import AVFoundation
import Foundation

/// The file a recording is saved as.
enum AudioFormat: String, CaseIterable {
    /// Plays and uploads anywhere. Recorded as AAC, then converted with LAME when you stop.
    case mp3
    /// AAC, written straight to disk.
    case m4a
}

@MainActor
final class MeetingRecorder: NSObject, AVAudioRecorderDelegate {
    enum State: Equatable {
        case idle
        case requestingPermission
        case recording
        case paused

        var isActive: Bool { self == .recording || self == .paused }
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    var onStateChange: ((State) -> Void)?
    var onSaved: ((URL, TimeInterval) -> Void)?
    var onError: ((String) -> Void)?
    /// Called with true while finished recordings are being converted to MP3.
    var onExportingChange: ((Bool) -> Void)?

    /// Whether any recording is still being converted (for example when the app quits).
    var isExporting: Bool { exports > 0 }

    private var recorder: AVAudioRecorder?
    private var activity: NSObjectProtocol?
    private var interruptionCheck: Timer?
    private var format: AudioFormat = .mp3
    private var bitRate = 32_000
    private var exports = 0 {
        didSet { if (exports > 0) != (oldValue > 0) { onExportingChange?(exports > 0) } }
    }

    func start(in directory: URL, bitRate: Int = 32_000, format: AudioFormat = .mp3) {
        guard state == .idle else { return }
        self.format = format
        self.bitRate = bitRate

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startRecording(in: directory, bitRate: bitRate)
        case .notDetermined:
            state = .requestingPermission
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.startRecording(in: directory, bitRate: bitRate)
                    } else {
                        self.state = .idle
                        self.reportDeniedPermission()
                    }
                }
            }
        case .denied, .restricted:
            reportDeniedPermission()
        @unknown default:
            reportDeniedPermission()
        }
    }

    func stop() {
        guard let recorder else { return }
        let problem = state == .recording && !recorder.isRecording ? "The microphone stopped recording." : nil
        finish(recorder, problem: problem)
    }

    func pause() {
        guard state == .recording, let recorder else { return }
        recorder.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused, let recorder else { return }
        guard recorder.record() else {
            finish(recorder, problem: "Couldn’t resume the microphone.")
            return
        }
        state = .recording
    }

    /// Current input level from 0 (silence) to 1 (full scale).
    func level() -> Double {
        guard state == .recording, let recorder else { return 0 }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        return max(0, min(1, (decibels + 50) / 50))
    }

    /// The name of the microphone macOS records from.
    var inputName: String? { AVCaptureDevice.default(for: .audio)?.localizedName }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self, let recorder = self.recorder, recorder.url == url else { return }
            let problem = flag ? "Recording ended unexpectedly." : "The audio recorder could not finish."
            self.finish(recorder, problem: problem)
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let url = recorder.url
        let problem = error?.localizedDescription ?? "The audio encoder stopped."
        Task { @MainActor [weak self] in
            guard let self, let recorder = self.recorder, recorder.url == url else { return }
            self.finish(recorder, problem: problem)
        }
    }

    private func startRecording(in directory: URL, bitRate: Int) {
        let fileManager = FileManager.default
        let url = recordingURL(in: directory)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 24_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant
        ]

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                recorder.delegate = nil
                recorder.stop()
                try? fileManager.removeItem(at: url)
                if state != .idle { state = .idle }
                onError?("Couldn’t start the microphone. Check the selected device in System Settings → Sound → Input.")
                return
            }

            self.recorder = recorder
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Recording a meeting")

            // Some input interruptions stop the recorder without a delegate callback.
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.state == .recording, let recorder = self.recorder, !recorder.isRecording else { return }
                    self.finish(recorder, problem: "The microphone stopped recording.")
                }
            }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            interruptionCheck = timer
            state = .recording
        } catch {
            try? fileManager.removeItem(at: url)
            if state != .idle { state = .idle }
            onError?("Couldn’t start recording. \(error.localizedDescription)")
        }
    }

    private func finish(_ recorder: AVAudioRecorder, problem: String?) {
        let url = recorder.url
        recorder.delegate = nil
        recorder.stop()
        self.recorder = nil

        interruptionCheck?.invalidate()
        interruptionCheck = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        state = .idle

        if let file = try? AVAudioFile(forReading: url), file.length > 0 {
            let duration = Double(file.length) / file.fileFormat.sampleRate
            guard format == .mp3 else {
                report(url, duration: duration, problem: problem)
                return
            }
            let mp3 = url.deletingPathExtension().appendingPathExtension("mp3")
            let bitRate = bitRate
            exports += 1
            Task.detached(priority: .userInitiated) {
                let failure: String?
                do {
                    try MP3Export.convert(url, to: mp3, bitRate: bitRate)
                    try? FileManager.default.removeItem(at: url)
                    failure = nil
                } catch {
                    failure = error.localizedDescription
                }
                await MainActor.run {
                    self.exports -= 1
                    if let failure {
                        // The AAC recording is untouched, so nothing is lost.
                        self.onError?("Couldn’t convert the recording to MP3. \(failure) The recording was kept as M4A at:\n\(url.path)")
                    } else {
                        self.report(mp3, duration: duration, problem: problem)
                    }
                }
            }
        } else if FileManager.default.fileExists(atPath: url.path) {
            let detail = problem ?? "Couldn’t read any audio from this recording."
            onError?("\(detail) The file is at:\n\(url.path)")
        } else {
            onError?(problem ?? "Couldn’t save the recording.")
        }
    }

    private func report(_ url: URL, duration: TimeInterval, problem: String?) {
        if let problem {
            onError?("\(problem) The audio captured so far was saved at:\n\(url.path)")
        } else {
            onSaved?(url, duration)
        }
    }

    /// Always AAC while recording; the name is also free as `.mp3`, for the conversion afterwards.
    private func recordingURL(in directory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        var name = "Meeting \(formatter.string(from: Date()))"
        let taken = { (name: String) in
            ["m4a", "mp3"].contains { FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(name).\($0)").path) }
        }
        if taken(name) { name += "-\(UUID().uuidString.prefix(8))" }
        return directory.appendingPathComponent("\(name).m4a")
    }

    private func reportDeniedPermission() {
        onError?("Allow FishMic to use the microphone in System Settings → Privacy & Security → Microphone.")
    }
}
