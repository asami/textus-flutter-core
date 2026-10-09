package org.textus.flutter.core.audio

import android.os.Build
import android.os.ParcelFileDescriptor
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.audio.AudioSource
import com.google.mlkit.genai.speechrecognition.SpeechRecognition
import com.google.mlkit.genai.speechrecognition.SpeechRecognizer
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerResponse
import com.google.mlkit.genai.speechrecognition.speechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.speechRecognizerRequest
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/** Explicit Basic model preparation and paced recognition from saved PCM only. */
internal class SavedAudioTranscriber {
    private var client: SpeechRecognizer? = null
    private var pipe: Array<ParcelFileDescriptor>? = null

    suspend fun availability(localeTag: String): Map<String, Any?> {
        val selected = locale(localeTag)
        if (Build.VERSION.SDK_INT < 31) return capability(localeTag, "unavailable", "Basic ASR requires Android API 31")
        val recognizer = open(selected)
        return try { status(localeTag, recognizer.checkStatus()) }
        finally { release(recognizer) }
    }

    suspend fun prepare(localeTag: String): Map<String, Any?> {
        val selected = locale(localeTag)
        if (Build.VERSION.SDK_INT < 31) return capability(localeTag, "unavailable", "Basic ASR requires Android API 31")
        val recognizer = open(selected)
        return try {
            when (recognizer.checkStatus()) {
                FeatureStatus.DOWNLOADABLE -> recognizer.download().collect { download ->
                    when (download) {
                        is DownloadStatus.DownloadFailed -> throw AudioFailure("downloadFailed", download.e.message)
                        is DownloadStatus.DownloadStarted -> Unit
                        is DownloadStatus.DownloadProgress -> Unit
                        is DownloadStatus.DownloadCompleted -> Unit
                    }
                }
                FeatureStatus.AVAILABLE, FeatureStatus.DOWNLOADING, FeatureStatus.UNAVAILABLE -> Unit
                else -> throw AudioFailure("featureStatus", "Unknown Basic recognition feature status")
            }
            status(localeTag, recognizer.checkStatus())
        } finally { release(recognizer) }
    }

    suspend fun transcribe(wave: ByteArray, localeTag: String): Map<String, Any?> {
        val audio = PcmWaveAudio.parse(wave)
        val selected = locale(localeTag)
        if (Build.VERSION.SDK_INT < 31) throw AudioFailure("unavailable", "Basic ASR requires Android API 31")
        val recognizer = open(selected)
        try {
            if (recognizer.checkStatus() != FeatureStatus.AVAILABLE) {
                throw AudioFailure("unavailable", "Basic model is not available for $localeTag")
            }
            return withTimeout(audio.durationMilliseconds + 30000) {
                coroutineScope {
                    val descriptors = ParcelFileDescriptor.createPipe()
                    pipe = descriptors
                    val feeder = async(Dispatchers.IO) {
                        ParcelFileDescriptor.AutoCloseOutputStream(descriptors[1]).use { stream ->
                            val start = System.nanoTime()
                            var offset = 0
                            while (offset < audio.pcm.size) {
                                val count = minOf(640, audio.pcm.size - offset)
                                stream.write(audio.pcm, offset, count)
                                offset += count
                                // 32000 bytes/second: pace each cumulative sample
                                // boundary, retaining EOF until the last sample time.
                                val target = start + offset.toLong() * 1000000000 / 32000
                                val remaining = target - System.nanoTime()
                                if (remaining > 0) delay((remaining + 999999) / 1000000)
                            }
                        }
                    }
                    val text = StringBuilder()
                    var completed = false
                    try {
                        recognizer.startRecognition(speechRecognizerRequest {
                            audioSource = AudioSource.fromPfd(descriptors[0])
                        }).collect { response ->
                            when (response) {
                                is SpeechRecognizerResponse.FinalTextResponse -> text.append(response.text)
                                is SpeechRecognizerResponse.PartialTextResponse -> Unit
                                is SpeechRecognizerResponse.CompletedResponse -> completed = true
                                is SpeechRecognizerResponse.ErrorResponse ->
                                    throw AudioFailure(response.e.errorCode.toString(), response.e.message)
                            }
                        }
                        feeder.await()
                        if (!completed) throw AudioFailure("incompleteRecognition", "No CompletedResponse")
                        if (text.toString().trim().isEmpty()) throw AudioFailure("noSpeech", "No final speech text")
                        mapOf("text" to text.toString(), "extensions" to emptyMap<String, Any?>())
                    } finally {
                        withContext(NonCancellable) {
                            closePipe()
                            feeder.cancelAndJoin()
                        }
                    }
                }
            }
        } finally { release(recognizer, stop = true) }
    }

    suspend fun cancel() {
        closePipe()
        val recognizer = client ?: return
        release(recognizer, stop = true)
    }

    private fun open(selected: Locale): SpeechRecognizer {
        check(client == null) { "An audio model is already open" }
        return SpeechRecognition.getClient(speechRecognizerOptions {
            locale = selected
            preferredMode = SpeechRecognizerOptions.Mode.MODE_BASIC
        }).also { client = it }
    }

    private suspend fun release(recognizer: SpeechRecognizer, stop: Boolean = false) {
        if (client !== recognizer) return
        client = null
        withContext(NonCancellable) {
            try {
                closePipe()
                if (stop) withTimeout(5000) { recognizer.stopRecognition() }
            } finally { recognizer.close() }
        }
    }

    private fun closePipe() {
        val descriptors = pipe
        pipe = null
        descriptors?.forEach { descriptor ->
            try { descriptor.close() } catch (_: java.io.IOException) { /* Already closed. */ }
        }
    }

    private fun locale(tag: String): Locale {
        if (!Regex("^[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$").matches(tag)) {
            throw AudioFailure("invalidLocale", "Invalid recognition locale")
        }
        return Locale.Builder().setLanguageTag(tag).build()
    }

    private fun status(tag: String, state: Int): Map<String, Any?> = when (state) {
        FeatureStatus.AVAILABLE -> capability(tag, "available", null)
        FeatureStatus.DOWNLOADABLE -> capability(tag, "downloadable", null)
        FeatureStatus.DOWNLOADING -> capability(tag, "downloading", null)
        FeatureStatus.UNAVAILABLE -> capability(tag, "unavailable", "Basic model unavailable on this device/locale")
        else -> throw AudioFailure("featureStatus", "Unknown Basic recognition feature status: $state")
    }

    private fun capability(tag: String, state: String, reason: String?) =
        mapOf("providerId" to "android-basic-speech", "locale" to tag,
            "state" to state, "reason" to reason)
}
