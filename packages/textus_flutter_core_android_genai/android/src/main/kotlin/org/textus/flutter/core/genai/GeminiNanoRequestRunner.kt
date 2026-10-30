package org.textus.flutter.core.genai

import kotlinx.coroutines.flow.collect

/** Validated immutable request; parsing cannot initialize a native model. */
internal sealed class GeminiNanoRequest(val deadlineMillis: Long) {
    object Probe : GeminiNanoRequest(20_000)
    object Prepare : GeminiNanoRequest(600_000)
    class Recognize(val bytes: ByteArray, val prompt: String, val expectedModelName: String?) :
        GeminiNanoRequest(90_000)
    class Draft(
        val requestId: String,
        val operation: String,
        val language: String,
        bytes: ByteArray?,
        val prompt: String,
        val expectedModelName: String?,
    ) : GeminiNanoRequest(90_000) {
        private val originalBytes = bytes?.copyOf()
        val bytes: ByteArray? get() = originalBytes?.copyOf()
    }

    companion object {
        fun parse(method: String, arguments: Any?): GeminiNanoRequest {
            if (method == "probe" || method == "prepare") {
                if (arguments != null && (arguments !is Map<*, *> || arguments.isNotEmpty())) {
                    throw GeminiNanoFailure("invalidArguments", "$method requires null or an empty map")
                }
                return if (method == "probe") Probe else Prepare
            }
            if (method == "generateDraft") return parseDraft(arguments)
            if (method != "recognize" || arguments !is Map<*, *> ||
                arguments.keys != setOf("bytes", "prompt", "expectedModelName")) {
                throw GeminiNanoFailure("invalidArguments", "Expected recognize with exactly bytes, prompt and expectedModelName")
            }
            val bytes = arguments["bytes"]
            val prompt = arguments["prompt"]
            val modelName = arguments["expectedModelName"]
            if (bytes !is ByteArray || bytes.isEmpty() || prompt !is String || prompt.isBlank() ||
                (modelName != null && (modelName !is String || modelName.isBlank()))) {
                throw GeminiNanoFailure("invalidArguments", "Invalid original bytes, prompt or expectedModelName")
            }
            return Recognize(bytes.copyOf(), prompt, modelName as String?)
        }

        fun parseDraftCancellation(arguments: Any?): String {
            if (arguments !is Map<*, *> || arguments.keys != setOf("requestId")) {
                throw GeminiNanoFailure("invalidArguments", "cancelDraft requires exactly requestId")
            }
            return draftIdentity(arguments["requestId"])
        }

        private fun parseDraft(arguments: Any?): Draft {
            if (arguments !is Map<*, *> || arguments.keys != setOf(
                    "requestId", "operation", "language", "bytes", "prompt", "expectedModelName",
                )) {
                throw GeminiNanoFailure("invalidArguments", "generateDraft requires exactly requestId, operation, language, bytes, prompt and expectedModelName")
            }
            val requestId = draftIdentity(arguments["requestId"])
            val operation = arguments["operation"]
            val language = arguments["language"]
            val bytes = arguments["bytes"]
            val prompt = arguments["prompt"]
            val modelName = arguments["expectedModelName"]
            val textOperation = operation == "textSummary" || operation == "textProofreading" || operation == "textReadability"
            if ((operation != "imageDescription" && !textOperation) || language != "ja" ||
                (operation == "imageDescription" && (bytes !is ByteArray || bytes.isEmpty())) ||
                (textOperation && bytes != null) ||
                prompt !is String || prompt.isBlank() ||
                (modelName != null && (modelName !is String || modelName.isBlank()))) {
                throw GeminiNanoFailure("invalidArguments", "Invalid generated draft operation, language, original bytes, prompt or expectedModelName")
            }
            return Draft(requestId, operation as String, language as String, bytes as ByteArray?, prompt, modelName as String?)
        }

        private fun draftIdentity(value: Any?): String {
            if (value !is String || value.isBlank() || value != value.trim() || value.contains('\u0000')) {
                throw GeminiNanoFailure("invalidArguments", "Draft requestId must be exact, nonblank and without NUL")
            }
            return value
        }
    }
}

/** Exactly one model per request; native cleanup finishes before returning. */
internal class GeminiNanoRequestRunner(private val factory: GeminiNanoModelFactory) {
    suspend fun execute(method: String, arguments: Any?, cleanupFailures: MutableList<String> = mutableListOf()): Any? =
        execute(GeminiNanoRequest.parse(method, arguments), cleanupFailures)

    suspend fun execute(request: GeminiNanoRequest, cleanupFailures: MutableList<String>): Any? {
        val model = factory.create()
        var primary: Throwable? = null
        val response: Map<String, Any?>?
        try {
            val status = model.status()
            response = when (request) {
                GeminiNanoRequest.Probe -> mapOf(
                    "state" to status.wireState,
                    "modelName" to if (status == GeminiNanoReadiness.AVAILABLE) actualModelName(model) else null,
                    "reason" to status.reason,
                )
                GeminiNanoRequest.Prepare -> {
                    when (status) {
                        GeminiNanoReadiness.AVAILABLE -> Unit
                        GeminiNanoReadiness.DOWNLOADABLE -> {
                            var completed = false
                            model.download().collect { event ->
                                when (event) {
                                    GeminiNanoDownload.Completed -> completed = true
                                    is GeminiNanoDownload.Failed -> throw event.error
                                    GeminiNanoDownload.Progress -> Unit
                                }
                            }
                            if (!completed) {
                                throw GeminiNanoFailure("downloadIncomplete", "AICore download ended without DownloadCompleted")
                            }
                        }
                        else -> throw GeminiNanoFailure("providerUnavailable", status.reason!!)
                    }
                    null
                }
                is GeminiNanoRequest.Recognize -> {
                    if (status != GeminiNanoReadiness.AVAILABLE) {
                        throw GeminiNanoFailure("providerUnavailable", status.reason!!)
                    }
                    val modelName = actualModelName(model)
                    if (request.expectedModelName != null && request.expectedModelName != modelName) {
                        throw GeminiNanoFailure("modelChanged", "AICore model changed from ${request.expectedModelName} to $modelName")
                    }
                    val text = model.generate(request.bytes, request.prompt, cleanupFailures)
                    if (text.isBlank()) throw GeminiNanoFailure("emptyResponse", "AICore returned blank generated text")
                    mapOf("text" to text, "modelName" to modelName)
                }
                is GeminiNanoRequest.Draft -> {
                    if (status != GeminiNanoReadiness.AVAILABLE) {
                        throw GeminiNanoFailure("providerUnavailable", status.reason!!)
                    }
                    val modelName = actualModelName(model)
                    if (request.expectedModelName != null && request.expectedModelName != modelName) {
                        throw GeminiNanoFailure("modelChanged", "AICore model changed from ${request.expectedModelName} to $modelName")
                    }
                    val text = model.generateDraft(request.bytes, request.prompt, cleanupFailures)
                    mapOf("requestId" to request.requestId, "text" to text, "modelName" to modelName)
                }
            }
        } catch (error: Throwable) {
            primary = error
            throw error
        } finally {
            try {
                model.close()
            } catch (error: Throwable) {
                cleanupFailures.add(nativeDescription(error))
                if (primary == null && request !is GeminiNanoRequest.Recognize && request !is GeminiNanoRequest.Draft) {
                    throw GeminiNanoFailure("cleanupFailed", nativeDescription(error), error)
                }
            }
        }
        return if (request is GeminiNanoRequest.Recognize || request is GeminiNanoRequest.Draft) {
            response!! + ("cleanupFailures" to cleanupFailures.toList())
        } else response
    }

    private suspend fun actualModelName(model: GeminiNanoModel): String = model.modelName().also {
        if (it.isBlank()) throw GeminiNanoFailure("nativeFailure", "Available AICore model has no actual base model name")
    }
}
