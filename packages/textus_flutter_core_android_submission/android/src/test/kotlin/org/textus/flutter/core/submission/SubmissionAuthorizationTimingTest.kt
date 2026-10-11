package org.textus.flutter.core.submission

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Virtual-time timing and pure ownership specifications; these perform no native authorization. */
@OptIn(ExperimentalCoroutinesApi::class)
class SubmissionAuthorizationTimingTest {
    @Test fun sdkResponseThenHumanConsentCanExceedTwentySeconds() = runTest {
        // Given independently controlled SDK and consent replies and the production bounds (AT1).
        val sdkReply = CompletableDeferred<Unit>()
        val pending = CompletableDeferred<Unit>()
        var publications = 0
        var cleanups = 0
        // Given a child that owns both stage waits and its terminal cleanup.
        val call = async {
            runCatching {
                // When the production SDK stage completes, the distinct consent stage begins.
                SubmissionAuthorizationTiming.authorization {
                    try {
                        SubmissionAuthorizationTiming.sdk { sdkReply.await() }
                        SubmissionAuthorizationTiming.foregroundConsent { pending.await() }
                        // Then only completion of both controlled stages publishes one result.
                        publications++
                        "available"
                    } finally {
                        // Given this call's stage ownership, when it exits, then cleanup runs once.
                        cleanups++
                    }
                }
            }
        }
        try {
            testScheduler.runCurrent()
            // When the SDK replies at 8 seconds and the human reply takes another 45 seconds.
            testScheduler.advanceTimeBy(8000L)
            testScheduler.runCurrent()
            sdkReply.complete(Unit)
            testScheduler.runCurrent()
            testScheduler.advanceTimeBy(45000L)
            testScheduler.runCurrent()
            // Then exceeding the old total bound leaves consent pending without publication.
            assertEquals(53000L, testScheduler.currentTime)
            assertFalse(call.isCompleted)
            assertEquals(0, publications)
            // When the controlled human result arrives within its own bound.
            pending.complete(Unit)
            testScheduler.runCurrent()
            // Then the complete call succeeds and cleans up exactly once.
            assertEquals("available", call.await().getOrThrow())
            assertEquals(1, publications)
            assertEquals(1, cleanups)
        } finally {
            // Given scenario-owned waits, when teardown cancels and joins them, then none remain live.
            call.cancelAndJoin()
            sdkReply.cancel()
            pending.cancel()
            assertTrue(call.isCompleted && sdkReply.isCompleted && pending.isCompleted)
        }
    }

    @Test fun unresolvedSdkTimesOutBeforeConsentAndCleansUpOnce() = runTest {
        // Given an SDK reply that stays unresolved and consent that must not start (AT2).
        val sdkReply = CompletableDeferred<Unit>()
        var consentEntries = 0
        var cleanups = 0
        // Given a child with captured stage cleanup and an expected cancellation result.
        val call = async {
            runCatching {
                // When the real timing policy waits for this unresolved SDK operation.
                SubmissionAuthorizationTiming.authorization {
                    try {
                        SubmissionAuthorizationTiming.sdk { sdkReply.await() }
                        SubmissionAuthorizationTiming.foregroundConsent { consentEntries++ }
                    } finally {
                        // Given the owned SDK wait, when it exits, then it is cancelled once.
                        sdkReply.cancel()
                        cleanups++
                    }
                }
            }
        }
        try {
            testScheduler.runCurrent()
            // When virtual time reaches one millisecond before the SDK deadline.
            testScheduler.advanceTimeBy(19999L)
            testScheduler.runCurrent()
            // Then the child still waits and has entered no consent block or cleanup.
            assertFalse(call.isCompleted)
            assertEquals(0, consentEntries)
            assertEquals(0, cleanups)
            // When the exact 20-second boundary is processed.
            testScheduler.advanceTimeBy(1L)
            testScheduler.runCurrent()
            // Then the SDK timeout is captured, consent never starts and cleanup runs once.
            assertTrue(call.await().exceptionOrNull() is TimeoutCancellationException)
            assertEquals(20000L, testScheduler.currentTime)
            assertEquals(0, consentEntries)
            assertEquals(1, cleanups)
            assertTrue(sdkReply.isCancelled)
        } finally {
            // Given owned child/reply, when teardown cancels and joins them, then both are terminal.
            call.cancelAndJoin()
            sdkReply.cancel()
            assertTrue(call.isCompleted && sdkReply.isCompleted)
        }
    }

    @Test fun foregroundConsentHasItsOwnDeadlineAndRetiresCapturedOwner() = runTest {
        // Given a resumed real consent owner and independently controlled replies (AT3).
        val consent = SubmissionConsentLifecycle()
        consent.attach(true, false)
        val owner = consent.begin()
        val sdkReply = CompletableDeferred<Unit>()
        val pending = CompletableDeferred<Unit>()
        var publications = 0
        var cleanups = 0
        var finishes = 0
        // Given one captured child with an expected timeout represented as a result.
        val call = async {
            runCatching {
                // When SDK completion permits that same owner to launch and await consent.
                SubmissionAuthorizationTiming.authorization {
                    try {
                        SubmissionAuthorizationTiming.sdk { sdkReply.await() }
                        if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                        consent.launch(owner)
                        SubmissionAuthorizationTiming.foregroundConsent { pending.await() }
                        // Then a controlled grant can publish only while the captured owner is current.
                        if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                        publications++
                    } finally {
                        // Given the captured pending resolution, when the call exits, then retire it once.
                        pending.cancel()
                        if (consent.finish(owner)) finishes++
                        cleanups++
                    }
                }
            }
        }
        try {
            testScheduler.runCurrent()
            // When SDK completion starts consent at 8 seconds, followed by 119,999 milliseconds.
            testScheduler.advanceTimeBy(8000L)
            testScheduler.runCurrent()
            sdkReply.complete(Unit)
            testScheduler.runCurrent()
            testScheduler.advanceTimeBy(119999L)
            testScheduler.runCurrent()
            // Then the consent wait and its captured owner still live with no grant or cleanup.
            assertEquals(127999L, testScheduler.currentTime)
            assertFalse(call.isCompleted)
            assertTrue(consent.current(owner))
            assertEquals(0, publications)
            assertEquals(0, cleanups)
            // When the consent stage's own 120-second boundary is processed.
            testScheduler.advanceTimeBy(1L)
            testScheduler.runCurrent()
            // Then timeout at 128 seconds cancels pending consent and finishes only that owner once.
            assertTrue(call.await().exceptionOrNull() is TimeoutCancellationException)
            assertEquals(128000L, testScheduler.currentTime)
            assertTrue(pending.isCancelled)
            assertFalse(consent.current(owner))
            assertEquals(0, publications)
            assertEquals(1, finishes)
            assertEquals(1, cleanups)
        } finally {
            // Given owned child/replies, when teardown cancels and joins them, then no wait survives.
            call.cancelAndJoin()
            sdkReply.cancel()
            pending.cancel()
            assertTrue(call.isCompleted && sdkReply.isCompleted && pending.isCompleted)
        }
    }

    @Test fun enclosingAuthorizationBoundsAnUnresolvedPersistenceWait() = runTest {
        // Given unresolved local persistence outside the SDK and consent stages (AT4).
        val persistence = CompletableDeferred<Unit>()
        var cleanups = 0
        // Given a child that captures expected timeout without failing its test parent.
        val call = async {
            runCatching {
                // When the complete production authorization bound encloses local work.
                SubmissionAuthorizationTiming.authorization {
                    try {
                        persistence.await()
                    } finally {
                        // Given owned local work, when it exits, then its wait retires with one cleanup.
                        persistence.cancel()
                        cleanups++
                    }
                }
            }
        }
        try {
            testScheduler.runCurrent()
            // When the complete call is one millisecond short of its absolute bound.
            testScheduler.advanceTimeBy(159999L)
            testScheduler.runCurrent()
            // Then unfinished local work still waits with no premature cleanup.
            assertFalse(call.isCompleted)
            assertEquals(0, cleanups)
            // When the exact 160-second boundary is processed.
            testScheduler.advanceTimeBy(1L)
            testScheduler.runCurrent()
            // Then the outer call times out and cancels its local wait exactly once.
            assertTrue(call.await().exceptionOrNull() is TimeoutCancellationException)
            assertEquals(160000L, testScheduler.currentTime)
            assertEquals(1, cleanups)
            assertTrue(persistence.isCancelled)
        } finally {
            // Given owned local wait/child, when teardown cancels and joins them, then both are terminal.
            call.cancelAndJoin()
            persistence.cancel()
            assertTrue(call.isCompleted && persistence.isCompleted)
        }
    }

    @Test fun callerCancellationImmediatelyRetiresConsentAndRejectsLateCompletion() = runTest {
        // Given the actual resumed consent policy, a pending reply and one captured owner (AT5).
        val consent = SubmissionConsentLifecycle()
        consent.attach(true, false)
        val owner = consent.begin()
        val pending = CompletableDeferred<Unit>()
        var publications = 0
        var cleanups = 0
        var finishes = 0
        var cancellationObserved = false
        // Given a child that observes cancellation inside its own result boundary.
        val call = async {
            try {
                // When immediate controlled SDK success launches this owner's consent.
                SubmissionAuthorizationTiming.authorization {
                    try {
                        SubmissionAuthorizationTiming.sdk { Unit }
                        consent.launch(owner)
                        SubmissionAuthorizationTiming.foregroundConsent { pending.await() }
                        // Then only a current owner with a completed consent reply could publish.
                        if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                        publications++
                    } finally {
                        // Given captured pending consent, when cancellation exits, then retire it once.
                        pending.cancel()
                        if (consent.finish(owner)) finishes++
                        cleanups++
                    }
                }
                Result.success(Unit)
            } catch (failure: CancellationException) {
                // Given cancellation of this child, when observed, then record it without failing the parent.
                cancellationObserved = true
                Result.failure<Unit>(failure)
            }
        }
        try {
            testScheduler.runCurrent()
            // Then consent is pending before any virtual time advances.
            assertTrue(consent.current(owner))
            assertTrue(consent.resolving)
            assertFalse(call.isCompleted)
            // When the caller explicitly cancels the child at the current scheduler instant.
            call.cancel()
            testScheduler.runCurrent()
            call.join()
            // Then cancellation is immediate, cleanup is singular and the owner/reply are retired.
            assertEquals(0L, testScheduler.currentTime)
            assertTrue(call.isCancelled)
            assertTrue(cancellationObserved)
            assertTrue(pending.isCancelled)
            assertFalse(consent.current(owner))
            assertEquals(1, finishes)
            assertEquals(1, cleanups)
            assertEquals(0, publications)
            // When a late controlled reply attempts completion after retirement.
            val accepted = pending.complete(Unit)
            testScheduler.runCurrent()
            // Then it is rejected and cannot publish or trigger another cleanup.
            assertFalse(accepted)
            assertEquals(0, publications)
            assertEquals(1, cleanups)
            assertFalse(consent.finish(owner))
        } finally {
            // Given owned pending reply/child, when teardown cancels and joins them, then both are terminal.
            call.cancelAndJoin()
            pending.cancel()
            assertTrue(call.isCompleted && pending.isCompleted)
        }
    }

    @Test fun retirementBeforeSdkReplyCannotReviveCapturedOrReplacementOwner() = runTest {
        // Given one real consent lineage waiting for a controlled SDK reply (AT6).
        val consent = SubmissionConsentLifecycle()
        consent.attach(true, false)
        val owner = consent.begin()
        val sdkReply = CompletableDeferred<Unit>()
        var consentEntries = 0
        var publications = 0
        var cleanups = 0
        var staleFinishes = 0
        // Given a child permanently bound to that captured owner.
        val call = async {
            runCatching {
                // When production timing awaits SDK completion, ownership is checked after the await.
                SubmissionAuthorizationTiming.authorization {
                    try {
                        SubmissionAuthorizationTiming.sdk { sdkReply.await() }
                        if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                        consent.launch(owner)
                        SubmissionAuthorizationTiming.foregroundConsent { consentEntries++ }
                        // Then publication requires the original owner still to be current.
                        if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                        publications++
                    } finally {
                        // Given old captured ownership, when finishing, then only that owner is considered.
                        if (consent.finish(owner)) staleFinishes++
                        cleanups++
                    }
                }
            }
        }
        var replacement: Long? = null
        try {
            testScheduler.runCurrent()
            // When engine retirement precedes a new lineage and the delayed SDK reply.
            consent.cancel()
            consent.attach(true, false)
            val next = consent.begin()
            replacement = next
            testScheduler.advanceTimeBy(8000L)
            testScheduler.runCurrent()
            sdkReply.complete(Unit)
            testScheduler.runCurrent()
            // Then the safe stale-owner failure prevents consent/grant and preserves the replacement.
            val failure = call.await().exceptionOrNull()
            assertTrue(failure is SubmissionConfigurationFailure)
            assertEquals("authorizationCancelled", (failure as SubmissionConfigurationFailure).code)
            assertFalse(consent.current(owner))
            assertTrue(consent.current(next))
            assertEquals(0, consentEntries)
            assertEquals(0, publications)
            assertEquals(0, staleFinishes)
            assertEquals(1, cleanups)
        } finally {
            // Given owned child/reply/replacement, when teardown retires them, then no pending owner survives.
            call.cancelAndJoin()
            sdkReply.cancel()
            replacement?.let { consent.finish(it) }
            assertTrue(call.isCompleted && sdkReply.isCompleted)
            assertFalse(consent.current(owner))
            replacement?.let { assertFalse(consent.current(it)) }
        }
    }

    @Test fun unrelatedPauseBeforeSdkReplyPreventsConsentAndGrant() = runTest {
        // Given a resumed real consent owner before any resolution has launched (AT7).
        val consent = SubmissionConsentLifecycle()
        consent.attach(true, false)
        val owner = consent.begin()
        val sdkReply = CompletableDeferred<Unit>()
        var consentEntries = 0
        var publications = 0
        var cleanups = 0
        // Given a child whose delayed SDK continuation still uses that same owner.
        val call = async {
            runCatching {
                // When SDK completion returns, the captured current-owner check precedes consent launch.
                SubmissionAuthorizationTiming.authorization {
                    try {
                        SubmissionAuthorizationTiming.sdk { sdkReply.await() }
                        if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                        consent.launch(owner)
                        SubmissionAuthorizationTiming.foregroundConsent { consentEntries++ }
                        // Then a controlled grant also requires the same current owner.
                        if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                        publications++
                    } finally {
                        // Given captured old ownership, when exiting, then finish cannot restore it.
                        consent.finish(owner)
                        cleanups++
                    }
                }
            }
        }
        try {
            testScheduler.runCurrent()
            // When an unrelated pause interrupts the prelaunch wait.
            val cancelled = consent.pause()
            // Then the real policy cancels that owner before SDK completion.
            assertTrue(cancelled)
            assertFalse(consent.current(owner))
            // When the delayed SDK reply subsequently arrives at 8 seconds.
            testScheduler.advanceTimeBy(8000L)
            testScheduler.runCurrent()
            sdkReply.complete(Unit)
            testScheduler.runCurrent()
            // Then a safe stale-owner failure prevents consent and any controlled publication.
            val failure = call.await().exceptionOrNull()
            assertTrue(failure is SubmissionConfigurationFailure)
            assertEquals("authorizationCancelled", (failure as SubmissionConfigurationFailure).code)
            assertEquals(0, consentEntries)
            assertEquals(0, publications)
            assertEquals(1, cleanups)
            assertFalse(consent.resolving)
            assertFalse(consent.finish(owner))
        } finally {
            // Given owned child/reply, when teardown cancels and joins them, then neither remains live.
            call.cancelAndJoin()
            sdkReply.cancel()
            assertTrue(call.isCompleted && sdkReply.isCompleted)
            assertFalse(consent.current(owner))
        }
    }

    @Test fun expectedPauseAndConfigurationReattachRetainOneConsentCompletion() = runTest {
        // Given a real resumed consent owner and one controlled pending result (AT8).
        val consent = SubmissionConsentLifecycle()
        consent.attach(true, false)
        val owner = consent.begin()
        val pending = CompletableDeferred<Unit>()
        var publications = 0
        var cleanups = 0
        var finishes = 0
        // Given a child that may publish and finish only its captured owner.
        val call = async {
            runCatching {
                // When immediate SDK completion launches the production-bounded consent wait.
                SubmissionAuthorizationTiming.authorization {
                    try {
                        SubmissionAuthorizationTiming.sdk { Unit }
                        if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                        consent.launch(owner)
                        SubmissionAuthorizationTiming.foregroundConsent { pending.await() }
                        // Then successful controlled consent publishes only for that still-current owner.
                        if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                        publications++
                    } finally {
                        // Given the captured resolution, when exiting, then finish that owner exactly once.
                        if (!pending.isCompleted) pending.cancel()
                        if (consent.finish(owner)) finishes++
                        cleanups++
                    }
                }
            }
        }
        var replacement: Long? = null
        try {
            testScheduler.runCurrent()
            // Then consent is launched under the captured owner before its expected pause.
            assertTrue(consent.resolving)
            assertTrue(consent.current(owner))
            // When the launched resolution pauses and configuration detach/reattach retains its lineage.
            val pauseCancelled = consent.pause()
            val detachCancelled = consent.detach(true)
            consent.attach(true, true)
            // Then neither transition cancels and the same generation remains current.
            assertFalse(pauseCancelled)
            assertFalse(detachCancelled)
            assertEquals(owner, consent.generation)
            assertTrue(consent.current(owner))
            // When a delayed consent reply arrives at 45 seconds within its 120-second stage budget.
            testScheduler.advanceTimeBy(45000L)
            testScheduler.runCurrent()
            pending.complete(Unit)
            testScheduler.runCurrent()
            // Then one successful result publishes, finishes the captured owner and clears resolving.
            assertTrue(call.await().isSuccess)
            assertEquals(45000L, testScheduler.currentTime)
            assertEquals(1, publications)
            assertEquals(1, finishes)
            assertEquals(1, cleanups)
            assertFalse(consent.current(owner))
            assertFalse(consent.resolving)
            // Given a subsequent activity lineage, when a duplicate reply and late old finish arrive.
            consent.attach(true, false)
            val next = consent.begin()
            replacement = next
            val duplicateAccepted = pending.complete(Unit)
            val lateFinishAccepted = consent.finish(owner)
            testScheduler.runCurrent()
            // Then neither is accepted, no second publication occurs and the new owner stays current.
            assertFalse(duplicateAccepted)
            assertFalse(lateFinishAccepted)
            assertTrue(consent.current(next))
            assertEquals(1, publications)
            assertEquals(1, finishes)
            assertEquals(1, cleanups)
        } finally {
            // Given owned child/reply/replacement, when teardown retires them, then no wait/owner survives.
            call.cancelAndJoin()
            pending.cancel()
            replacement?.let { consent.finish(it) }
            assertTrue(call.isCompleted && pending.isCompleted)
            assertFalse(consent.current(owner))
            replacement?.let { assertFalse(consent.current(it)) }
        }
    }

    @Test fun nativeEntryAllowsSdkAndConsentToExceedTwentySeconds() = runTest {
        // Given controlled SDK/consent replies and the shared production authorizeDrive entry (AT9).
        val sdkReply = CompletableDeferred<Unit>()
        val pending = CompletableDeferred<Unit>()
        var publications = 0
        var cleanups = 0
        // Given one child owning both waits and the nested production authorization stages.
        val call = async {
            runCatching {
                // When native entry dispatch encloses the internal SDK and foreground consent bounds.
                SubmissionAuthorizationTiming.entry("authorizeDrive") {
                    SubmissionAuthorizationTiming.authorization {
                        try {
                            SubmissionAuthorizationTiming.sdk { sdkReply.await() }
                            SubmissionAuthorizationTiming.foregroundConsent { pending.await() }
                            // Then completing both controlled stages permits one available result.
                            publications++
                            "available"
                        } finally {
                            // Given owned stage waits, when exiting, then retire them with one cleanup.
                            sdkReply.cancel()
                            pending.cancel()
                            cleanups++
                        }
                    }
                }
            }
        }
        try {
            testScheduler.runCurrent()
            // When SDK completion takes 8 seconds and consent remains pending for another 45 seconds.
            testScheduler.advanceTimeBy(8000L)
            testScheduler.runCurrent()
            sdkReply.complete(Unit)
            testScheduler.runCurrent()
            testScheduler.advanceTimeBy(45000L)
            testScheduler.runCurrent()
            // Then the actual shared entry policy survives 53 seconds without premature completion.
            assertEquals(53000L, testScheduler.currentTime)
            assertFalse(call.isCompleted)
            assertEquals(0, publications)
            assertEquals(0, cleanups)
            // When the controlled consent reply completes within its own production budget.
            pending.complete(Unit)
            testScheduler.runCurrent()
            // Then entry dispatch returns available once and performs exactly one cleanup.
            assertEquals("available", call.await().getOrThrow())
            assertEquals(1, publications)
            assertEquals(1, cleanups)
            // When a duplicate consent reply arrives after the completed entry.
            val duplicateAccepted = pending.complete(Unit)
            testScheduler.runCurrent()
            // Then it cannot produce another result or cleanup.
            assertFalse(duplicateAccepted)
            assertEquals(1, publications)
            assertEquals(1, cleanups)
        } finally {
            // Given owned child/replies, when teardown cancels and joins them, then all are terminal.
            call.cancelAndJoin()
            sdkReply.cancel()
            pending.cancel()
            assertTrue(call.isCompleted && sdkReply.isCompleted && pending.isCompleted)
        }
    }

    @Test fun nativeEntryBoundsUnresolvedForegroundWorkAtOneHundredSixtySeconds() = runTest {
        // Given unresolved owned local work at the shared production foreground entry (AT10).
        val pending = CompletableDeferred<Unit>()
        var publications = 0
        var cleanups = 0
        // Given a child that captures its expected timeout and owns the local wait.
        val call = async {
            runCatching {
                // When authorizeDrive entry dispatch bounds unfinished foreground work.
                SubmissionAuthorizationTiming.entry("authorizeDrive") {
                    try {
                        pending.await()
                        // Then publication requires local completion before the entry deadline.
                        publications++
                    } finally {
                        // Given the owned pending work, when entry exits, then retire it once.
                        pending.cancel()
                        cleanups++
                    }
                }
            }
        }
        try {
            testScheduler.runCurrent()
            // When virtual time reaches one millisecond before the 160-second entry deadline.
            testScheduler.advanceTimeBy(159999L)
            testScheduler.runCurrent()
            // Then the call and pending work remain active without publication or cleanup.
            assertEquals(159999L, testScheduler.currentTime)
            assertFalse(call.isCompleted)
            assertTrue(pending.isActive)
            assertEquals(0, publications)
            assertEquals(0, cleanups)
            // When the exact shared foreground entry deadline is processed.
            testScheduler.advanceTimeBy(1L)
            testScheduler.runCurrent()
            // Then entry times out at 160 seconds, publishes nothing and retires pending work once.
            assertTrue(call.await().exceptionOrNull() is TimeoutCancellationException)
            assertEquals(160000L, testScheduler.currentTime)
            assertEquals(0, publications)
            assertEquals(1, cleanups)
            assertTrue(pending.isCancelled)
        } finally {
            // Given owned child/local wait, when teardown cancels and joins them, then neither survives.
            call.cancelAndJoin()
            pending.cancel()
            assertTrue(call.isCompleted && pending.isCompleted)
        }
    }

    @Test fun nativeEntryKeepsAuthorizationStateAtTwentySeconds() = runTest {
        // Given an unresolved owned silent state operation at the shared entry (AT11).
        val pending = CompletableDeferred<Unit>()
        var publications = 0
        var cleanups = 0
        // Given a child that captures the silent deadline without invoking any consent stage.
        val call = async {
            runCatching {
                // When the exact authorizationState method enters the production dispatcher.
                SubmissionAuthorizationTiming.entry("authorizationState") {
                    try {
                        pending.await()
                        // Then a state result can publish only after silent work completes.
                        publications++
                    } finally {
                        // Given the owned silent wait, when exiting, then retire it with one cleanup.
                        pending.cancel()
                        cleanups++
                    }
                }
            }
        }
        try {
            testScheduler.runCurrent()
            // When virtual time reaches one millisecond before the silent entry deadline.
            testScheduler.advanceTimeBy(19999L)
            testScheduler.runCurrent()
            // Then state work remains active without publication or cleanup.
            assertEquals(19999L, testScheduler.currentTime)
            assertFalse(call.isCompleted)
            assertTrue(pending.isActive)
            assertEquals(0, publications)
            assertEquals(0, cleanups)
            // When the exact 20-second silent deadline is processed.
            testScheduler.advanceTimeBy(1L)
            testScheduler.runCurrent()
            // Then state dispatch times out with no result and exactly one pending-wait cleanup.
            assertTrue(call.await().exceptionOrNull() is TimeoutCancellationException)
            assertEquals(20000L, testScheduler.currentTime)
            assertEquals(0, publications)
            assertEquals(1, cleanups)
            assertTrue(pending.isCancelled)
        } finally {
            // Given owned child/silent wait, when teardown cancels and joins them, then both are terminal.
            call.cancelAndJoin()
            pending.cancel()
            assertTrue(call.isCompleted && pending.isCompleted)
        }
    }

    @Test fun nativeEntryKeepsBearerTokenAtTwentySeconds() = runTest {
        // Given an unresolved owned silent token operation at the shared entry (AT12).
        val pending = CompletableDeferred<Unit>()
        var publications = 0
        var cleanups = 0
        // Given a child that captures the silent deadline without invoking any consent stage.
        val call = async {
            runCatching {
                // When the exact bearerToken method enters the production dispatcher.
                SubmissionAuthorizationTiming.entry("bearerToken") {
                    try {
                        pending.await()
                        // Then a token result can publish only after silent work completes.
                        publications++
                    } finally {
                        // Given the owned silent wait, when exiting, then retire it with one cleanup.
                        pending.cancel()
                        cleanups++
                    }
                }
            }
        }
        try {
            testScheduler.runCurrent()
            // When virtual time reaches one millisecond before the silent entry deadline.
            testScheduler.advanceTimeBy(19999L)
            testScheduler.runCurrent()
            // Then token work remains active without publication or cleanup.
            assertEquals(19999L, testScheduler.currentTime)
            assertFalse(call.isCompleted)
            assertTrue(pending.isActive)
            assertEquals(0, publications)
            assertEquals(0, cleanups)
            // When the exact 20-second silent deadline is processed.
            testScheduler.advanceTimeBy(1L)
            testScheduler.runCurrent()
            // Then token dispatch times out with no result and exactly one pending-wait cleanup.
            assertTrue(call.await().exceptionOrNull() is TimeoutCancellationException)
            assertEquals(20000L, testScheduler.currentTime)
            assertEquals(0, publications)
            assertEquals(1, cleanups)
            assertTrue(pending.isCancelled)
        } finally {
            // Given owned child/silent wait, when teardown cancels and joins them, then both are terminal.
            call.cancelAndJoin()
            pending.cancel()
            assertTrue(call.isCompleted && pending.isCompleted)
        }
    }

    @Test fun nativeEntryPropagatesCallerCancellationAndRejectsLateCompletion() = runTest {
        // Given a real resumed consent lifecycle, captured owner and pending resolution (AT13).
        val consent = SubmissionConsentLifecycle()
        consent.attach(true, false)
        val owner = consent.begin()
        val pending = CompletableDeferred<Unit>()
        var publications = 0
        var cleanups = 0
        var finishes = 0
        var cancellationObserved = false
        // Given a child that retains the captured owner through entry and internal authorization.
        val call = async {
            try {
                // When immediate SDK completion launches that owner's production-bounded consent.
                SubmissionAuthorizationTiming.entry("authorizeDrive") {
                    SubmissionAuthorizationTiming.authorization {
                        try {
                            SubmissionAuthorizationTiming.sdk { Unit }
                            consent.launch(owner)
                            SubmissionAuthorizationTiming.foregroundConsent { pending.await() }
                            // Then only the current captured owner could publish a completed grant.
                            if (!consent.current(owner)) throw SubmissionConfigurationFailure("authorizationCancelled")
                            publications++
                        } finally {
                            // Given captured pending consent, when exiting, then cancel and finish it once.
                            pending.cancel()
                            if (consent.finish(owner)) finishes++
                            cleanups++
                        }
                    }
                }
                Result.success(Unit)
            } catch (failure: CancellationException) {
                // Given caller cancellation, when observed inside the child, then record its propagation.
                cancellationObserved = true
                Result.failure<Unit>(failure)
            }
        }
        try {
            testScheduler.runCurrent()
            // Then the captured owner's resolution is launched before virtual time advances.
            assertTrue(consent.current(owner))
            assertTrue(consent.resolving)
            assertFalse(call.isCompleted)
            // When the caller cancels the shared entry at virtual time zero.
            call.cancel()
            testScheduler.runCurrent()
            call.join()
            // Then cancellation retires the captured owner and pending reply with singular cleanup.
            assertEquals(0L, testScheduler.currentTime)
            assertTrue(call.isCancelled)
            assertTrue(cancellationObserved)
            assertTrue(pending.isCancelled)
            assertFalse(consent.current(owner))
            assertFalse(consent.resolving)
            assertEquals(0, publications)
            assertEquals(1, finishes)
            assertEquals(1, cleanups)
            // When the retired pending reply attempts a late controlled completion.
            val accepted = pending.complete(Unit)
            testScheduler.runCurrent()
            // Then completion is rejected without publication, another finish or another cleanup.
            assertFalse(accepted)
            assertFalse(consent.finish(owner))
            assertEquals(0, publications)
            assertEquals(1, finishes)
            assertEquals(1, cleanups)
        } finally {
            // Given owned child/reply/lineage, when teardown retires them, then no wait or owner survives.
            call.cancelAndJoin()
            pending.cancel()
            consent.finish(owner)
            assertTrue(call.isCompleted && pending.isCompleted)
            assertFalse(consent.current(owner))
        }
    }

    @Test fun nativeEntryRejectsUnknownMethodBeforeInvokingOperation() = runTest {
        // Given an unknown authorization method and an observable operation invocation count (AT14).
        var invocations = 0
        // When the real closed entry dispatcher receives that unknown method.
        val result = runCatching {
            SubmissionAuthorizationTiming.entry("unknownAuthorizationMethod") {
                invocations++
                Unit
            }
        }
        // Then the fixed safe configuration failure is returned before the operation can run.
        val failure = result.exceptionOrNull()
        assertTrue(failure is SubmissionConfigurationFailure)
        assertEquals("configurationInvalid", (failure as SubmissionConfigurationFailure).code)
        assertEquals("Submission configuration is invalid.", failure.message)
        assertEquals(0, invocations)
        assertEquals(0L, testScheduler.currentTime)
    }
}
