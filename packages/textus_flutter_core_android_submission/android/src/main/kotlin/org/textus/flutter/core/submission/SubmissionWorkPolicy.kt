package org.textus.flutter.core.submission

/** Closed terminal packet; it never includes a request, token, account or path. */
internal data class SubmissionTerminal(val outcome: String, val operations: Int, val nextDelayMs: Long?)

/** Complete normal-work instruction; callback registration must already exist. */
internal data class SubmissionWake(val callbackHandle: Long, val delayMs: Long,
    val uniqueName: String, val enqueuePolicy: String, val networkConstraint: String,
    val expedited: Boolean, val backoffMs: Long)

/** Pure scheduling policy. Android WorkManager implements these exact decisions. */
internal object SubmissionWorkPolicy {
    const val uniqueName = "textus_submission"
    const val enqueuePolicy = "APPEND_OR_REPLACE"
    const val networkConstraint = "CONNECTED"
    const val expedited = false
    const val backoffMs = 30000L
    const val maximumDelayMs = 86400000L

    fun wake(callbackHandle: Any?, delayMs: Any?): SubmissionWake = SubmissionWake(
        callback(callbackHandle), delay(delayMs), uniqueName, enqueuePolicy,
        networkConstraint, expedited, backoffMs)

    fun delay(value: Any?): Long {
        val delay = SubmissionConnectionPolicy.integer(value)
        if (delay !in 0..maximumDelayMs) throw SubmissionConfigurationFailure("configurationInvalid")
        return delay
    }

    fun callback(value: Any?): Long {
        val handle = SubmissionConnectionPolicy.integer(value)
        if (handle <= 0) throw SubmissionConfigurationFailure("configurationInvalid")
        return handle
    }

    fun terminal(value: Any?): SubmissionTerminal {
        val map = SubmissionConnectionPolicy.exact(value, setOf("outcome", "operations", "nextDelayMs"))
        val outcome = SubmissionConnectionPolicy.string(map["outcome"])
        if (outcome !in setOf("drained", "pending", "offline", "cancelled", "failure")) {
            throw SubmissionConfigurationFailure("configurationInvalid")
        }
        val operations = SubmissionConnectionPolicy.integer(map["operations"])
        if (operations !in 0..8) throw SubmissionConfigurationFailure("configurationInvalid")
        return SubmissionTerminal(outcome, operations.toInt(), map["nextDelayMs"]?.let(::delay))
    }

    /** Infrastructure failures retry; business due times append a delayed wake. */
    fun decision(terminal: SubmissionTerminal): String = when (terminal.outcome) {
        "cancelled" -> "cancelled"
        "failure", "offline" -> "retry"
        "pending" -> if (terminal.nextDelayMs == null) "retry" else "schedule"
        "drained" -> if (terminal.nextDelayMs == null) "success" else "retry"
        else -> "retry"
    }
}
