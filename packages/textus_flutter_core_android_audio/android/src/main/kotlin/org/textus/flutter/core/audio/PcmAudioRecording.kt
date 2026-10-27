package org.textus.flutter.core.audio

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.io.ByteArrayOutputStream
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext

/** Bounded microphone recording; a full buffer remains until explicit stop. */
internal class PcmAudioRecording(private val maxDurationSeconds: Int) {
    private var recorder: AudioRecord? = null
    private var reader: Deferred<ByteArray>? = null
    private val running = AtomicBoolean(false)
    private val released = AtomicBoolean(false)
    private val resourceLock = Any()
    private var capturedAt: String? = null

    suspend fun start(scope: CoroutineScope) {
        require(maxDurationSeconds in 1..120)
        check(recorder == null && !released.get()) { "Recording already started" }
        val audio = withContext(Dispatchers.IO) {
          synchronized(resourceLock) {
            if (released.get()) throw AudioFailure("cancelled", "Recording start cancelled")
            val minimum = AudioRecord.getMinBufferSize(16000,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            if (minimum <= 0) throw AudioFailure("recordingUnsupported", "Invalid AudioRecord buffer size: $minimum")
            val created = AudioRecord(MediaRecorder.AudioSource.MIC, 16000,
                AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                maxOf(minimum, 6400))
            if (created.state != AudioRecord.STATE_INITIALIZED) {
                created.release()
                throw AudioFailure("recordingInitialization", "AudioRecord was not initialized")
            }
            recorder = created
            try {
                created.startRecording()
                if (created.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
                    throw AudioFailure("recordingStart", "AudioRecord did not enter recording state")
                }
            } catch (error: Throwable) {
                release()
                throw error
            }
            // Assign before the cancellable dispatcher return so cancellation
            // cannot lose an allocated microphone resource.
            created
          }
        }
        capturedAt = DateTimeFormatter.ofPattern("uuuu-MM-dd'T'HH:mm:ss.SSS'Z'")
            .withZone(ZoneOffset.UTC).format(Instant.now())
        running.set(true)
        reader = scope.async(Dispatchers.IO) {
            val output = ByteArrayOutputStream()
            val maximum = maxDurationSeconds * 32000
            val block = ByteArray(6400)
            try {
                while (running.get() && output.size() < maximum) {
                    val remaining = maximum - output.size()
                    val count = audio.read(block, 0, minOf(block.size, remaining),
                        AudioRecord.READ_BLOCKING)
                    if (count < 0) {
                        if (!running.get()) break
                        throw AudioFailure("recordingRead", "AudioRecord.read returned $count")
                    }
                    if (count == 0) {
                        if (!running.get()) break
                        throw AudioFailure("recordingRead", "AudioRecord.read returned no samples")
                    }
                    if (count % 2 != 0) throw AudioFailure("recordingRead", "Incomplete PCM16 sample")
                    output.write(block, 0, count)
                }
                output.toByteArray()
            } finally {
                running.set(false)
                release()
            }
        }
    }

    suspend fun stop(): Map<String, Any?> {
        running.set(false)
        withContext(Dispatchers.IO) { stopRecorder() }
        val pcm = try {
            reader?.await() ?: throw AudioFailure("notRecording", "No active recorder")
        } finally { withContext(NonCancellable + Dispatchers.IO) { release() } }
        if (pcm.size < 32) throw AudioFailure("emptyRecording", "No complete millisecond of audio captured")
        return mapOf("bytes" to PcmWaveAudio.encode(pcm),
            "capturedAt" to capturedAt, "originalName" to "recording.wav")
    }

    suspend fun cancel() {
        running.set(false)
        withContext(NonCancellable + Dispatchers.IO) { stopRecorder() }
        try { reader?.await() } catch (_: Throwable) { /* Unsaved capture is discarded. */ }
        withContext(NonCancellable + Dispatchers.IO) { release() }
    }

    private fun stopRecorder() {
      synchronized(resourceLock) {
        val audio = recorder ?: return
        if (!released.get() && audio.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
            try { audio.stop() } catch (_: IllegalStateException) { /* Concurrent read termination. */ }
        }
      }
    }

    private fun release() {
      synchronized(resourceLock) {
        if (released.compareAndSet(false, true)) {
            val audio = recorder
            if (audio != null) {
                try { if (audio.recordingState == AudioRecord.RECORDSTATE_RECORDING) audio.stop() }
                finally { audio.release() }
            }
        }
      }
    }
}

/** Exact platform diagnostics carried through the Flutter channel. */
internal class AudioFailure(val code: String, override val message: String?) : Exception(message)
