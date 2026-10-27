package org.textus.flutter.core.genai

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

/** Pure injectable model boundary; each factory result has one request owner. */
internal interface GeminiNanoModel {
    suspend fun status(): GeminiNanoReadiness
    suspend fun modelName(): String
    fun download(): Flow<GeminiNanoDownload>
    suspend fun generate(bytes: ByteArray, prompt: String, cleanupFailures: MutableList<String>): String
    fun close()
}

internal fun interface GeminiNanoModelFactory {
    fun create(): GeminiNanoModel
}

internal sealed class GeminiNanoDownload {
    object Progress : GeminiNanoDownload()
    object Completed : GeminiNanoDownload()
    class Failed(val error: Throwable) : GeminiNanoDownload()
}

internal enum class GeminiNanoReadiness(val wireState: String, val reason: String?) {
    UNAVAILABLE("unavailable", "AICore reports the feature unavailable"),
    DOWNLOADABLE("downloadable", "AICore model download is required"),
    DOWNLOADING("preparing", "AICore model download is in progress"),
    AVAILABLE("available", null),
}

internal class GeminiNanoFailure(
    val code: String,
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

internal fun nativeDescription(error: Throwable): String = error.toString().ifBlank {
    error.javaClass.name
}

/** Official beta4 default stable client, with no implicit model preparation. */
internal class AicoreGeminiNanoModel(
    private val model: GenerativeModel = Generation.getClient(),
) : GeminiNanoModel {
    override suspend fun status(): GeminiNanoReadiness = when (val status = model.checkStatus()) {
        FeatureStatus.UNAVAILABLE -> GeminiNanoReadiness.UNAVAILABLE
        FeatureStatus.DOWNLOADABLE -> GeminiNanoReadiness.DOWNLOADABLE
        FeatureStatus.DOWNLOADING -> GeminiNanoReadiness.DOWNLOADING
        FeatureStatus.AVAILABLE -> GeminiNanoReadiness.AVAILABLE
        else -> throw GeminiNanoFailure("nativeFailure", "Unknown AICore FeatureStatus: $status")
    }

    override suspend fun modelName(): String = model.getBaseModelName()

    override fun download(): Flow<GeminiNanoDownload> = model.download().map { status ->
        when (status) {
            is DownloadStatus.DownloadCompleted -> GeminiNanoDownload.Completed
            is DownloadStatus.DownloadFailed -> GeminiNanoDownload.Failed(status.e)
            else -> GeminiNanoDownload.Progress
        }
    }

    override suspend fun generate(
        bytes: ByteArray,
        prompt: String,
        cleanupFailures: MutableList<String>,
    ): String = withContext(Dispatchers.Default) {
        // Allocation and its finally stay in the same owner even on cancellation.
        var bitmap: Bitmap? = null
        try {
            val image = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                ?: throw GeminiNanoFailure("invalidArguments", "Original image bytes could not be decoded")
            bitmap = image
            val request = GenerateContentRequest.Builder(ImagePart(image), TextPart(prompt)).apply {
                temperature = 0.0f
                candidateCount = 1
                maxOutputTokens = 512
            }.build()
            val tokens = model.countTokens(request).totalTokens
            val limit = model.getTokenLimit()
            if (tokens < 0 || limit <= 0) {
                throw GeminiNanoFailure("nativeFailure", "Invalid AICore token count $tokens or limit $limit")
            }
            if (tokens.toLong() + 512L > limit.toLong()) {
                throw GeminiNanoFailure("inputTooLarge", "Request tokens $tokens plus 512 output tokens exceed model limit $limit")
            }
            val candidates = model.generateContent(request).candidates
            if (candidates.size != 1 || candidates.single().text.isBlank()) {
                throw GeminiNanoFailure("emptyResponse", "AICore returned ${candidates.size} candidates; exactly one nonblank text is required")
            }
            candidates.single().text
        } finally {
            try {
                bitmap?.recycle()
            } catch (error: Throwable) {
                cleanupFailures.add(nativeDescription(error))
            }
        }
    }

    override fun close() = model.close()
}
