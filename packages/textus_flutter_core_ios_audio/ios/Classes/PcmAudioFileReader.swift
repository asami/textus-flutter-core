import AVFoundation
import Foundation

/// Reads every actual CAF sample without assuming one read fills its request.
enum PcmAudioFileReader {
    struct Failure: Error {
        let code: String
        let message: String
    }

    static func readCanonicalWave(from url: URL) throws -> Data {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatInt16, interleaved: true)
        let actual = file.fileFormat
        let processing = file.processingFormat
        let expectedFrames = file.length
        guard actual.sampleRate == 16_000, actual.channelCount == 1,
              actual.commonFormat == .pcmFormatInt16,
              processing.sampleRate == 16_000, processing.channelCount == 1,
              processing.commonFormat == .pcmFormatInt16, processing.isInterleaved,
              expectedFrames >= 16, expectedFrames <= 1_920_000 else {
            throw Failure(code: "invalidAudio", message: "Recorded audio is not bounded 16 kHz mono PCM16")
        }
        let capacity = AVAudioFrameCount(min(8_192, expectedFrames))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: capacity) else {
            throw Failure(code: "recordingFailed", message: "Could not allocate the recorded PCM buffer")
        }
        var pcm = Data(capacity: Int(expectedFrames) * 2)
        var totalFrames: AVAudioFramePosition = 0
        while totalFrames < expectedFrames {
            guard file.length == expectedFrames, file.framePosition == totalFrames else {
                throw Failure(code: "recordingFailed", message: "Recorded PCM frame count changed while reading")
            }
            let requested = AVAudioFrameCount(min(AVAudioFramePosition(capacity), expectedFrames - totalFrames))
            buffer.frameLength = 0
            try file.read(into: buffer, frameCount: requested)
            let returned = buffer.frameLength
            guard returned > 0, returned <= requested,
                  let samples = buffer.int16ChannelData?[0] else {
                throw Failure(code: "recordingFailed", message: "Recorded PCM could not be read completely")
            }
            let nextTotal = totalFrames + AVAudioFramePosition(returned)
            guard nextTotal <= expectedFrames, file.length == expectedFrames,
                  file.framePosition == nextTotal else {
                throw Failure(code: "recordingFailed", message: "Recorded PCM frame count changed while reading")
            }
            for index in 0..<Int(returned) {
                let value = UInt16(bitPattern: samples[index])
                pcm.append(UInt8(truncatingIfNeeded: value))
                pcm.append(UInt8(truncatingIfNeeded: value >> 8))
            }
            totalFrames = nextTotal
        }
        guard totalFrames == expectedFrames, pcm.count == Int(expectedFrames) * 2 else {
            throw Failure(code: "recordingFailed", message: "Recorded PCM could not be read completely")
        }
        do {
            return try CanonicalPcmWaveAudio.encode(pcm)
        } catch is CanonicalPcmWaveAudio.Failure {
            throw Failure(code: "invalidAudio", message: "Recorded audio is not bounded 16 kHz mono PCM16")
        }
    }
}
