package org.textus.flutter.core.audio

import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PcmWaveAudioTest {
    @Test
    fun exactSamplesDurationAndDetachedPayload() {
        // Given 16001 exact mono PCM16 samples in mutable caller bytes.
        val pcm = ByteArray(32002) { (it % 256).toByte() }
        val expected = pcm.copyOf()
        // When the actual helper encodes/parses and caller inputs mutate.
        val wave = PcmWaveAudio.encode(pcm)
        val parsed = PcmWaveAudio.parse(wave)
        pcm[0] = 99
        wave[44] = 88
        // Then exact samples and floored whole milliseconds remain independent.
        assertArrayEquals(expected, parsed.pcm)
        assertEquals(1000L, parsed.durationMilliseconds)
        assertEquals(32046, wave.size)
        assertArrayEquals(expected, PcmWaveAudio.parse(PcmWaveAudio.encode(expected)).pcm)
    }

    @Test
    fun malformedHeadersAndDeclaredSizesAreRejected() {
        // Given valid canonical audio and each frozen format/header field.
        val valid = PcmWaveAudio.encode(ByteArray(32000))
        val replacements = mapOf(4 to 0, 16 to 18, 20 to 3, 22 to 2,
            24 to 44100, 28 to 64000, 32 to 4, 34 to 8, 40 to 31998)
        // When each header field or mandatory chunk tag is corrupted separately.
        replacements.forEach { (offset, value) ->
            val invalid = valid.copyOf()
            val buffer = ByteBuffer.wrap(invalid).order(ByteOrder.LITTLE_ENDIAN)
            if (offset in listOf(20, 22, 32, 34)) buffer.putShort(offset, value.toShort())
            else buffer.putInt(offset, value)
            // Then the actual parser rejects unsupported headers instead of misreading PCM.
            assertThrows(IllegalArgumentException::class.java) { PcmWaveAudio.parse(invalid) }
        }
        listOf(0, 8, 12, 36).forEach { offset ->
            val invalid = valid.copyOf()
            invalid[offset] = 0
            assertThrows(IllegalArgumentException::class.java) { PcmWaveAudio.parse(invalid) }
        }
    }

    @Test
    fun emptyOddTruncatedExtraAndOverLimitDataAreRejected() {
        // Given canonical audio and payloads outside the exact bounded schema.
        val valid = PcmWaveAudio.encode(ByteArray(32))
        val badPcm = listOf(ByteArray(0), ByteArray(2), ByteArray(33), ByteArray(3840002))
        // When invalid payloads encode or truncated/extra/empty waveforms parse.
        badPcm.forEach { pcm ->
            // Then encoding cannot silently repair payload size or duration.
            assertThrows(IllegalArgumentException::class.java) { PcmWaveAudio.encode(pcm) }
        }
        listOf(ByteArray(0), valid.copyOf(43), valid.copyOf(valid.size - 1),
            valid + byteArrayOf(0, 0), valid.copyOf(44)).forEach { wave ->
            assertThrows(IllegalArgumentException::class.java) { PcmWaveAudio.parse(wave) }
        }
        listOf(0, 1, 2, 33, 3840002).forEach { size ->
            val invalid = valid.copyOf(44 + size)
            val header = ByteBuffer.wrap(invalid).order(ByteOrder.LITTLE_ENDIAN)
            header.putInt(4, invalid.size - 8)
            header.putInt(40, size)
            assertThrows(IllegalArgumentException::class.java) { PcmWaveAudio.parse(invalid) }
        }
    }

    @Test
    fun exactDurationCapIsAcceptedWithoutTruncation() {
        // Given exactly 120 seconds of PCM16LE mono 16 kHz payload.
        val pcm = ByteArray(PcmWaveAudio.MAXIMUM_PCM_BYTES)
        // When the actual helper encodes and parses the largest supported original.
        val parsed = PcmWaveAudio.parse(PcmWaveAudio.encode(pcm))
        // Then the full payload and duration equal the public Dart boundary.
        assertEquals(3840000, parsed.pcm.size)
        assertEquals(120000L, parsed.durationMilliseconds)
        assertArrayEquals(pcm, parsed.pcm)
    }
}

class AudioCleanupLifecycleTest {
    @Test
    fun recordingAndSavingOriginsJoinMatchingRecordingCleanup() {
        // Given each actual recording/stop origin on a separate cleanup lifecycle.
        listOf("recording", "saving").forEach { origin ->
            val lifecycle = AudioCleanupLifecycle()
            assertFalse(lifecycle.hasActive)
            // When pause or explicit cancellation begins cleanup of that operation.
            lifecycle.begin(origin)
            // Then recording cleanup can join once without accepting playback cleanup.
            assertTrue(lifecycle.hasActive)
            assertTrue(lifecycle.canJoin(setOf("recording", "saving")))
            assertFalse(lifecycle.canJoin(setOf("playing")))
        }
    }

    @Test
    fun playingOriginMatchesOnlyPlaybackCleanup() {
        // Given a lifecycle with cleanup started for playback.
        val lifecycle = AudioCleanupLifecycle()
        lifecycle.begin("playing")
        // When matching and unrelated interruption sets ask to join.
        val matching = lifecycle.canJoin(setOf("playing"))
        val recording = lifecycle.canJoin(setOf("recording", "saving"))
        val transcription = lifecycle.canJoin(setOf("availability", "prepare", "transcribing"))
        // Then only the playback set matches the active origin.
        assertTrue(matching)
        assertFalse(recording)
        assertFalse(transcription)
        assertTrue(lifecycle.hasActive)
    }

    @Test
    fun idleAndUnrelatedCleanupSetsCannotJoin() {
        // Given an idle lifecycle followed by cleanup of explicit preparation.
        val lifecycle = AudioCleanupLifecycle()
        assertFalse(lifecycle.canJoin(setOf("prepare")))
        // When preparation cleanup begins and unrelated sets request joining.
        lifecycle.begin("prepare")
        // Then recording, playback and empty sets reject while preparation matches.
        assertFalse(lifecycle.canJoin(setOf("recording", "saving")))
        assertFalse(lifecycle.canJoin(setOf("playing")))
        assertFalse(lifecycle.canJoin(emptySet()))
        assertTrue(lifecycle.canJoin(setOf("availability", "prepare", "transcribing")))
    }

    @Test
    fun finishClearsOriginAndPermitsNewCleanup() {
        // Given cleanup of a recording on the actual reusable helper.
        val lifecycle = AudioCleanupLifecycle()
        lifecycle.begin("recording")
        // When cleanup finishes and a later playback cleanup begins.
        lifecycle.finish()
        assertFalse(lifecycle.hasActive)
        assertFalse(lifecycle.canJoin(setOf("recording")))
        lifecycle.begin("playing")
        // Then only the new operation can be joined and finishing returns idle.
        assertTrue(lifecycle.hasActive)
        assertTrue(lifecycle.canJoin(setOf("playing")))
        assertFalse(lifecycle.canJoin(setOf("recording")))
        lifecycle.finish()
        assertFalse(lifecycle.hasActive)
    }

    @Test
    fun duplicateBeginRejectsWithoutReplacingActiveOrigin() {
        // Given a cleanup lifecycle already owned by recording.
        val lifecycle = AudioCleanupLifecycle()
        lifecycle.begin("recording")
        // When another operation tries to begin before the first cleanup finishes.
        assertThrows(IllegalStateException::class.java) { lifecycle.begin("playing") }
        // Then duplicate cleanup is rejected and the original matching set stays authoritative.
        assertTrue(lifecycle.hasActive)
        assertTrue(lifecycle.canJoin(setOf("recording", "saving")))
        assertFalse(lifecycle.canJoin(setOf("playing")))
    }
}

class AudioPermissionLifecycleTest {
    @Test
    fun pausedGrantWaitsForResumeAndLaunchesOnce() {
        // Given the actual lifecycle helper before any foreground resume.
        val lifecycle = AudioPermissionLifecycle()
        assertFalse(lifecycle.isResumed)
        // When permission is granted while paused and the same Activity resumes twice.
        val immediate = lifecycle.grant()
        val firstResume = lifecycle.resume()
        val repeatedResume = lifecycle.resume()
        // Then only the first foreground resume consumes the deferred launch.
        assertFalse(immediate)
        assertTrue(firstResume)
        assertFalse(repeatedResume)
        assertTrue(lifecycle.isResumed)
    }

    @Test
    fun cancellationBeforeResumeDropsDeferredGrant() {
        // Given a permission grant deferred while the Activity is paused.
        val lifecycle = AudioPermissionLifecycle()
        assertFalse(lifecycle.grant())
        // When cancellation occurs before foreground resume.
        lifecycle.cancel()
        val launch = lifecycle.resume()
        // Then cancelled permission cannot launch on this or a repeated resume.
        assertFalse(launch)
        assertFalse(lifecycle.resume())
    }

    @Test
    fun foregroundGrantLaunchesImmediatelyWithoutDeferredDuplicate() {
        // Given an Activity whose authoritative resume has been observed.
        val lifecycle = AudioPermissionLifecycle()
        assertFalse(lifecycle.resume())
        // When explicit permission is granted while foreground.
        val launch = lifecycle.grant()
        // Then immediate launch is allowed and no deferred launch remains.
        assertTrue(launch)
        assertFalse(lifecycle.resume())
    }

    @Test
    fun pauseRetainsGrantUntilForegroundReturns() {
        // Given a foreground Activity which pauses for explicit permission UI.
        val lifecycle = AudioPermissionLifecycle()
        lifecycle.resume()
        lifecycle.pause()
        // When a grant arrives and another pause precedes resume.
        val immediate = lifecycle.grant()
        lifecycle.pause()
        // Then microphone launch stays deferred until one foreground resume.
        assertFalse(immediate)
        assertFalse(lifecycle.isResumed)
        assertTrue(lifecycle.resume())
        assertFalse(lifecycle.resume())
    }

    @Test
    fun repeatedPausedGrantStillConsumesOneLaunch() {
        // Given the helper with no foreground Activity.
        val lifecycle = AudioPermissionLifecycle()
        // When duplicate grant notifications arrive before resume.
        val first = lifecycle.grant()
        val duplicate = lifecycle.grant()
        // Then both are deferred and resume permits only one launch.
        assertFalse(first)
        assertFalse(duplicate)
        assertTrue(lifecycle.resume())
        assertFalse(lifecycle.resume())
    }
}
