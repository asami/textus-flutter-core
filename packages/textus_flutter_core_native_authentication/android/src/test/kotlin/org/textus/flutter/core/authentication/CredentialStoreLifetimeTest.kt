package org.textus.flutter.core.authentication

import org.junit.Assert.*
import org.junit.Test

class CredentialStoreLifetimeTest {
    private fun closed(action: () -> Unit) {
        try { action(); fail("Expected retired operation") }
        catch (error: CredentialStoreFailure) { assertEquals(CredentialStoreFailure.CLOSED, error.code) }
    }

    @Test fun closeRetiresBeforeQueuedWorkAndWithdrawsIssuedResult() {
        // Given one issued operation, a second queued call and another handle.
        val lifetime = CredentialStoreLifetime()
        val issued = lifetime.accept("first")
        val queued = lifetime.accept("first")
        val other = lifetime.accept("second")
        lifetime.issue(issued)
        // When close retires synchronously before its queued drain barrier.
        lifetime.retire("first")
        closed { lifetime.issue(queued) }
        closed { lifetime.accept("first") }
        lifetime.issue(other)
        // Then issued work can settle once but cannot publish a value; other handles work.
        assertFalse(lifetime.current(issued))
        assertTrue(lifetime.complete(issued))
        assertFalse(lifetime.complete(issued))
        assertTrue(lifetime.complete(queued))
        assertTrue(lifetime.current(other))
        assertTrue(lifetime.complete(other))
        assertFalse(lifetime.complete(other))
    }

    @Test fun detachRejectsUnissuedWorkAndSuppressesAllLateReplies() {
        // Given live issued and queued operations from different handles.
        val lifetime = CredentialStoreLifetime()
        val issued = lifetime.accept("first")
        val queued = lifetime.accept("second")
        lifetime.issue(issued)
        // When the engine retires before shutdown drains its serial queue.
        lifetime.detach()
        closed { lifetime.issue(queued) }
        closed { lifetime.accept("third") }
        // Then no late/duplicate result can address a detached messenger.
        assertFalse(lifetime.isLive())
        assertFalse(lifetime.current(issued))
        assertFalse(lifetime.complete(issued))
        assertFalse(lifetime.complete(queued))
        assertFalse(lifetime.complete(issued))
        // Given a different engine lifetime, when one old engine detached, it stays live.
        val independent = CredentialStoreLifetime()
        val current = independent.accept("first")
        independent.issue(current)
        assertTrue(independent.complete(current))
    }
}
