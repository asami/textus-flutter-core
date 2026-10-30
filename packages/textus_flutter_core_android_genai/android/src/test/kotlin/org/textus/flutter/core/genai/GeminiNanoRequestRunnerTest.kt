package org.textus.flutter.core.genai

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/** Readiness and preparation: pure model boundary, no Android runtime mocks. */
@OptIn(ExperimentalCoroutinesApi::class)
class GeminiNanoRequestRunnerTest {
    @Test
    fun shouldProbeEachReadinessWithoutDownloadingOrGenerating() = runTest {
        for (state in GeminiNanoReadiness.values()) {
            // Given one fresh model in this real readiness category.
            val model = Model(state = state)
            val factory = Factory(model)
            // When its runner performs only a probe.
            val result = GeminiNanoRequestRunner(factory).execute("probe", null) as Map<*, *>
            // Then the wire snapshot is exact, unknown models remain null and resources close.
            assertEquals(setOf("state", "modelName", "reason"), result.keys)
            assertEquals(state.wireState, result["state"])
            assertEquals(if (state == GeminiNanoReadiness.AVAILABLE) "actual-base-model" else null, result["modelName"])
            assertEquals(state.reason, result["reason"])
            assertEquals(if (state == GeminiNanoReadiness.AVAILABLE) 1 else 0, model.names)
            assertEquals(0, model.downloads)
            assertEquals(0, model.generations)
            assertEquals(1, model.closes)
            assertEquals(1, factory.creates)
        }
    }

    @Test
    fun shouldExposeUnknownStatusAndUnknownAvailableModel() = runTest {
        for (unknownStatus in listOf(true, false)) {
            // Given either an unknown status failure or an available model with a blank name.
            val actual = GeminiNanoFailure("nativeFailure", "Unknown AICore FeatureStatus: 999")
            val model = if (unknownStatus) Model(statusFailure = actual) else Model(name = " ")
            // When a probe cannot produce an honest available model snapshot.
            val failure = caught { GeminiNanoRequestRunner(Factory(model)).execute("probe", emptyMap<String, Any?>()) }
            // Then the exact failure remains observable with no inference or download.
            assertEquals("nativeFailure", (failure as GeminiNanoFailure).code)
            if (unknownStatus) assertSame(actual, failure) else assertTrue(failure.message!!.contains("actual base model"))
            assertEquals(0, model.downloads)
            assertEquals(0, model.generations)
            assertEquals(1, model.closes)
        }
    }

    @Test
    fun shouldPrepareOnlyReadyOrDownloadableModels() = runTest {
        for (state in GeminiNanoReadiness.values()) {
            // Given a fresh readiness snapshot and a download with a real completion event.
            val model = Model(state = state)
            val runner = GeminiNanoRequestRunner(Factory(model))
            // When explicit preparation is requested for this state.
            if (state == GeminiNanoReadiness.AVAILABLE || state == GeminiNanoReadiness.DOWNLOADABLE) {
                val result = runner.execute("prepare", null)
                // Then readiness/completion alone succeeds; metadata and generation are unnecessary.
                assertNull(result)
                assertEquals(if (state == GeminiNanoReadiness.DOWNLOADABLE) 1 else 0, model.downloads)
            } else {
                val failure = caught { runner.execute("prepare", null) } as GeminiNanoFailure
                // Then preparing/unavailable truth rejects without another download.
                assertEquals("providerUnavailable", failure.code)
                assertEquals(state.reason, failure.message)
                assertEquals(0, model.downloads)
            }
            assertEquals(0, model.names)
            assertEquals(0, model.generations)
            assertEquals(1, model.closes)
        }
    }

    @Test
    fun shouldRequireDownloadCompletedAndRetainTheActualDownloadError() = runTest {
        for (failedDownload in listOf(false, true)) {
            // Given progress-only completion or the actual native download exception.
            val actual = IllegalStateException("download quota exhausted")
            val model = Model(state = GeminiNanoReadiness.DOWNLOADABLE, events = if (failedDownload)
                listOf(GeminiNanoDownload.Progress, GeminiNanoDownload.Failed(actual))
                else listOf(GeminiNanoDownload.Progress))
            // When explicit preparation consumes the download stream.
            val failure = caught { GeminiNanoRequestRunner(Factory(model)).execute("prepare", null) }
            // Then no stream without completion can report readiness and actual errors retain identity.
            if (failedDownload) assertSame(actual, failure)
            else assertEquals("downloadIncomplete", (failure as GeminiNanoFailure).code)
            assertEquals(1, model.downloads)
            assertEquals(0, model.generations)
            assertEquals(1, model.closes)
        }
    }

    @Test
    fun shouldRejectUnavailableInferenceWithoutPreparing() = runTest {
        for (state in GeminiNanoReadiness.values().filter { it != GeminiNanoReadiness.AVAILABLE }) {
            // Given a nonavailable model and valid original image arguments.
            val model = Model(state = state)
            // When inference rechecks readiness.
            val failure = caught { GeminiNanoRequestRunner(Factory(model)).execute("recognize", arguments()) } as GeminiNanoFailure
            // Then readiness prevents all generation and implicit preparation.
            assertEquals("providerUnavailable", failure.code)
            assertEquals(state.reason, failure.message)
            assertEquals(0, model.names)
            assertEquals(0, model.downloads)
            assertEquals(0, model.generations)
            assertEquals(1, model.closes)
        }
    }

    @Test
    fun shouldCheckExpectedModelBeforeInferenceAndReturnActualModelForUnprobedCalls() = runTest {
        for (expected in listOf<String?>(null, "actual-base-model", "previous-model")) {
            // Given an actual model and either no prior probe, matching or changed historical identity.
            val model = Model()
            val runner = GeminiNanoRequestRunner(Factory(model))
            // When recognition obtains the actual base model name.
            if (expected == "previous-model") {
                val failure = caught { runner.execute("recognize", arguments(expected = expected)) } as GeminiNanoFailure
                // Then a changed model is rejected before generation and retains both names.
                assertEquals("modelChanged", failure.code)
                assertTrue(failure.message!!.contains("previous-model"))
                assertTrue(failure.message!!.contains("actual-base-model"))
                assertEquals(0, model.generations)
            } else {
                val result = runner.execute("recognize", arguments(expected = expected)) as Map<*, *>
                // Then successful raw text and actual identity are verbatim, with the exact envelope.
                assertEquals(setOf("text", "modelName", "cleanupFailures"), result.keys)
                assertEquals(" raw generated text ", result["text"])
                assertEquals("actual-base-model", result["modelName"])
                assertEquals(emptyList<String>(), result["cleanupFailures"])
                assertEquals(1, model.generations)
            }
            assertEquals(0, model.downloads)
            assertEquals(1, model.closes)
        }
    }

    @Test
    fun shouldSnapshotOriginalBytesBeforeAnySuspension() = runTest {
        // Given original bytes and a held readiness query after argument parsing.
        val gate = CompletableDeferred<Unit>()
        val model = Model(statusGate = gate)
        val bytes = byteArrayOf(1, 2, 3)
        val runner = GeminiNanoRequestRunner(Factory(model))
        // When the caller mutates its bytes while the native operation is suspended.
        val request = async(start = CoroutineStart.UNDISPATCHED) { runner.execute("recognize", arguments(bytes = bytes)) }
        bytes[0] = 99
        gate.complete(Unit)
        request.await()
        // Then the model receives its owned original copy and exact prompt.
        assertArrayEquals(byteArrayOf(1, 2, 3), model.receivedBytes)
        assertEquals(" exact prompt ", model.receivedPrompt)
        assertArrayEquals(byteArrayOf(99, 2, 3), bytes)
        assertEquals(1, model.closes)
    }

    @Test
    fun shouldKeepSuccessfulRawDataAlongsideEveryCleanupFailure() = runTest {
        // Given a successful generation with separate image and model cleanup failures.
        val model = Model(generationCleanup = "bitmap cleanup failed", closeFailure = IllegalStateException("model close failed"))
        // When recognition and all cleanup complete.
        val result = GeminiNanoRequestRunner(Factory(model)).execute("recognize", arguments()) as Map<*, *>
        // Then raw success survives and every cleanup description remains ordered in the envelope.
        assertEquals(" raw generated text ", result["text"])
        assertEquals(listOf("bitmap cleanup failed", "java.lang.IllegalStateException: model close failed"), result["cleanupFailures"])
        assertEquals(1, model.closes)
    }

    @Test
    fun shouldKeepPrimaryNativeFailureWithCloseFailure() = runTest {
        // Given an actual quota-like exception and a separately failing close.
        val actual = IllegalStateException("native quota rejected generation")
        val model = Model(generationFailure = actual, closeFailure = IllegalStateException("close failed"))
        val cleanup = mutableListOf<String>()
        // When generation fails and the runner still closes its model.
        val failure = caught { GeminiNanoRequestRunner(Factory(model)).execute("recognize", arguments(), cleanup) }
        // Then the primary error is identical and cleanup is additional descriptive evidence.
        assertSame(actual, failure)
        assertEquals(listOf("java.lang.IllegalStateException: close failed"), cleanup)
        assertEquals(1, model.closes)
    }

    @Test
    fun shouldFailProbeAndPreparationWhenTheirCloseFails() = runTest {
        for (method in listOf("probe", "prepare")) {
            // Given a ready model whose final close fails after this metadata/preparation operation.
            val model = Model(closeFailure = IllegalStateException("close after $method failed"))
            val cleanup = mutableListOf<String>()
            // When the runner finishes this operation.
            val failure = caught { GeminiNanoRequestRunner(Factory(model)).execute(method, null, cleanup) } as GeminiNanoFailure
            // Then close failure is an error, never a successful readiness/preparation claim.
            assertEquals("cleanupFailed", failure.code)
            assertTrue(failure.message!!.contains("close after $method failed"))
            assertEquals(1, cleanup.size)
            assertEquals(1, model.closes)
            assertEquals(0, model.generations)
        }
    }

    @Test
    fun shouldPropagateCancellationAndCloseExactlyOnceWithCleanupEvidence() = runTest {
        // Given an inference suspended after its model has been created.
        val gate = CompletableDeferred<Unit>()
        val model = Model(generationGate = gate, closeFailure = IllegalStateException("canceled close failed"))
        val cleanup = mutableListOf<String>()
        // When the request owner cancels native inference.
        val request = async { GeminiNanoRequestRunner(Factory(model)).execute("recognize", arguments(), cleanup) }
        runCurrent()
        request.cancel(CancellationException("foregroundRequired"))
        val failure = caught { request.await() }
        // Then cancellation propagates after exactly one close and includes its cleanup failure.
        assertTrue(failure is CancellationException)
        assertEquals(1, model.generations)
        assertEquals(1, model.closes)
        assertEquals(listOf("java.lang.IllegalStateException: canceled close failed"), cleanup)
        assertFalse(gate.isCompleted)
    }

    @Test
    fun shouldRejectMalformedArgumentsBeforeCreatingAnyModel() = runTest {
        val cases = listOf(
            "probe" to listOf(1), "probe" to mapOf("extra" to 1),
            "prepare" to "not a map", "prepare" to mapOf("extra" to 1),
            "unknown" to null, "recognize" to null,
            "recognize" to mapOf("bytes" to byteArrayOf(1), "prompt" to "x"),
            "recognize" to arguments() + ("extra" to 1),
            "recognize" to arguments(bytes = byteArrayOf()),
            "recognize" to arguments() + ("bytes" to listOf(1)),
            "recognize" to arguments() + ("prompt" to " "),
            "recognize" to arguments() + ("prompt" to 4),
            "recognize" to arguments() + ("expectedModelName" to " "),
            "recognize" to arguments() + ("expectedModelName" to 4),
        )
        for ((method, arguments) in cases) {
            // Given this malformed method envelope and a fresh observable factory.
            val model = Model()
            val factory = Factory(model)
            // When the request is submitted directly to the runner.
            val failure = caught { GeminiNanoRequestRunner(factory).execute(method, arguments) } as GeminiNanoFailure
            // Then admission fails with no native model creation or cleanup.
            assertEquals("invalidArguments", failure.code)
            assertEquals(0, factory.creates)
            assertEquals(0, model.closes)
        }
    }

    @Test
    fun shouldPreserveTokenAndEmptyResponseFailures() = runTest {
        for (code in listOf("inputTooLarge", "emptyResponse")) {
            // Given the production adapter's explicit failed generation boundary.
            val actual = GeminiNanoFailure(code, "actual $code description")
            val model = Model(generationFailure = actual)
            // When a validated runner delegates inference.
            val failure = caught { GeminiNanoRequestRunner(Factory(model)).execute("recognize", arguments()) }
            // Then the original code/description survive without retry, truncation or preparation.
            assertSame(actual, failure)
            assertEquals(1, model.generations)
            assertEquals(0, model.downloads)
            assertEquals(1, model.closes)
        }
    }

    @Test
    fun shouldGeneratePlainImageAndTextDraftsWithExactIdentityAndNullableImageInput() = runTest {
        for (operation in listOf("imageDescription", "textSummary", "textProofreading", "textReadability")) {
            for (expected in listOf<String?>(null, "actual-base-model")) {
                // Given this operation's exact prompt, original image or true text-only input, and expected model.
                val model = Model(draftText = " \n日本語の編集可能な下書き\n ")
                val factory = Factory(model)
                val bytes = if (operation == "imageDescription") byteArrayOf(1, 2, 3) else null
                // When one native draft request rechecks actual readiness and performs inference.
                val result = GeminiNanoRequestRunner(factory).execute("generateDraft", draftArguments(
                    operation = operation, bytes = bytes, expected = expected,
                )) as Map<*, *>
                // Then plain raw text, actual model and exact request identity survive after the one close.
                assertEquals(setOf("requestId", "text", "modelName", "cleanupFailures"), result.keys)
                assertEquals("draft-1", result["requestId"])
                assertEquals(" \n日本語の編集可能な下書き\n ", result["text"])
                assertEquals("actual-base-model", result["modelName"])
                assertEquals(emptyList<String>(), result["cleanupFailures"])
                if (bytes == null) assertNull(model.receivedBytes) else assertArrayEquals(bytes, model.receivedBytes)
                assertEquals(" exact Japanese draft prompt ", model.receivedPrompt)
                assertEquals(1, model.drafts)
                assertEquals(0, model.generations)
                assertEquals(0, model.downloads)
                assertEquals(1, model.names)
                assertEquals(1, model.closes)
                assertEquals(1, factory.creates)
            }
        }
    }

    @Test
    fun shouldSnapshotDraftImageBeforeSuspensionAndProtectItsParsedValue() = runTest {
        // Given original bytes and a draft parsed before any native model can suspend.
        val original = byteArrayOf(1, 2, 3)
        val parsed = GeminiNanoRequest.parse("generateDraft", draftArguments(bytes = original)) as GeminiNanoRequest.Draft
        val copy = parsed.bytes!!
        val gate = CompletableDeferred<Unit>()
        val model = Model(statusGate = gate)
        // When caller and accessor buffers are mutated while native readiness is pending.
        val pending = async(start = CoroutineStart.UNDISPATCHED) {
            GeminiNanoRequestRunner(Factory(model)).execute(parsed, mutableListOf())
        }
        original[0] = 99
        copy[1] = 99
        gate.complete(Unit)
        pending.await()
        // Then inference and future reads still receive the original owned image and exact prompt.
        assertArrayEquals(byteArrayOf(1, 2, 3), model.receivedBytes)
        assertArrayEquals(byteArrayOf(1, 2, 3), parsed.bytes)
        assertEquals(" exact Japanese draft prompt ", model.receivedPrompt)
        assertEquals(90_000L, parsed.deadlineMillis)
        assertEquals("imageDescription", parsed.operation)
        assertEquals("ja", parsed.language)
        assertEquals(1, model.closes)
    }

    @Test
    fun shouldRejectEveryMalformedDraftEnvelopeBeforeCreatingAModel() = runTest {
        val valid = draftArguments()
        val invalid = mutableListOf<Any?>(null, "not a map", valid + ("extra" to true))
        invalid.addAll(valid.keys.map { missing -> valid.filterKeys { it != missing } })
        for ((key, value) in listOf(
            "requestId" to null, "requestId" to 7, "requestId" to "", "requestId" to " ",
            "requestId" to " draft-1", "requestId" to "draft-1 ", "requestId" to "draft\u0000id",
            "operation" to null, "operation" to 4, "operation" to "recognize", "operation" to "futureOperation",
            "language" to null, "language" to 4, "language" to "en", "language" to " ja",
            "bytes" to null, "bytes" to byteArrayOf(), "bytes" to listOf(1),
            "prompt" to null, "prompt" to 4, "prompt" to " ",
            "expectedModelName" to 4, "expectedModelName" to " ",
        )) invalid.add(valid + (key to value))
        for (operation in listOf("textSummary", "textProofreading", "textReadability")) {
            for (bytes in listOf<Any?>(byteArrayOf(1), byteArrayOf(), "pseudoimage", listOf(1), 1)) {
                invalid.add(draftArguments(operation = operation, bytes = null) + ("bytes" to bytes))
            }
            for ((key, value) in listOf(
                "operation" to " $operation", "operation" to "${operation}Future",
                "language" to "en", "language" to " ja", "extra" to true,
            )) invalid.add(draftArguments(operation = operation, bytes = null) + (key to value))
        }
        for (arguments in invalid) {
            // Given this missing, extra, wrong-type, unsupported or source-inconsistent draft envelope.
            val factory = Factory(Model())
            // When native request parsing is attempted before any model allocation.
            val failure = caught { GeminiNanoRequestRunner(factory).execute("generateDraft", arguments) } as GeminiNanoFailure
            // Then argument admission fails without a factory call or inference.
            assertEquals("invalidArguments", failure.code)
            assertEquals(0, factory.creates)
        }
    }

    @Test
    fun shouldKeepOldRecognitionEnvelopeSeparateFromTheNewDraftProtocol() = runTest {
        // Given the existing three-key recognition envelope and the additive six-key draft envelope.
        val model = Model()
        val factory = Factory(model)
        // When old recognition succeeds and either method is given the other's arguments.
        val result = GeminiNanoRequestRunner(factory).execute("recognize", arguments()) as Map<*, *>
        val wrongRecognition = caught { GeminiNanoRequestRunner(factory).execute("recognize", draftArguments()) }
        val wrongDraft = caught { GeminiNanoRequestRunner(factory).execute("generateDraft", arguments()) }
        // Then old output keeps its three keys and cross-protocol arguments fail before another model.
        assertEquals(setOf("text", "modelName", "cleanupFailures"), result.keys)
        assertEquals("invalidArguments", (wrongRecognition as GeminiNanoFailure).code)
        assertEquals("invalidArguments", (wrongDraft as GeminiNanoFailure).code)
        assertEquals(1, model.generations)
        assertEquals(0, model.drafts)
        assertEquals(1, factory.creates)
    }

    @Test
    fun shouldRejectUnavailableAndChangedDraftModelsWithoutInferenceOrDownload() = runTest {
        for (state in GeminiNanoReadiness.values()) {
            // Given nonavailable readiness, or an available model different from the exact expected identity.
            val model = Model(state = state)
            val expected = if (state == GeminiNanoReadiness.AVAILABLE) "previous-model" else null
            // When draft generation independently rechecks native readiness and actual model identity.
            val failure = caught {
                GeminiNanoRequestRunner(Factory(model)).execute("generateDraft", draftArguments(expected = expected))
            } as GeminiNanoFailure
            // Then the actual unavailable/model-changed cause blocks both inference paths and preparation.
            assertEquals(if (state == GeminiNanoReadiness.AVAILABLE) "modelChanged" else "providerUnavailable", failure.code)
            if (state == GeminiNanoReadiness.AVAILABLE) {
                assertTrue(failure.message!!.contains("previous-model"))
                assertTrue(failure.message!!.contains("actual-base-model"))
            } else assertEquals(state.reason, failure.message)
            assertEquals(0, model.drafts)
            assertEquals(0, model.generations)
            assertEquals(0, model.downloads)
            assertEquals(1, model.closes)
        }
        // Given available readiness whose actual model name is unknown.
        val unknown = Model(name = " ")
        // When a text-only draft checks its model before inference.
        val failure = caught {
            GeminiNanoRequestRunner(Factory(unknown)).execute("generateDraft", draftArguments(operation = "textSummary", bytes = null))
        } as GeminiNanoFailure
        // Then no guessed identity, draft inference or download can escape this failed check.
        assertEquals("nativeFailure", failure.code)
        assertEquals(0, unknown.drafts)
        assertEquals(0, unknown.downloads)
        assertEquals(1, unknown.closes)
    }

    @Test
    fun shouldRetainBlankDraftAndAllCleanupWhileKeepingOldRecognitionNonblank() = runTest {
        // Given a blank draft candidate and independent image/model cleanup failures.
        val draft = Model(draftText = " \n ", generationCleanup = "image recycle failed", closeFailure = IllegalStateException("model close failed"))
        // When a draft completes with raw whitespace and then closes its model.
        val result = GeminiNanoRequestRunner(Factory(draft)).execute("generateDraft", draftArguments()) as Map<*, *>
        // Then blank text is returned truthfully for Dart eligibility checks and cleanup never discards it.
        assertEquals(" \n ", result["text"])
        assertEquals(listOf("image recycle failed", "java.lang.IllegalStateException: model close failed"), result["cleanupFailures"])
        assertEquals(1, draft.closes)
        // Given the same blank output on the preexisting recognition path.
        val recognition = Model(recognitionText = " \n ")
        // When old recognition checks its output.
        val failure = caught { GeminiNanoRequestRunner(Factory(recognition)).execute("recognize", arguments()) } as GeminiNanoFailure
        // Then the old nonblank requirement remains unchanged.
        assertEquals("emptyResponse", failure.code)
        assertEquals(1, recognition.generations)
        assertEquals(0, recognition.drafts)
        assertEquals(1, recognition.closes)
    }

    @Test
    fun shouldPropagatePrimaryDraftFailureWithCleanupAndNoRetry() = runTest {
        for (code in listOf("inputTooLarge", "emptyResponse", "nativeFailure")) {
            // Given this actual SDK failure and two independent cleanup descriptions.
            val actual = GeminiNanoFailure(code, "actual $code from AICore")
            val model = Model(generationFailure = actual, generationCleanup = "image cleanup", closeFailure = IllegalStateException("close failed"))
            val cleanup = mutableListOf<String>()
            // When a text-only native draft fails inside its single inference.
            val failure = caught {
                GeminiNanoRequestRunner(Factory(model)).execute("generateDraft", draftArguments(operation = "textSummary", bytes = null), cleanup)
            }
            // Then primary identity and all cleanup remain while no fallback, retry or preparation occurs.
            assertSame(actual, failure)
            assertEquals(listOf("image cleanup", "java.lang.IllegalStateException: close failed"), cleanup)
            assertEquals(1, model.drafts)
            assertEquals(0, model.generations)
            assertEquals(0, model.downloads)
            assertEquals(1, model.closes)
        }
    }

    @Test
    fun shouldKeepExistingModelFakesCompatibleWithAnExplicitUnsupportedDraftDefault() = runTest {
        // Given an existing model implementation that only supplies old recognition behavior.
        var closes = 0
        val legacy = object : GeminiNanoModel {
            override suspend fun status() = GeminiNanoReadiness.AVAILABLE
            override suspend fun modelName() = "legacy-model"
            override fun download(): Flow<GeminiNanoDownload> = flow { throw AssertionError("No download") }
            override suspend fun generate(bytes: ByteArray, prompt: String, cleanupFailures: MutableList<String>) = "legacy"
            override fun close() { closes++ }
        }
        // When the new draft operation reaches the interface's safe default.
        val failure = caught {
            GeminiNanoRequestRunner(GeminiNanoModelFactory { legacy }).execute("generateDraft", draftArguments())
        } as GeminiNanoFailure
        // Then compatibility is source-safe and unsupported behavior is an explicit failure after cleanup.
        assertEquals("unsupportedOperation", failure.code)
        assertTrue(failure.message!!.contains("does not support generated drafts"))
        assertEquals(1, closes)
    }

    private fun draftArguments(
        operation: String = "imageDescription",
        bytes: ByteArray? = byteArrayOf(1, 2, 3),
        expected: String? = null,
    ): Map<String, Any?> = mapOf(
        "requestId" to "draft-1", "operation" to operation, "language" to "ja", "bytes" to bytes,
        "prompt" to " exact Japanese draft prompt ", "expectedModelName" to expected,
    )

    private fun arguments(bytes: ByteArray = byteArrayOf(1, 2, 3), expected: String? = null) = mapOf(
        "bytes" to bytes, "prompt" to " exact prompt ", "expectedModelName" to expected,
    )

    private suspend fun caught(action: suspend () -> Any?): Throwable {
        try { action() } catch (error: Throwable) { return error }
        throw AssertionError("Expected observable failure")
    }

    private class Factory(private val model: Model) : GeminiNanoModelFactory {
        var creates = 0
        override fun create(): GeminiNanoModel { creates++; return model }
    }

    private class Model(
        val state: GeminiNanoReadiness = GeminiNanoReadiness.AVAILABLE,
        val name: String = "actual-base-model",
        val events: List<GeminiNanoDownload> = listOf(GeminiNanoDownload.Progress, GeminiNanoDownload.Completed),
        val statusFailure: Throwable? = null,
        val generationFailure: Throwable? = null,
        val closeFailure: Throwable? = null,
        val generationCleanup: String? = null,
        val statusGate: CompletableDeferred<Unit>? = null,
        val generationGate: CompletableDeferred<Unit>? = null,
        val draftText: String = " raw Japanese draft ",
        val recognitionText: String = " raw generated text ",
    ) : GeminiNanoModel {
        var names = 0
        var downloads = 0
        var generations = 0
        var drafts = 0
        var closes = 0
        var receivedBytes: ByteArray? = null
        var receivedPrompt: String? = null
        override suspend fun status(): GeminiNanoReadiness {
            statusGate?.await()
            statusFailure?.let { throw it }
            return state
        }
        override suspend fun modelName(): String { names++; return name }
        override fun download(): Flow<GeminiNanoDownload> = flow {
            downloads++
            for (event in events) emit(event)
        }
        override suspend fun generate(bytes: ByteArray, prompt: String, cleanupFailures: MutableList<String>): String {
            generations++
            receivedBytes = bytes.copyOf()
            receivedPrompt = prompt
            generationGate?.await()
            generationCleanup?.let { cleanupFailures.add(it) }
            generationFailure?.let { throw it }
            return recognitionText
        }
        override suspend fun generateDraft(bytes: ByteArray?, prompt: String, cleanupFailures: MutableList<String>): String {
            drafts++
            receivedBytes = bytes?.copyOf()
            receivedPrompt = prompt
            generationGate?.await()
            generationCleanup?.let { cleanupFailures.add(it) }
            generationFailure?.let { throw it }
            return draftText
        }
        override fun close() { closes++; closeFailure?.let { throw it } }
    }
}
