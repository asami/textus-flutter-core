package org.textus.flutter.core.submission

import org.junit.Assert.*
import org.junit.Test

/** Pure NB6/configuration transition evidence; no real engine, key or SDK proof. */
class SubmissionRunLifecycleTest {
    private class ConfigurationHandle(val backing: MutableMap<String, String>, val current: () -> Boolean) {
        var closeCount = 0
            private set
        fun close() {
            // Given this controlled handle owns only its context-local disposal.
            if (closeCount == 0) {
                // When its captured owner disposes the handle for the first time.
                closeCount++
            }
            // Then backing values survive and repeated disposal stays idempotent.
        }
    }

    @Test fun configurationCloseReacquiresDistinctHandleWithPersistedDefinitionsAndSelection() {
        // Given one attached engine and controlled persisted safe configuration.
        val lifecycle = SubmissionConfigurationLifecycle<ConfigurationHandle>()
        val owner = lifecycle.attach()
        val backing = mutableMapOf<String, String>()
        val first = lifecycle.acquire(owner) { _, current ->
            // Given the factory borrows persisted backing from this scenario.
            // When a context-local handle is constructed with its ownership guard.
            val handle = ConfigurationHandle(backing, current)
            // Then construction retains backing rather than replacing persisted values.
            handle
        }
        backing["definition"] = "safe_http_target"
        backing["selection"] = "server"
        assertTrue(first.handle.current())
        // When close retires/disposes the captured context and the same engine reacquires.
        val retired = lifecycle.retire(first)
        retired!!.handle.close()
        val fresh = lifecycle.acquire(owner) { _, current ->
            // Given the same persisted definitions after the first disposal.
            // When a fresh handle captures its own guard.
            val handle = ConfigurationHandle(backing, current)
            // Then the fresh handle has independent disposal state.
            handle
        }
        val repeated = lifecycle.retire(first)
        first.handle.close()
        // Then old ownership never revives, persisted values remain and fresh disposal is untouched.
        assertSame(first, retired)
        assertNotSame(first, fresh)
        assertNotSame(first.handle, fresh.handle)
        assertFalse(lifecycle.isCurrent(first))
        assertTrue(lifecycle.isCurrent(fresh))
        assertEquals(mapOf("definition" to "safe_http_target", "selection" to "server"), fresh.handle.backing)
        assertNull(repeated)
        assertEquals(1, first.handle.closeCount)
        assertEquals(0, fresh.handle.closeCount)
        assertSame(fresh, lifecycle.acquire(owner) { _, _ ->
            // Given an already live configuration slot.
            // When an unexpected factory invocation attempts to replace it.
            // Then fail this scenario rather than silently allocating another handle.
            error("live context must be reused")
        })
    }

    @Test fun retiredStoreGrantAndTokenCallbacksStayInvalidAfterReacquireAndDetach() {
        // Given captured store, grant-write and token-publication guards from one context.
        val lifecycle = SubmissionConfigurationLifecycle<ConfigurationHandle>()
        val owner = lifecycle.attach()
        val backing = mutableMapOf<String, String>()
        val old = lifecycle.acquire(owner) { _, current ->
            // Given scenario-owned backing and a captured context guard.
            // When the controlled handle is allocated.
            val handle = ConfigurationHandle(backing, current)
            // Then all delayed callbacks can retain that exact guard.
            handle
        }
        val delayedStore = old.handle.current
        val delayedGrant = old.handle.current
        val delayedToken = old.handle.current
        // When close removes the old slot and a fresh context becomes current.
        val capturedCleanup = lifecycle.retire(old)!!
        val fresh = lifecycle.acquire(owner) { _, current ->
            // Given the same engine and durable backing.
            // When the factory captures fresh ownership.
            val handle = ConfigurationHandle(backing, current)
            // Then old callbacks cannot obtain this handle's ownership.
            handle
        }
        capturedCleanup.handle.close()
        // Then no delayed old store/grant/token dispatch is current; fresh ownership is usable.
        assertFalse(delayedStore())
        assertFalse(delayedGrant())
        assertFalse(delayedToken())
        assertTrue(fresh.handle.current())
        assertEquals(0, fresh.handle.closeCount)
        // When engine detach retires the fresh handle before cleanup and further acquire.
        val detached = lifecycle.detach()!!
        val failure = assertThrows(SubmissionConfigurationFailure::class.java) {
            lifecycle.acquire(owner) { _, _ ->
                // Given engine ownership was detached before acquisition.
                // When an unexpected factory invocation occurs.
                // Then fail this scenario instead of manufacturing a detached handle.
                error("detached factory must not run")
            }
        }
        detached.handle.close()
        // Then both lineages are invalid and only their captured handles were disposed.
        assertFalse(lifecycle.engineCurrent(owner))
        assertFalse(delayedToken())
        assertFalse(fresh.handle.current())
        assertEquals("configurationClosed", failure.code)
        assertEquals(1, old.handle.closeCount)
        assertEquals(1, fresh.handle.closeCount)
        assertNull(lifecycle.detach())
        // When an explicit new engine attachment permits a new context.
        val nextOwner = lifecycle.attach()
        val next = lifecycle.acquire(nextOwner) { _, current ->
            // Given persisted backing retained after engine cleanup.
            // When the new engine constructs an independent handle.
            val handle = ConfigurationHandle(backing, current)
            // Then only that new engine's context may become current.
            handle
        }
        // Then old engine acquisition stays rejected and resolution codes are not reset.
        assertTrue(next.handle.current())
        assertFalse(lifecycle.engineCurrent(owner))
        assertNotEquals(fresh.requestCode, next.requestCode)
    }

    @Test fun failedFactoryLeavesNoSlotAndResolutionCodesRemainDistinctWithoutWrap() {
        // Given the actual lazy policy and a factory that fails before installing a handle.
        val lifecycle = SubmissionConfigurationLifecycle<Any>()
        val owner = lifecycle.attach()
        var failedCode = 0
        // When first construction fails and a later acquire retries in the same engine.
        assertThrows(IllegalStateException::class.java) {
            lifecycle.acquire(owner) { code, current ->
                // Given an uninstalled construction reservation.
                failedCode = code
                // When construction observes its guard before failing.
                val usable = current()
                // Then no usable ownership is exposed from partial construction.
                assertFalse(usable)
                throw IllegalStateException("controlled factory failure")
            }
        }
        // Then failure leaves no live slot for later operations to reuse.
        assertNull(lifecycle.peek())
        // When a later construction succeeds using a fresh code.
        val first = lifecycle.acquire(owner) { _, _ ->
            // Given no live slot remains from the failed factory.
            // When a controlled handle is constructed.
            val handle = Any()
            // Then successful construction returns only its new handle.
            handle
        }
        lifecycle.retire(first)
        val fresh = lifecycle.acquire(owner) { _, _ ->
            // Given the recovered context has now retired.
            // When another controlled handle is constructed.
            val handle = Any()
            // Then the next context receives distinct handle/code ownership.
            handle
        }
        // Then failed and retired contexts never donate their resolution code to a replacement.
        assertEquals(21861, failedCode)
        assertEquals(21862, first.requestCode)
        assertEquals(21863, fresh.requestCode)
        assertFalse(lifecycle.isCurrent(first))
        assertTrue(lifecycle.isCurrent(fresh))
        // Given a controlled near-exhaustion allocator, using the production upper bound.
        val bounded = SubmissionConfigurationLifecycle<Any>(65535)
        val boundedOwner = bounded.attach()
        val last = bounded.acquire(boundedOwner) { _, _ ->
            // Given one remaining code at the production upper bound.
            // When a controlled handle is constructed.
            val handle = Any()
            // Then only that last available reservation may install the handle.
            handle
        }
        // When the final code retires and another context is requested, also after reattach.
        bounded.retire(last)
        val exhausted = assertThrows(SubmissionConfigurationFailure::class.java) {
            bounded.acquire(boundedOwner) { _, _ ->
                // Given all bounded resolution codes are consumed.
                // When a factory is unexpectedly invoked anyway.
                // Then fail instead of allowing fallback ownership.
                error("exhausted factory must not run")
            }
        }
        bounded.detach()
        val nextOwner = bounded.attach()
        val stillExhausted = assertThrows(SubmissionConfigurationFailure::class.java) {
            bounded.acquire(nextOwner) { _, _ ->
                // Given exhaustion persisted across explicit engine reattachment.
                // When a reset would unexpectedly invoke the factory.
                // Then fail instead of accepting a reused retired resolution code.
                error("codes must not reset")
            }
        }
        // Then exhaustion never wraps, reuses a retired code or installs a fallback slot.
        assertEquals(65535, last.requestCode)
        assertEquals("configurationUnavailable", exhausted.code)
        assertEquals("configurationUnavailable", stillExhausted.code)
        assertNull(bounded.peek())
        assertFalse(bounded.isCurrent(last))
    }

    @Test fun stopIsMonotonicAndLateCallbacksCannotPublishTerminal() {
        // Given one safe native run and its matching engine generation.
        val run = SubmissionRunLifecycle("run_one", 7)
        assertTrue(run.isCurrent())
        assertFalse(run.isCurrent("run_other", 7))
        assertFalse(run.isCurrent("run_one", 8))
        // When native ownership retires before stop is delivered to Dart.
        run.retire()
        run.retire()
        // Then no matching or stale callback can revive or publish it.
        assertFalse(run.isCurrent())
        assertFalse(run.acceptTerminal("run_one", 7))
        assertFalse(run.acceptTerminal("run_other", 7))
    }

    @Test fun oneMatchingTerminalWinsAndDetachedGenerationLoses() {
        // Given live ownership and a callback carrying the wrong generation.
        val run = SubmissionRunLifecycle("run_one", 11)
        // When wrong-owner, matching and duplicate terminals arrive in order.
        assertFalse(run.acceptTerminal("run_one", 10))
        assertTrue(run.acceptTerminal("run_one", 11))
        // Then the matching terminal wins once and ownership stays retired.
        assertFalse(run.acceptTerminal("run_one", 11))
        assertFalse(run.isCurrent())
        assertThrows(SubmissionConfigurationFailure::class.java) { SubmissionRunLifecycle("../private", 1) }
    }

    @Test fun consentRequiresResumedOwnerAndAllowsOnlyOneOutstandingRequest() {
        // Given an attached activity lineage that has not yet resumed.
        val consent = SubmissionConsentLifecycle()
        consent.attach(false, false)
        // When explicit consent is requested without foreground, then after resume.
        val missing = assertThrows(SubmissionConfigurationFailure::class.java) { consent.begin() }
        consent.resume()
        val owner = consent.begin()
        val busy = assertThrows(SubmissionConfigurationFailure::class.java) { consent.begin() }
        // Then only the resumed exact owner remains current and competing consent fails.
        assertEquals("foregroundRequired", missing.code)
        assertEquals("authorizationBusy", busy.code)
        assertTrue(consent.current(owner))
        assertTrue(consent.finish(owner))
        assertFalse(consent.finish(owner))
    }

    @Test fun unrelatedPauseCancelsButLaunchedConsentSurvivesExpectedPause() {
        // Given foreground consent before it has launched its own resolution.
        val consent = SubmissionConsentLifecycle()
        consent.attach(true, false)
        val first = consent.begin()
        // When an unrelated activity pause interrupts that operation.
        assertTrue(consent.pause())
        // Then its generation is permanently stale.
        assertFalse(consent.current(first))
        consent.resume()
        val launched = consent.begin()
        // When its own resolution launch precedes the expected activity pause.
        consent.launch(launched)
        assertFalse(consent.pause())
        // Then the same pending owner may consume one verified resolution result.
        assertTrue(consent.current(launched))
        assertTrue(consent.finish(launched))
        assertFalse(consent.current(launched))
    }

    @Test fun configurationReattachRetainsOnlyExpectedResolutionLineage() {
        // Given one launched consent resolution followed by activity replacement.
        val consent = SubmissionConsentLifecycle()
        consent.attach(true, false)
        val retained = consent.begin()
        consent.launch(retained)
        // When a configuration change reattaches that same pending lineage.
        assertFalse(consent.detach(true))
        consent.attach(true, true)
        // Then only the retained owner can finish; later permanent detach cancels it.
        assertTrue(consent.current(retained))
        assertTrue(consent.detach(false))
        assertFalse(consent.current(retained))
        consent.attach(true, true)
        val replacement = consent.begin()
        assertNotEquals(retained, replacement)
        assertFalse(consent.finish(retained))
        assertTrue(consent.finish(replacement))
    }

    @Test fun configurationDetachBeforeLaunchAndEngineCancellationDoNotRetainConsent() {
        // Given foreground pending consent that has no launched resolution.
        val consent = SubmissionConsentLifecycle()
        consent.attach(true, false)
        val old = consent.begin()
        // When configuration detach interrupts it, then a new engine cancels its own request.
        assertTrue(consent.detach(true))
        consent.attach(true, true)
        val next = consent.begin()
        consent.cancel()
        // Then neither old nor new late SDK callback is current or may finish.
        assertFalse(consent.current(old))
        assertFalse(consent.current(next))
        assertFalse(consent.finish(next))
    }
}
