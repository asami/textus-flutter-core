package org.textus.flutter.core.audio

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred

/** One player and its own private temporary WAV; durable originals are unknown. */
internal class AudioPlayback(private val context: Context) {
    private var player: MediaPlayer? = null
    private val temporary = PlaybackTemporaryFile(context.cacheDir)
    private var terminal: CompletableDeferred<Unit>? = null
    private var stopped = false

    suspend fun play(wave: ByteArray) {
        PcmWaveAudio.parse(wave)
        check(player == null && terminal == null)
        val completion = CompletableDeferred<Unit>()
        terminal = completion
        try {
            val file = temporary.write(wave)
            if (stopped) return
            val media = MediaPlayer()
            player = media
            media.setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            media.setOnPreparedListener {
                if (player === it && !stopped && !completion.isCompleted) {
                    try { it.start() }
                    catch (error: Throwable) {
                        completion.completeExceptionally(AudioFailure("playbackStart", error.message))
                    }
                }
            }
            media.setOnCompletionListener { completion.complete(Unit) }
            media.setOnErrorListener { _, what, extra ->
                completion.completeExceptionally(AudioFailure("playbackError", "MediaPlayer error $what/$extra"))
                true
            }
            media.setDataSource(file.absolutePath)
            media.prepareAsync()
            completion.await()
        } finally { stop() }
    }

    suspend fun stop() {
        stopped = true
        val ownedPlayer = player
        player = null
        var failure: Throwable? = null
        fun retain(error: Throwable) {
            val first = failure
            if (first == null) failure = error
            else if (first !== error) first.addSuppressed(error)
        }
        fun attempt(block: () -> Unit) {
            try { block() } catch (error: Throwable) { retain(error) }
        }
        attempt { ownedPlayer?.setOnPreparedListener(null) }
        attempt { ownedPlayer?.setOnCompletionListener(null) }
        attempt { ownedPlayer?.setOnErrorListener(null) }
        attempt { ownedPlayer?.release() }
        attempt { terminal?.complete(Unit) }
        try {
            temporary.cleanup()
        } catch (error: IOException) {
            retain(AudioFailure("playbackCleanup", "Could not delete owned temporary WAV").also {
                it.initCause(error)
            })
        } catch (error: Throwable) {
            retain(error)
        }
        failure?.let { throw it }
    }
}
