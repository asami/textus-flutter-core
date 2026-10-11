package org.textus.flutter.core.submission

import org.junit.Assert.*
import org.junit.Test

/** Pure NB7 policy evidence; WorkManager persistence and engine restart remain native obligations. */
class SubmissionWorkPolicyTest {
    private fun packet(outcome: String = "pending", operations: Any = 8, delay: Any? = 120000L): Map<String, Any?> {
        // Given a terminal outcome/count and a separately computed business due time.
        val fields = mapOf("outcome" to outcome, "operations" to operations, "nextDelayMs" to delay)
        // When native policy receives a complete terminal packet.
        val supplied = fields.toMap()
        // Then assertions exercise strict decoding and actual scheduling decisions.
        return supplied
    }

    @Test fun pendingBusinessDeadlineSchedulesAndDrainedOnlyCompletesScheduling() {
        // Given a pending queue whose next retry is exactly two minutes away.
        val pending = SubmissionWorkPolicy.terminal(packet())
        // When terminal policy chooses how to close this invocation.
        val decision = SubmissionWorkPolicy.decision(pending)
        // Then the exact due delay survives and the result schedules rather than inventing acknowledgement.
        assertEquals("schedule", decision)
        assertEquals(120000L, pending.nextDelayMs)
        assertEquals(8, pending.operations)
        val drained = SubmissionWorkPolicy.terminal(packet("drained", 1, null))
        assertEquals("success", SubmissionWorkPolicy.decision(drained))
        assertEquals("retry", SubmissionWorkPolicy.decision(SubmissionWorkPolicy.terminal(packet("pending", 1, null))))
        assertEquals("retry", SubmissionWorkPolicy.decision(SubmissionWorkPolicy.terminal(packet("drained", 1, 0))))
    }

    @Test fun infrastructureAndOfflineRetryWhileStoppedOwnershipRemainsCancelled() {
        // Given terminal infrastructure/offline/cancellation outcomes, without request payloads.
        val outcomes = listOf("failure", "offline", "cancelled")
        // When each terminal is decoded and dispatched through the closed policy.
        val decisions = outcomes.map { SubmissionWorkPolicy.decision(SubmissionWorkPolicy.terminal(packet(it, 0, null))) }
        // Then failures use infrastructure retry and cancelled ownership is never reported as success.
        assertEquals(listOf("retry", "retry", "cancelled"), decisions)
    }

    @Test fun exactSchemaCountsAndDelaysRejectUnknownSubmittedOrUnsafeScalars() {
        // Given malformed terminal shapes that must never acknowledge durable intent.
        val values = listOf(packet("submitted"), packet(operations = -1), packet(operations = 9),
            packet(operations = 1.0), packet(delay = -1), packet(delay = 86400001L),
            packet(delay = 1.0), packet() + ("token" to "PRIVATE_MARKER"), packet() - "operations")
        // When the policy decodes these actual inputs.
        for (value in values) {
            val failure = assertThrows(SubmissionConfigurationFailure::class.java) { SubmissionWorkPolicy.terminal(value) }
            // Then rejection has a fixed safe failure with no reflected payload.
            assertEquals("configurationInvalid", failure.code)
            assertFalse(failure.message!!.contains("PRIVATE_MARKER"))
        }
        // When both valid boundary delays and counts are supplied.
        assertEquals(0L, SubmissionWorkPolicy.terminal(packet(operations = 0, delay = 0)).nextDelayMs)
        assertEquals(86400000L, SubmissionWorkPolicy.terminal(packet(delay = 86400000L)).nextDelayMs)
        // Then the business deadline is bounded without guessing Submitted.
        assertEquals("schedule", SubmissionWorkPolicy.decision(SubmissionWorkPolicy.terminal(packet(delay = 0))))
    }

    @Test fun callbackRegistrationMustPrecedeBoundedSerialWakeInstructions() {
        // Given a positive persisted Core callback and two wakes requested during active completion.
        val first = SubmissionWorkPolicy.wake(101L, 0L)
        val second = SubmissionWorkPolicy.wake(101L, 30000L)
        // When both are converted into the exact shared native scheduling instructions.
        val instructions = listOf(first, second)
        // Then both retain append semantics, connected normal work, and their own due times.
        assertEquals(listOf(0L, 30000L), instructions.map { it.delayMs })
        assertTrue(instructions.all { it.enqueuePolicy == "APPEND_OR_REPLACE" })
        assertTrue(instructions.all { it.networkConstraint == "CONNECTED" && !it.expedited })
        assertTrue(instructions.all { it.backoffMs == 30000L && it.uniqueName == "textus_submission" })
        // When callback registration or delay is invalid, no instruction can be produced.
        assertThrows(SubmissionConfigurationFailure::class.java) { SubmissionWorkPolicy.wake(0L, 0L) }
        assertThrows(SubmissionConfigurationFailure::class.java) { SubmissionWorkPolicy.wake(101L, -1L) }
        assertThrows(SubmissionConfigurationFailure::class.java) { SubmissionWorkPolicy.callback("101") }
        // Then no payload/account/path is needed to retain either scheduling request.
        assertEquals(first.callbackHandle, second.callbackHandle)
    }
}
