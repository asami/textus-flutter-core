package org.textus.flutter.core.genai

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
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
        for (method in listOf("probe", "prepare", "recognize", "generateDraft")) {
            // Given this valid foreground-gated method.
            val arguments = when (method) {
                "recognize" -> arguments()
                "generateDraft" -> draftArguments()
                else -> null
            }
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
        assertEquals(5, outcomes.size)
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
        for (method in listOf("probe", "prepare", "recognize", "generateDraft")) {
            // Given the original request still owning its native model.
            val input = when (method) {
                "recognize" -> arguments()
                "generateDraft" -> draftArguments()
                else -> null
            }
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
        assertEquals(6, outcomes.size)
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
        for ((method, deadline) in listOf("probe" to 20_000L, "prepare" to 600_000L, "recognize" to 90_000L, "generateDraft" to 90_000L)) {
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
            session.submit(method, when (method) {
                "recognize" -> arguments()
                "generateDraft" -> draftArguments()
                else -> null
            }, outcomes::add)
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

    @Test
    fun shouldAcknowledgeExactDraftCancellationBeforeItsScheduledBodyStarts() = runTest {
        // Given a foreground draft whose body has not yet reached the dispatcher.
        val model = Model()
        val factory = Factory(model)
        val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
        val terminal = mutableListOf<GeminiNanoOutcome>()
        val control = mutableListOf<GeminiNanoOutcome>()
        val overlap = mutableListOf<GeminiNanoOutcome>()
        session.setForeground(true)
        session.submit("generateDraft", draftArguments(), terminal::add)
        // When a mismatched ID is refused and the exact request is canceled before execution.
        session.submit("cancelDraft", mapOf("requestId" to "stale"), control::add)
        session.submit("cancelDraft", mapOf("requestId" to "draft-1"), control::add)
        session.submit("probe", null, overlap::add)
        // Then acknowledgement is immediate but terminal callback and busy release are still pending.
        assertEquals(listOf(false, true), control.map { (it as GeminiNanoOutcome.Success).value })
        assertTrue(terminal.isEmpty())
        assertEquals("busy", (overlap.single() as GeminiNanoOutcome.Error).code)
        assertEquals(0, factory.creates)
        runCurrent()
        session.submit("cancelDraft", mapOf("requestId" to "draft-1"), control::add)
        // Then exactly one canceled terminal outcome releases the owner without model allocation.
        assertEquals(1, terminal.size)
        assertEquals("canceled", (terminal.single() as GeminiNanoOutcome.Error).code)
        assertEquals(emptyList<String>(), (terminal.single() as GeminiNanoOutcome.Error).details["cleanupFailures"])
        assertEquals(false, (control.last() as GeminiNanoOutcome.Success).value)
        assertEquals(0, model.closes)
        assertEquals(0, factory.creates)
        session.detachEngine()
    }

    @Test
    fun shouldKeepCanceledDraftBusyUntilInferenceCleanupAndModelCloseFinish() = runTest {
        // Given a native draft suspended in inference and separately held cancellation cleanup.
        val infer = CompletableDeferred<Unit>()
        val cleanup = CompletableDeferred<Unit>()
        val model = Model(
            generationGate = infer, draftCleanupGate = cleanup, draftCleanup = "image recycle warning",
            closeFailure = IllegalStateException("canceled model close failed"),
        )
        val factory = Factory(model)
        val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
        val terminal = mutableListOf<GeminiNanoOutcome>()
        val control = mutableListOf<GeminiNanoOutcome>()
        session.setForeground(true)
        session.submit("generateDraft", draftArguments(operation = "textSummary"), terminal::add)
        runCurrent()
        // When the exact draft is canceled and enters its owned finally without finishing cleanup.
        session.submit("cancelDraft", mapOf("requestId" to "draft-1"), control::add)
        runCurrent()
        // Then the control acknowledged true, but no terminal callback/model close or new owner exists yet.
        assertEquals(true, (control.single() as GeminiNanoOutcome.Success).value)
        assertTrue(terminal.isEmpty())
        assertEquals(1, model.drafts)
        assertEquals(0, model.closes)
        for (method in listOf("probe", "prepare", "recognize", "generateDraft")) {
            // Given the canceled draft still owns its unfinished cleanup.
            val input = when (method) {
                "recognize" -> arguments()
                "generateDraft" -> draftArguments(id = "draft-2")
                else -> null
            }
            val overlaps = mutableListOf<GeminiNanoOutcome>()
            // When another regular operation attempts to overlap cleanup.
            session.submit(method, input, overlaps::add)
            // Then busy rejects before factory creation for every old and new regular method.
            assertEquals("busy", (overlaps.single() as GeminiNanoOutcome.Error).code)
            assertEquals(1, factory.creates)
        }
        // When the exact owner's cleanup is finally released.
        cleanup.complete(Unit)
        runCurrent()
        runCurrent()
        // Then one canceled callback follows its one close and contains every cleanup failure.
        val failure = terminal.single() as GeminiNanoOutcome.Error
        assertEquals("canceled", failure.code)
        assertEquals(listOf("image recycle warning", "java.lang.IllegalStateException: canceled model close failed"), failure.details["cleanupFailures"])
        assertEquals(1, model.closes)
        assertFalse(infer.isCompleted)
        assertEquals(0, model.downloads)
        session.detachEngine()
    }

    @Test
    fun shouldRefuseDraftCancellationForIdleOldMethodsAndDetachedSessions() = runTest {
        for (method in listOf("probe", "prepare", "recognize")) {
            // Given a valid idle control channel and this scheduled old request type.
            val model = Model()
            val factory = Factory(model)
            val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
            val control = mutableListOf<GeminiNanoOutcome>()
            val regular = mutableListOf<GeminiNanoOutcome>()
            session.submit("cancelDraft", mapOf("requestId" to "draft-1"), control::add)
            session.setForeground(true)
            session.submit(method, if (method == "recognize") arguments() else null, regular::add)
            // When cancelDraft uses an ID while an old operation owns the scheduled job.
            session.submit("cancelDraft", mapOf("requestId" to "draft-1"), control::add)
            // Then neither idle nor old operations can be canceled and controls allocate no model.
            assertEquals(listOf(false, false), control.map { (it as GeminiNanoOutcome.Success).value })
            assertEquals(0, factory.creates)
            runCurrent()
            // Then the old regular request completes normally with its one owned model.
            assertTrue(regular.single() is GeminiNanoOutcome.Success)
            assertEquals(1, model.closes)
            assertEquals(1, factory.creates)
            session.detachEngine()
            session.submit("cancelDraft", mapOf("requestId" to "draft-1"), control::add)
            assertEquals(false, (control.last() as GeminiNanoOutcome.Success).value)
            assertEquals(1, factory.creates)
        }
    }

    @Test
    fun shouldRejectMalformedCancellationBeforeForegroundBusyAndFactoryAdmission() = runTest {
        val invalid = listOf(
            null, "draft-1", emptyMap<String, Any?>(), mapOf("requestId" to "draft-1", "extra" to true),
            mapOf("requestId" to null), mapOf("requestId" to 4), mapOf("requestId" to ""),
            mapOf("requestId" to " "), mapOf("requestId" to " draft-1"), mapOf("requestId" to "draft-1 "),
            mapOf("requestId" to "draft\u0000id"),
        )
        // Given a background session and an observable native factory.
        val factory = Factory(Model())
        val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
        for (input in invalid) {
            // Given this non-exact one-key cancellation envelope.
            val outcomes = mutableListOf<GeminiNanoOutcome>()
            // When the control method parses it before any foreground or regular busy gate.
            session.submit("cancelDraft", input, outcomes::add)
            // Then invalidArguments is immediate and allocates no model.
            assertEquals("invalidArguments", (outcomes.single() as GeminiNanoOutcome.Error).code)
            assertEquals(0, factory.creates)
        }
        session.detachEngine()
    }

    @Test
    fun shouldIsolateStaleDraftCancellationWhenTerminalCallbackStartsANewerDraft() = runTest {
        // Given a completed first draft whose callback starts a second held draft.
        val first = Model()
        val gate = CompletableDeferred<Unit>()
        val second = Model(generationGate = gate)
        val factory = Factory(first, second)
        val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
        val earlier = mutableListOf<GeminiNanoOutcome>()
        val later = mutableListOf<GeminiNanoOutcome>()
        val controls = mutableListOf<GeminiNanoOutcome>()
        session.setForeground(true)
        session.submit("generateDraft", draftArguments()) {
            // Then the first callback is after its native model has closed.
            assertEquals(1, first.closes)
            earlier.add(it)
            session.submit("generateDraft", draftArguments(id = "draft-2"), later::add)
        }
        runCurrent()
        // When the old request ID attempts cancellation while a newer exact owner is pending.
        session.submit("cancelDraft", mapOf("requestId" to "draft-1"), controls::add)
        val overlap = mutableListOf<GeminiNanoOutcome>()
        session.submit("probe", null, overlap::add)
        // Then stale cancellation is false and old completion has not cleared newer busy ownership.
        assertEquals(false, (controls.single() as GeminiNanoOutcome.Success).value)
        assertEquals("busy", (overlap.single() as GeminiNanoOutcome.Error).code)
        assertTrue(later.isEmpty())
        assertEquals(0, second.closes)
        gate.complete(Unit)
        runCurrent()
        // Then both terminal callbacks delivered once with their own request identity and cleanup.
        assertEquals("draft-1", ((earlier.single() as GeminiNanoOutcome.Success).value as Map<*, *>)["requestId"])
        assertEquals("draft-2", ((later.single() as GeminiNanoOutcome.Success).value as Map<*, *>)["requestId"])
        assertEquals(1, second.closes)
        assertEquals(2, factory.creates)
        session.detachEngine()
    }

    @Test
    fun shouldCancelDraftsForPauseActivityDetachAndEngineDetachAfterOwnedCleanup() = runTest {
        for (event in listOf("pause", "activityDetach", "engineDetach")) {
            for (beforeBody in listOf(false, true)) {
                // Given a foreground draft, either scheduled or awaiting native inference.
                val gate = CompletableDeferred<Unit>()
                val first = Model(generationGate = if (beforeBody) null else gate, closeFailure = IllegalStateException("lifecycle close warning"))
                val next = Model()
                val factory = Factory(first, next)
                val session = GeminiNanoSession(GeminiNanoRequestRunner(factory), StandardTestDispatcher(testScheduler))
                val outcomes = mutableListOf<GeminiNanoOutcome>()
                session.setForeground(true)
                session.submit("generateDraft", draftArguments(), outcomes::add)
                if (!beforeBody) runCurrent()
                // When this actual Activity/engine ownership ends.
                when (event) {
                    "pause" -> session.setForeground(false)
                    "activityDetach" -> session.detachActivity()
                    else -> session.detachEngine()
                }
                runCurrent()
                // Then exactly one lifecycle failure follows cleanup, with no model if body never started.
                val failure = outcomes.single() as GeminiNanoOutcome.Error
                assertEquals(if (event == "engineDetach") "engineDetached" else "foregroundRequired", failure.code)
                assertEquals(if (beforeBody) 0 else 1, first.closes)
                assertEquals(if (beforeBody) emptyList<String>() else listOf("java.lang.IllegalStateException: lifecycle close warning"), failure.details["cleanupFailures"])
                assertEquals(if (beforeBody) 0 else 1, factory.creates)
                assertFalse(gate.isCompleted)
                if (event == "engineDetach") {
                    // Given a permanently detached engine after the canceled draft.
                    val control = mutableListOf<GeminiNanoOutcome>()
                    // When matching cancellation is requested after engine teardown.
                    session.submit("cancelDraft", mapOf("requestId" to "draft-1"), control::add)
                    // Then detached control acknowledgement is false with no new factory work.
                    assertEquals(false, (control.single() as GeminiNanoOutcome.Success).value)
                } else {
                    // Given the Activity has resumed after terminal cancellation.
                    session.setForeground(true)
                    // When a fresh draft starts after its predecessor has released ownership.
                    session.submit("generateDraft", draftArguments(id = "draft-2"), outcomes::add)
                    runCurrent()
                    // Then the fresh owner runs independently with its own exact identity and one close.
                    assertEquals(2, outcomes.size)
                    assertEquals("draft-2", ((outcomes.last() as GeminiNanoOutcome.Success).value as Map<*, *>)["requestId"])
                    assertEquals(1, if (beforeBody) first.closes else next.closes)
                    session.detachEngine()
                }
            }
        }
    }

    private fun draftArguments(id: String = "draft-1", operation: String = "imageDescription") = mapOf(
        "requestId" to id, "operation" to operation, "language" to "ja",
        "bytes" to if (operation == "imageDescription") byteArrayOf(1, 2, 3) else null,
        "prompt" to "日本語の正確なプロンプト", "expectedModelName" to "actual-model",
    )

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
        val draftCleanupGate: CompletableDeferred<Unit>? = null,
        val draftCleanup: String? = null,
    ) : GeminiNanoModel {
        var downloads = 0
        var closes = 0
        var drafts = 0
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
        override suspend fun generateDraft(bytes: ByteArray?, prompt: String, cleanupFailures: MutableList<String>): String {
            drafts++
            try {
                generationGate?.await()
                generationFailure?.let { throw it }
                return " 日本語の下書き "
            } finally {
                draftCleanupGate?.let { gate -> withContext(NonCancellable) { gate.await() } }
                draftCleanup?.let { cleanupFailures.add(it) }
            }
        }
        override fun close() { closes++; closeFailure?.let { throw it } }
    }
}
