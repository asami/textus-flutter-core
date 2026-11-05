import Foundation
import XCTest
@testable import AudioContracts

final class AudioContractTests: XCTestCase {
    func testMinimumAndMaximumActualSamplesRoundTripUnchanged() throws {
        // Given real varying little-endian PCM samples at the exact 1 ms/120 s bounds.
        for sampleCount in [16, 1_920_000] {
            let original = pcm(sampleCount)
            // When canonical WAV is encoded and validated by the production helper.
            let wave = try CanonicalPcmWaveAudio.encode(original)
            let decoded = try CanonicalPcmWaveAudio.validate(wave)
            // Then every sample survives unchanged and the header has the exact bounded length.
            XCTAssertEqual(wave.count, 44 + sampleCount * 2)
            XCTAssertEqual(decoded, original)
            XCTAssertEqual(Array(wave.prefix(4)), Array("RIFF".utf8))
            XCTAssertEqual(Array(wave[36..<40]), Array("data".utf8))
        }
    }

    func testInvalidPcmCannotBeEncoded() {
        // Given empty, submillisecond, odd and oversized actual PCM payloads.
        let invalid = [Data(), Data(repeating: 1, count: 30), Data(repeating: 1, count: 33),
                       Data(repeating: 1, count: 3_840_002)]
        // When encoding is requested.
        for pcm in invalid {
            // Then each payload fails instead of allocating a plausible canonical original.
            XCTAssertThrowsError(try CanonicalPcmWaveAudio.encode(pcm))
        }
    }

    func testCorruptHeadersTruncationExtraChunksAndTrailingBytesAreRejected() throws {
        // Given one valid saved original and independent header/chunk/length corruption.
        let valid = try CanonicalPcmWaveAudio.encode(pcm(32))
        var invalid = [Data(), Data(valid.prefix(43)), Data(valid.dropLast()), valid + Data([1, 2])]
        for offset in [0, 4, 8, 12, 16, 20, 22, 24, 28, 32, 34, 36, 40] {
            var corrupt = valid
            corrupt[offset] ^= 1
            invalid.append(corrupt)
        }
        var extraChunk = valid
        extraChunk.insert(contentsOf: Array("JUNK".utf8) + [0, 0, 0, 0], at: 36)
        set32(&extraChunk, 4, UInt32(extraChunk.count - 8))
        invalid.append(extraChunk)
        // When each malformed saved byte sequence is validated.
        for wave in invalid {
            // Then no truncation, extra chunk, header contradiction or trailing data is repaired.
            XCTAssertThrowsError(try CanonicalPcmWaveAudio.validate(wave))
        }
    }

    func testZeroOddSubmillisecondAndOversizedWavesAreRejectedEvenWithMatchingLengths() throws {
        // Given correctly sized headers with payloads outside Core's exact PCM bounds.
        let header = Data(try CanonicalPcmWaveAudio.encode(pcm(16)).prefix(44))
        for count in [0, 2, 30, 33, 3_840_002] {
            var wave = header + Data(repeating: 17, count: count)
            set32(&wave, 4, UInt32(wave.count - 8))
            set32(&wave, 40, UInt32(count))
            // When the same production validation used for playback/recognition receives it.
            // Then matching outer lengths cannot make invalid PCM acceptable.
            XCTAssertThrowsError(try CanonicalPcmWaveAudio.validate(wave))
        }
    }

    func testCancelBeforePermissionGrantPreventsMediaAcquisition() throws {
        // Given a pending permission generation with no activated media.
        let owner = AudioOperationOwner()
        let pending = try owner.acquire(sessionID: "recording")
        // When cancellation retires it before a delayed permission grant arrives.
        owner.retire(pending)
        // Then the old callback cannot acquire media or publish as current.
        XCTAssertFalse(owner.isCurrent(pending))
        XCTAssertThrowsError(try owner.acquireMedia(pending))
        XCTAssertFalse(owner.ownsMedia(pending))
    }

    func testOldCompletionCannotRetireOrReleaseItsSuccessor() throws {
        // Given a cancelled generation and a successor holding the media lease.
        let owner = AudioOperationOwner()
        let old = try owner.acquire(sessionID: "same")
        try owner.acquireMedia(old)
        XCTAssertTrue(owner.retire(old))
        let next = try owner.acquire(sessionID: "same")
        try owner.acquireMedia(next)
        // When the old permission, timer or completion callback tries to retire/acquire.
        XCTAssertFalse(owner.retire(old))
        XCTAssertThrowsError(try owner.acquireMedia(old))
        // Then the successor still owns media and is the only current generation.
        XCTAssertFalse(owner.isCurrent(old))
        XCTAssertTrue(owner.isCurrent(next))
        XCTAssertTrue(owner.ownsMedia(next))
    }

    func testDisposalIsTerminalAndIdempotentAcrossPendingCallbacks() throws {
        // Given a current media owner.
        let owner = AudioOperationOwner()
        let token = try owner.acquire(sessionID: "terminal")
        try owner.acquireMedia(token)
        // When it is disposed repeatedly before a delayed callback.
        XCTAssertTrue(owner.dispose(sessionID: "terminal"))
        XCTAssertFalse(owner.dispose(sessionID: "terminal"))
        // Then neither a new operation nor the disposed token can reacquire or publish.
        XCTAssertTrue(owner.isDisposed(sessionID: "terminal"))
        XCTAssertThrowsError(try owner.acquire(sessionID: "terminal"))
        XCTAssertThrowsError(try owner.acquireMedia(token))
        XCTAssertFalse(owner.isCurrent(token))
    }

    func testAnotherSessionCannotReleaseTheActiveOwnerAndBusyIsObservable() throws {
        // Given one active physical media lease and a distinct logical operation.
        let owner = AudioOperationOwner()
        let active = try owner.acquire(sessionID: "active")
        try owner.acquireMedia(active)
        let other = try owner.acquire(sessionID: "other")
        // When the other session attempts overlapping media, cleanup and terminal disposal.
        XCTAssertThrowsError(try owner.acquireMedia(other))
        XCTAssertThrowsError(try owner.acquire(sessionID: "active"))
        XCTAssertFalse(owner.retire(other))
        XCTAssertFalse(owner.dispose(sessionID: "other"))
        // Then only the active token can release its own resources.
        XCTAssertTrue(owner.ownsMedia(active))
        XCTAssertTrue(owner.isCurrent(active))
        XCTAssertTrue(owner.retire(active))
        XCTAssertFalse(owner.ownsMedia(active))
    }

    private func pcm(_ samples: Int) -> Data {
        var data = Data(capacity: samples * 2)
        for index in 0..<samples {
            let value = UInt16(truncatingIfNeeded: index &* 31 &+ 7)
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        return data
    }

    private func set32(_ data: inout Data, _ offset: Int, _ value: UInt32) {
        for index in 0..<4 { data[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8)) }
    }
}
