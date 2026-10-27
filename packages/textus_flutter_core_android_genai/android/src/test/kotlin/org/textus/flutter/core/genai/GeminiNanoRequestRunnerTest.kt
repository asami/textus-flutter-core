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
    ) : GeminiNanoModel {
        var names = 0
        var downloads = 0
        var generations = 0
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
            return " raw generated text "
        }
        override fun close() { closes++; closeFailure?.let { throw it } }
    }
}
