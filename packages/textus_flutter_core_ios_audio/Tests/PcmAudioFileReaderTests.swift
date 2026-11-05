import AVFoundation
import Foundation
import XCTest
@testable import AudioContracts

final class PcmAudioFileReaderTests: XCTestCase {
    func testLongCafFilesPreserveEverySampleIncludingTheTail() throws {
        for frameCount in [320_001, 329_937, 1_920_000] {
            // Given a closed real 16 kHz mono PCM16 CAF with a varying known sample sequence.
            let url = temporaryCafURL()
            defer { try? FileManager.default.removeItem(at: url) }
            let format = try pcmFormat()
            try writeCaf(at: url, format: format, frameCount: frameCount)
            let expected = expectedPcm(frameCount: frameCount)
            // When the production reader extracts the CAF and the production codec decodes its WAV.
            let wave = try PcmAudioFileReader.readCanonicalWave(from: url)
            let decoded = try CanonicalPcmWaveAudio.validate(wave)
            // Then the exact original sequence, complete suffix and 44-byte canonical header survive.
            XCTAssertEqual(wave.count, 44 + frameCount * 2, "CAF frames: \(frameCount)")
            XCTAssertEqual(decoded, expected, "CAF frames: \(frameCount)")
            XCTAssertEqual(Data(decoded.suffix(64)), Data(expected.suffix(64)), "CAF tail: \(frameCount)")
        }
    }

    func testShortCafControlPreservesEverySample() throws {
        // Given a closed real 320-frame PCM16 CAF using the same varying sequence as long captures.
        let url = temporaryCafURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCaf(at: url, format: pcmFormat(), frameCount: 320)
        let expected = expectedPcm(frameCount: 320)
        // When the production reader extracts the actual saved CAF.
        let wave = try PcmAudioFileReader.readCanonicalWave(from: url)
        let decoded = try CanonicalPcmWaveAudio.validate(wave)
        // Then the short control also retains its full sequence and exact canonical length.
        XCTAssertEqual(decoded, expected)
        XCTAssertEqual(wave.count, 44 + 320 * 2)
    }

    func testActualSampleRateStereoAndFloatCafFilesAreRejected() throws {
        let formats = [
            try pcmFormat(sampleRate: 44_100),
            try pcmFormat(channels: 2),
            try pcmFormat(commonFormat: .pcmFormatFloat32)
        ]
        for format in formats {
            // Given a real CAF whose stored sample rate, channel count or sample representation is foreign.
            let url = temporaryCafURL()
            defer { try? FileManager.default.removeItem(at: url) }
            try writeCaf(at: url, format: format, frameCount: 320)
            // When production extraction receives that file without a conversion allowance.
            // Then it reports invalidAudio instead of resampling, mixing or accepting float originals.
            XCTAssertThrowsError(try PcmAudioFileReader.readCanonicalWave(from: url)) { error in
                // Given the actual rejected file / When inspecting its failure / Then keep the native code.
                XCTAssertEqual((error as? PcmAudioFileReader.Failure)?.code, "invalidAudio")
            }
        }
    }

    func testActualSubmillisecondAndOver120SecondCafFilesAreRejected() throws {
        for frameCount in [15, 1_920_001] {
            // Given a real canonical-format CAF with actual frames outside the 1 ms through 120 s bounds.
            let url = temporaryCafURL()
            defer { try? FileManager.default.removeItem(at: url) }
            try writeCaf(at: url, format: pcmFormat(), frameCount: frameCount)
            // When production extraction inspects the stored frame length.
            // Then the file fails with invalidAudio rather than truncation, padding or duration estimation.
            XCTAssertThrowsError(try PcmAudioFileReader.readCanonicalWave(from: url)) { error in
                // Given the actual rejected length / When inspecting its failure / Then keep the native code.
                XCTAssertEqual((error as? PcmAudioFileReader.Failure)?.code, "invalidAudio")
            }
        }
    }

    private func temporaryCafURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
    }

    private func pcmFormat(
        sampleRate: Double = 16_000,
        channels: AVAudioChannelCount = 1,
        commonFormat: AVAudioCommonFormat = .pcmFormatInt16
    ) throws -> AVAudioFormat {
        try XCTUnwrap(AVAudioFormat(
            commonFormat: commonFormat, sampleRate: sampleRate, channels: channels, interleaved: true
        ))
    }

    private func writeCaf(at url: URL, format: AVAudioFormat, frameCount: Int) throws {
        // Given a test-owned UUID path and the actual format required by this scenario.
        // The writer remains local to this call and is released before the reader is invoked.
        let writer = try AVAudioFile(
            forWriting: url, settings: format.settings,
            commonFormat: format.commonFormat, interleaved: true
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_192))
        var written = 0
        while written < frameCount {
            let frames = min(8_192, frameCount - written)
            buffer.frameLength = AVAudioFrameCount(frames)
            for frame in 0..<frames {
                for channel in 0..<Int(format.channelCount) {
                    let sample = sampleValue(frame: written + frame, channel: channel)
                    let offset = frame * Int(format.channelCount) + channel
                    if format.commonFormat == .pcmFormatInt16 {
                        let samples = try XCTUnwrap(buffer.int16ChannelData?[0])
                        samples[offset] = sample
                    } else {
                        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
                        samples[offset] = Float(sample) / 32_768
                    }
                }
            }
            // When AVFoundation writes the varying actual sample buffer into the CAF.
            try writer.write(from: buffer)
            written += frames
        }
        // Then the fixture has the exact actual frame length before its writer lifetime ends.
        XCTAssertEqual(writer.length, AVAudioFramePosition(frameCount))
    }

    private func sampleValue(frame: Int, channel: Int = 0) -> Int16 {
        Int16(truncatingIfNeeded: frame &* 31 &+ channel &* 997 &+ 7)
    }

    private func expectedPcm(frameCount: Int) -> Data {
        var bytes = Data(capacity: frameCount * 2)
        for frame in 0..<frameCount {
            let value = UInt16(bitPattern: sampleValue(frame: frame))
            bytes.append(UInt8(truncatingIfNeeded: value))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        return bytes
    }
}
