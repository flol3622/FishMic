import AVFoundation
import Foundation

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

    private var recorder: AVAudioRecorder?
    private var activity: NSObjectProtocol?
    private var interruptionCheck: Timer?

    func start(in directory: URL, bitRate: Int = 32_000) {
        guard state == .idle else { return }

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
            if let problem {
                onError?("\(problem) The audio captured so far was saved at:\n\(url.path)")
            } else {
                onSaved?(url, Double(file.length) / file.fileFormat.sampleRate)
            }
        } else if FileManager.default.fileExists(atPath: url.path) {
            let detail = problem ?? "Couldn’t read any audio from this recording."
            onError?("\(detail) The file is at:\n\(url.path)")
        } else {
            onError?(problem ?? "Couldn’t save the recording.")
        }
    }

    private func recordingURL(in directory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Meeting \(formatter.string(from: Date()))"
        let url = directory.appendingPathComponent("\(name).m4a")
        if FileManager.default.fileExists(atPath: url.path) {
            return directory.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(8)).m4a")
        }
        return url
    }

    private func reportDeniedPermission() {
        onError?("Allow FishMic to use the microphone in System Settings → Privacy & Security → Microphone.")
    }
}
