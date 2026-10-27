package org.textus.flutter.core.genai

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Foreground, cancellation and callback ownership with virtual coroutine time. */
@OptIn(ExperimentalCoroutinesApi::class)
class GeminiNanoSessionTest {
    @Test
    fun shouldRequireForegroundBeforeModelCreationAndAllowAResumedRequest() = runTest {
        // Given an attached session whose initial foreground state is false.
        val model = Model()
        val factory = Factory(model)
        val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
        val outcomes = mutableListOf<GeminiNanoOutcome>()
        // When all operations are requested before resume and then a resumed probe runs.
        for (method in listOf("probe", "prepare", "recognize")) {
            // Given this valid foreground-gated method.
            val arguments = if (method == "recognize") arguments() else null
            // When it is submitted before any resumed Activity.
            session.submit(method, arguments, outcomes::add)
            // Then no model is created and this callback has an explicit foreground error.
            assertEquals("foregroundRequired", (outcomes.last() as GeminiNanoOutcome.Error).code)
            assertEquals(0, factory.creates)
        }
        session.setForeground(true)
        session.submit("probe", null, outcomes::add)
        runCurrent()
        // Then the resumed probe succeeds after closing its one owned model.
        assertEquals(4, outcomes.size)
        assertTrue(outcomes.last() is GeminiNanoOutcome.Success)
        assertEquals(1, factory.creates)
        assertEquals(1, model.closes)
        session.detachEngine()
    }

    @Test
    fun shouldRejectOverlapsUntilCleanupAndReleaseBeforeDeliveringSuccess() = runTest {
        // Given a foreground inference held inside its first model and a second fresh model.
        val gate = CompletableDeferred<Unit>()
        val first = Model(generationGate = gate)
        val next = Model()
        val factory = Factory(first, next)
        val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
        session.setForeground(true)
        val outcomes = mutableListOf<GeminiNanoOutcome>()
        session.submit("recognize", arguments(), outcomes::add)
        runCurrent()
        for (method in listOf("probe", "prepare", "recognize")) {
            // Given the original request still owning its native model.
            val input = if (method == "recognize") arguments() else null
            // When another valid method overlaps it.
            session.submit(method, input, outcomes::add)
            // Then overlap rejects immediately without creating or closing another model.
            assertEquals("busy", (outcomes.last() as GeminiNanoOutcome.Error).code)
            assertEquals(1, factory.creates)
            assertEquals(0, first.closes)
        }
        // When the first generation is released and then a new probe is requested.
        gate.complete(Unit)
        runCurrent()
        session.submit("probe", null) {
            // Then cleanup has completed before successful callback delivery.
            assertEquals(1, next.closes)
            outcomes.add(it)
        }
        runCurrent()
        // Then both requests delivered once and the next operation acquired the guard.
        assertEquals(5, outcomes.size)
        assertEquals(2, outcomes.count { it is GeminiNanoOutcome.Success })
        assertEquals(1, first.closes)
        assertEquals(2, factory.creates)
        session.detachEngine()
    }

    @Test
    fun shouldCancelOnPauseWithPrimaryAndCleanupEvidenceThenRecover() = runTest {
        // Given a foreground inference waiting on native work and a failing close.
        val gate = CompletableDeferred<Unit>()
        val first = Model(generationGate = gate, closeFailure = IllegalStateException("close on pause failed"))
        val next = Model()
        val factory = Factory(first, next)
        val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
        val outcomes = mutableListOf<GeminiNanoOutcome>()
        session.setForeground(true)
        session.submit("recognize", arguments(), outcomes::add)
        runCurrent()
        // When the owning Activity pauses and later resumes.
        session.setForeground(false)
        runCurrent()
        session.setForeground(true)
        session.submit("probe", null, outcomes::add)
        runCurrent()
        // Then cancellation is delivered after cleanup and resumed work uses a new model.
        val canceled = outcomes.first() as GeminiNanoOutcome.Error
        assertEquals("foregroundRequired", canceled.code)
        assertTrue(canceled.message.contains("foregroundRequired"))
        assertEquals(listOf("java.lang.IllegalStateException: close on pause failed"), canceled.details["cleanupFailures"])
        assertTrue(outcomes.last() is GeminiNanoOutcome.Success)
        assertEquals(2, outcomes.size)
        assertEquals(1, first.closes)
        assertEquals(1, next.closes)
        assertFalse(gate.isCompleted)
        session.detachEngine()
    }

    @Test
    fun shouldCancelConfigurationDetachWithoutClaimingDownloadRollback() = runTest {
        // Given an explicit preparation suspended in an AICore-managed download.
        val gate = CompletableDeferred<Unit>()
        val first = Model(state = GeminiNanoReadiness.DOWNLOADABLE, downloadGate = gate)
        val current = Model(state = GeminiNanoReadiness.DOWNLOADING)
        val session = GeminiNanoSession(GeminiNanoRequestRunner(Factory(first, current)), StandardTestDispatcher(testScheduler))
        val outcomes = mutableListOf<GeminiNanoOutcome>()
        session.setForeground(true)
        session.submit("prepare", null, outcomes::add)
        runCurrent()
        // When configuration detach cancels and a reattached foreground Activity probes explicitly.
        session.detachActivity()
        runCurrent()
        session.setForeground(true)
        session.submit("probe", emptyMap<String, Any?>(), outcomes::add)
        runCurrent()
        // Then cancellation closes the old client but the new probe preserves current downloading truth.
        assertEquals("foregroundRequired", (outcomes.first() as GeminiNanoOutcome.Error).code)
        val snapshot = (outcomes.last() as GeminiNanoOutcome.Success).value as Map<*, *>
        assertEquals("preparing", snapshot["state"])
        assertEquals(null, snapshot["modelName"])
        assertEquals(1, first.downloads)
        assertEquals(1, first.closes)
        assertEquals(1, current.closes)
        assertFalse(gate.isCompleted)
        session.detachEngine()
    }

    @Test
    fun shouldCancelEngineDetachAndRejectFurtherWorkExactlyOnce() = runTest {
        // Given an engine with one active model whose inference is pending.
        val first = Model(generationGate = CompletableDeferred())
        val factory = Factory(first)
        val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
        val outcomes = mutableListOf<GeminiNanoOutcome>()
        session.setForeground(true)
        session.submit("recognize", arguments(), outcomes::add)
        runCurrent()
        // When engine detach is repeated and a later probe is submitted.
        session.detachEngine()
        session.detachEngine()
        runCurrent()
        session.setForeground(true)
        session.submit("probe", null, outcomes::add)
        runCurrent()
        // Then each request has one engineDetached callback and no new native model.
        assertEquals(listOf("engineDetached", "engineDetached"), outcomes.map { (it as GeminiNanoOutcome.Error).code })
        assertEquals(1, first.closes)
        assertEquals(1, factory.creates)
    }

    @Test
    fun shouldRetainBusyOwnershipWhenACallbackStartsANewerRequest() = runTest {
        // Given a completed probe whose callback starts a second held inference.
        val first = Model()
        val gate = CompletableDeferred<Unit>()
        val second = Model(generationGate = gate)
        val factory = Factory(first, second)
        val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
        val firstOutcomes = mutableListOf<GeminiNanoOutcome>()
        val secondOutcomes = mutableListOf<GeminiNanoOutcome>()
        val overlap = mutableListOf<GeminiNanoOutcome>()
        session.setForeground(true)
        // When old completion delivers and its callback admits newer native work.
        session.submit("probe", null) {
            firstOutcomes.add(it)
            session.submit("recognize", arguments(), secondOutcomes::add)
        }
        runCurrent()
        session.submit("probe", null, overlap::add)
        gate.complete(Unit)
        runCurrent()
        // Then stale completion cannot clear newer ownership or deliver the old callback again.
        assertEquals(1, firstOutcomes.size)
        assertEquals(1, secondOutcomes.size)
        assertEquals("busy", (overlap.single() as GeminiNanoOutcome.Error).code)
        assertEquals(2, factory.creates)
        assertEquals(1, first.closes)
        assertEquals(1, second.closes)
        session.detachEngine()
    }

    @Test
    fun shouldTimeoutEachMethodWithVirtualTimeAfterCleanupAndRecover() = runTest {
        for ((method, deadline) in listOf("probe" to 20_000L, "prepare" to 600_000L, "recognize" to 90_000L)) {
            // Given this method suspended within its fresh native model.
            val gate = CompletableDeferred<Unit>()
            val first = when (method) {
                "probe" -> Model(statusGate = gate)
                "prepare" -> Model(state = GeminiNanoReadiness.DOWNLOADABLE, downloadGate = gate)
                else -> Model(generationGate = gate)
            }
            val next = Model()
            val session = GeminiNanoSession(GeminiNanoRequestRunner(Factory(first, next)), StandardTestDispatcher(testScheduler))
            val outcomes = mutableListOf<GeminiNanoOutcome>()
            session.setForeground(true)
            // When its own deadline is advanced exactly to timeout.
            session.submit(method, if (method == "recognize") arguments() else null, outcomes::add)
            runCurrent()
            advanceTimeBy(deadline - 1)
            runCurrent()
            assertTrue(outcomes.isEmpty())
            advanceTimeBy(1)
            runCurrent()
            session.submit("probe", null, outcomes::add)
            runCurrent()
            // Then timeout is one observable failure after close and a later request succeeds.
            assertEquals("timeout", (outcomes.first() as GeminiNanoOutcome.Error).code)
            assertEquals(2, outcomes.size)
            assertTrue(outcomes.last() is GeminiNanoOutcome.Success)
            assertEquals(1, first.closes)
            assertEquals(1, next.closes)
            assertFalse(gate.isCompleted)
            session.detachEngine()
        }
    }

    @Test
    fun shouldDeliverCancellationEvenBeforeTheScheduledBodyStarts() = runTest {
        for (engineDetach in listOf(false, true)) {
            // Given a foreground session with a scheduled body that has never run.
            val model = Model()
            val factory = Factory(model)
            val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
            val outcomes = mutableListOf<GeminiNanoOutcome>()
            session.setForeground(true)
            session.submit("probe", null, outcomes::add)
            // When the Activity or engine detaches before the dispatcher begins the body.
            if (engineDetach) session.detachEngine() else session.detachActivity()
            runCurrent()
            // Then cancellation delivers once with no allocated model to leak or close.
            assertEquals(1, outcomes.size)
            assertEquals(if (engineDetach) "engineDetached" else "foregroundRequired", (outcomes.single() as GeminiNanoOutcome.Error).code)
            assertEquals(0, factory.creates)
            assertEquals(0, model.closes)
            if (!engineDetach) {
                // Given that canceled-before-start Activity session is resumed.
                session.setForeground(true)
                // When a new probe runs after the cancellation callback.
                session.submit("probe", null, outcomes::add)
                runCurrent()
                // Then its released guard accepts exactly one actual model.
                assertEquals(2, outcomes.size)
                assertTrue(outcomes.last() is GeminiNanoOutcome.Success)
                assertEquals(1, factory.creates)
                assertEquals(1, model.closes)
                session.detachEngine()
            }
        }
    }

    @Test
    fun shouldExposeNativeFailureAndCleanupThenAcceptAnotherRequest() = runTest {
        // Given an actual generation error and a separately failing model close.
        val first = Model(generationFailure = IllegalStateException("native quota error"), closeFailure = IllegalStateException("close failed"))
        val next = Model()
        val session = GeminiNanoSession(GeminiNanoRequestRunner(Factory(first, next)), StandardTestDispatcher(testScheduler))
        val outcomes = mutableListOf<GeminiNanoOutcome>()
        session.setForeground(true)
        // When inference fails and then a new probe runs.
        session.submit("recognize", arguments(), outcomes::add)
        runCurrent()
        session.submit("probe", null, outcomes::add)
        runCurrent()
        // Then primary and cleanup descriptions survive while the guard recovers.
        val failure = outcomes.first() as GeminiNanoOutcome.Error
        assertEquals("nativeFailure", failure.code)
        assertTrue(failure.message.contains("native quota error"))
        assertEquals(failure.message, failure.details["nativeThrowable"])
        assertEquals(listOf("java.lang.IllegalStateException: close failed"), failure.details["cleanupFailures"])
        assertEquals(1, first.closes)
        assertEquals(1, next.closes)
        assertTrue(outcomes.last() is GeminiNanoOutcome.Success)
        session.detachEngine()
    }

    private fun arguments() = mapOf("bytes" to byteArrayOf(1, 2, 3), "prompt" to "prompt", "expectedModelName" to null)

    private class Factory(vararg models: Model) : GeminiNanoModelFactory {
        private val remaining = ArrayDeque(models.toList())
        var creates = 0
        override fun create(): GeminiNanoModel { creates++; return remaining.removeFirst() }
    }

    private class Model(
        val state: GeminiNanoReadiness = GeminiNanoReadiness.AVAILABLE,
        val statusGate: CompletableDeferred<Unit>? = null,
        val downloadGate: CompletableDeferred<Unit>? = null,
        val generationGate: CompletableDeferred<Unit>? = null,
        val generationFailure: Throwable? = null,
        val closeFailure: Throwable? = null,
    ) : GeminiNanoModel {
        var downloads = 0
        var closes = 0
        override suspend fun status(): GeminiNanoReadiness { statusGate?.await(); return state }
        override suspend fun modelName(): String = "actual-model"
        override fun download(): Flow<GeminiNanoDownload> = flow {
            downloads++
            emit(GeminiNanoDownload.Progress)
            downloadGate?.await()
            emit(GeminiNanoDownload.Completed)
        }
        override suspend fun generate(bytes: ByteArray, prompt: String, cleanupFailures: MutableList<String>): String {
            generationGate?.await()
            generationFailure?.let { throw it }
            return "raw generation"
        }
        override fun close() { closes++; closeFailure?.let { throw it } }
    }
}
