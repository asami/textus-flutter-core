package org.textus.flutter.core.audio

import java.io.File
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Owns one playback WAV through writing, cancellation and retryable cleanup. */
internal class PlaybackTemporaryFile(
    private val directory: File,
    private val beforeWrite: (File) -> Unit = {},
    private val beforeCleanup: () -> Unit = {},
    private val deleteFile: (File) -> Boolean = { it.delete() },
) {
    private val mutex = Mutex()
    private var owned: File? = null
    private var closed = false

    suspend fun write(bytes: ByteArray): File = withContext(Dispatchers.IO) {
        mutex.withLock {
            check(!closed) { "Playback temporary-file owner is closed" }
            check(owned == null) { "Playback temporary-file owner already has a WAV" }
            val file = File.createTempFile("textus-audio-", ".wav", directory)
            // Publish before hooks or writing can fail, including cancelled returns.
            owned = file
            beforeWrite(file)
            file.writeBytes(bytes)
            file
        }
    }

    suspend fun cleanup(): Unit = withContext(NonCancellable + Dispatchers.IO) {
        beforeCleanup()
        mutex.withLock {
            closed = true
            val file = owned
            if (file != null) {
                if (file.exists() && !deleteFile(file) && file.exists()) {
                    throw IOException("Could not delete owned temporary WAV")
                }
                // Failed deletion or an exception retains the exact path for retry.
                owned = null
            }
        }
    }
}
