import Foundation

/// The persisted Core PCM contract: one exact 44-byte header and PCM16 payload.
enum CanonicalPcmWaveAudio {
    static let minimumPcmBytes = 32
    static let maximumPcmBytes = 3_840_000

    enum Failure: Error {
        case invalidPcm
        case invalidWave
    }

    static func encode(_ pcm: Data) throws -> Data {
        guard validPayloadSize(pcm.count) else { throw Failure.invalidPcm }
        // Bounded before allocating or converting lengths to UInt32.
        var wave = Data(capacity: 44 + pcm.count)
        wave.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count), to: &wave)
        wave.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16), to: &wave)
        append(UInt16(1), to: &wave)
        append(UInt16(1), to: &wave)
        append(UInt32(16_000), to: &wave)
        append(UInt32(32_000), to: &wave)
        append(UInt16(2), to: &wave)
        append(UInt16(16), to: &wave)
        wave.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count), to: &wave)
        wave.append(pcm)
        return wave
    }

    /// Validates the original without repairing, resampling or accepting chunks.
    @discardableResult
    static func validate(_ wave: Data) throws -> Data {
        guard wave.count >= 44 + minimumPcmBytes,
              wave.count <= 44 + maximumPcmBytes else { throw Failure.invalidWave }
        let bytes = [UInt8](wave)
        func tag(_ offset: Int, _ text: String) -> Bool {
            Array(bytes[offset..<(offset + 4)]) == Array(text.utf8)
        }
        func u16(_ offset: Int) -> UInt16 {
            UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
        }
        let payload = wave.count - 44
        guard validPayloadSize(payload),
              tag(0, "RIFF"), tag(8, "WAVE"), tag(12, "fmt "), tag(36, "data"),
              u32(4) == UInt32(wave.count - 8), u32(16) == 16,
              u16(20) == 1, u16(22) == 1, u32(24) == 16_000,
              u32(28) == 32_000, u16(32) == 2, u16(34) == 16,
              u32(40) == UInt32(payload) else { throw Failure.invalidWave }
        return Data(bytes[44...])
    }

    private static func validPayloadSize(_ count: Int) -> Bool {
        count >= minimumPcmBytes && count <= maximumPcmBytes && count % 2 == 0
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
}
