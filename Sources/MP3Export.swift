import AVFoundation
import Foundation

/// Converts a finished recording to MP3 with LAME. macOS has no MP3 encoder of its own,
/// so FishMic records AAC (streamed to disk, safe for long meetings) and converts it when you stop.
enum MP3Export {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Writes `source` as a constant-bit-rate MP3 at `destination`.
    /// The MP3 appears only once it's complete; a failure leaves nothing behind.
    static func convert(_ source: URL, to destination: URL, bitRate: Int) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let channels = Int(format.channelCount)
        guard channels > 0, format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
            throw Failure("The recording has an audio format FishMic can’t convert.")
        }

        guard let lame = lame_init() else { throw Failure("Couldn’t start the MP3 encoder.") }
        defer { lame_close(lame) }
        lame_set_num_channels(lame, Int32(min(channels, 2)))
        lame_set_in_samplerate(lame, Int32(format.sampleRate.rounded()))
        lame_set_out_samplerate(lame, 24_000)
        lame_set_mode(lame, MONO)
        lame_set_VBR(lame, vbr_off)
        lame_set_brate(lame, Int32(bitRate / 1000))
        lame_set_quality(lame, 5) // LAME's balance of speed and quality: about 10 s per hour of audio
        lame_set_bWriteVbrTag(lame, 1) // a LAME/Xing header, so players show the right duration
        guard lame_init_params(lame) >= 0 else { throw Failure("The MP3 encoder rejected its settings.") }

        let directory = destination.deletingLastPathComponent()
        let partial = directory.appendingPathComponent(".\(destination.lastPathComponent).partial")
        let fileManager = FileManager.default
        guard fileManager.createFile(atPath: partial.path, contents: nil) else {
            throw Failure("Couldn’t create \(destination.lastPathComponent).")
        }
        var finished = false
        defer { if !finished { try? fileManager.removeItem(at: partial) } }
        let output = try FileHandle(forWritingTo: partial)
        defer { try? output.close() }

        let chunk: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else {
            throw Failure("Couldn’t allocate an audio buffer.")
        }
        var mp3 = [UInt8](repeating: 0, count: Int(chunk) * 5 / 4 + 7_200)

        while input.framePosition < input.length {
            try input.read(into: buffer, frameCount: chunk)
            let frames = Int32(buffer.frameLength)
            if frames == 0 { break }
            guard let data = buffer.floatChannelData else { throw Failure("Couldn’t read the recording.") }
            let left = data[0]
            let right = channels > 1 ? data[1] : data[0]
            let count = mp3.withUnsafeMutableBufferPointer { out in
                lame_encode_buffer_ieee_float(lame, left, right, frames, out.baseAddress, Int32(out.count))
            }
            guard count >= 0 else { throw Failure("The MP3 encoder failed (\(count)).") }
            try output.write(contentsOf: mp3[0..<Int(count)])
        }

        let tail = mp3.withUnsafeMutableBufferPointer { out in
            lame_encode_flush(lame, out.baseAddress, Int32(out.count))
        }
        guard tail >= 0 else { throw Failure("The MP3 encoder failed (\(tail)).") }
        try output.write(contentsOf: mp3[0..<Int(tail)])

        // LAME left an empty first frame; fill it with the final tag now that the length is known.
        var tag = [UInt8](repeating: 0, count: 2_880)
        let tagSize = tag.withUnsafeMutableBufferPointer { lame_get_lametag_frame(lame, $0.baseAddress, $0.count) }
        if tagSize > 0, tagSize <= tag.count {
            try output.seek(toOffset: 0)
            try output.write(contentsOf: tag[0..<tagSize])
        }
        try output.close()

        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: partial, to: destination)
        finished = true
    }
}
