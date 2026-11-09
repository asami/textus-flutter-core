package org.textus.flutter.core.genai

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.Candidate
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.SystemInstruction
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** Pure injectable model boundary; each factory result has one request owner. */
internal interface GeminiNanoModel {
    suspend fun status(): GeminiNanoReadiness
    suspend fun modelName(): String
    suspend fun systemPromptAvailable(): Boolean = false
    fun download(): Flow<GeminiNanoDownload>
    suspend fun generate(bytes: ByteArray, prompt: String, cleanupFailures: MutableList<String>): String
    suspend fun generateDraft(bytes: ByteArray?, prompt: String, cleanupFailures: MutableList<String>): String =
        throw GeminiNanoFailure("unsupportedOperation", "This model does not support generated drafts")
    suspend fun generateVoiceCleanup(prompt: String, cleanupFailures: MutableList<String>): String =
        throw GeminiNanoFailure("unsupportedOperation", "This model does not support complete voice cleanup")
    suspend fun generateVoiceCleanup(instructions: String, source: String, cleanupFailures: MutableList<String>): String =
        throw GeminiNanoFailure("unsupportedOperation", "This model does not support instruction-separated voice cleanup")
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
    override suspend fun systemPromptAvailable(): Boolean = model.isSystemPromptAvailable()

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
    ): String = infer(bytes, prompt, cleanupFailures, requireNonblank = true)

    override suspend fun generateDraft(
        bytes: ByteArray?,
        prompt: String,
        cleanupFailures: MutableList<String>,
    ): String = infer(bytes, prompt, cleanupFailures, requireNonblank = false)

    override suspend fun generateVoiceCleanup(prompt: String, cleanupFailures: MutableList<String>): String =
        infer(null, prompt, cleanupFailures, requireNonblank = true,
            outputTokenLimit = 2048, requireComplete = true)

    override suspend fun generateVoiceCleanup(
        instructions: String,
        source: String,
        cleanupFailures: MutableList<String>,
    ): String = infer(null, JSONObject.quote(source), cleanupFailures, requireNonblank = true,
        outputTokenLimit = 2048, requireComplete = true, instructions = instructions)

    private suspend fun infer(
        bytes: ByteArray?,
        prompt: String,
        cleanupFailures: MutableList<String>,
        requireNonblank: Boolean,
        outputTokenLimit: Int = 512,
        requireComplete: Boolean = false,
        instructions: String? = null,
    ): String = withContext(Dispatchers.Default) {
        // Allocation and its finally stay in the same owner even on cancellation.
        var bitmap: Bitmap? = null
        try {
            val builder = if (instructions != null) {
                GenerateContentRequest.Builder(SystemInstruction(instructions), TextPart(prompt))
            } else if (bytes == null) {
                GenerateContentRequest.Builder(TextPart(prompt))
            } else {
                val image = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    ?: throw GeminiNanoFailure("invalidArguments", "Original image bytes could not be decoded")
                bitmap = image
                GenerateContentRequest.Builder(ImagePart(image), TextPart(prompt))
            }
            val request = builder.apply {
                temperature = 0.0f
                candidateCount = 1
                maxOutputTokens = outputTokenLimit
            }.build()
            val tokens = model.countTokens(request).totalTokens
            val limit = model.getTokenLimit()
            if (tokens < 0 || limit <= 0) {
                throw GeminiNanoFailure("nativeFailure", "Invalid AICore token count $tokens or limit $limit")
            }
            if (tokens.toLong() + outputTokenLimit.toLong() > limit.toLong()) {
                throw GeminiNanoFailure("inputTooLarge", "Request tokens $tokens plus $outputTokenLimit output tokens exceed model limit $limit")
            }
            val candidates = model.generateContent(request).candidates
            if (candidates.size != 1 || (requireNonblank && candidates.single().text.isBlank())) {
                val requirement = if (requireNonblank) "one nonblank text" else "one text candidate"
                throw GeminiNanoFailure("emptyResponse", "AICore returned ${candidates.size} candidates; exactly $requirement is required")
            }
            if (requireComplete) requireCompleteVoiceCleanup(candidates.single().finishReason)
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

/** Truncated, unknown and nonstandard completions are not editable successes. */
internal fun requireCompleteVoiceCleanup(finishReason: Int?) {
    if (finishReason != Candidate.FinishReason.STOP) {
        throw GeminiNanoFailure("incompleteResponse", "Voice cleanup did not finish normally: $finishReason")
    }
}
