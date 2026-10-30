package org.textus.flutter.core.genai

import kotlin.coroutines.EmptyCoroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

internal sealed class GeminiNanoOutcome {
    class Success(val value: Any?) : GeminiNanoOutcome()
    class Error(val code: String, val message: String, val details: Map<String, Any?>) : GeminiNanoOutcome()
}

/** Main-dispatcher session owns foreground admission, deadlines and callbacks. */
internal class GeminiNanoSession(
    private val runner: GeminiNanoRequestRunner,
    private val dispatcher: CoroutineDispatcher = Dispatchers.Main.immediate,
) {
    private val scope = CoroutineScope(SupervisorJob() + dispatcher)
    private var foreground = false
    private var detached = false
    private var active: Active? = null

    private class Active(val request: GeminiNanoRequest, val callback: (GeminiNanoOutcome) -> Unit) {
        lateinit var job: Job
        val cleanupFailures = mutableListOf<String>()
        var outcome: GeminiNanoOutcome? = null
        var cancellationCode: String? = null
        var delivered = false
    }

    fun submit(method: String, arguments: Any?, callback: (GeminiNanoOutcome) -> Unit) {
        if (method == "cancelDraft") {
            val requestId = try {
                GeminiNanoRequest.parseDraftCancellation(arguments)
            } catch (error: GeminiNanoFailure) {
                callback(failure(error.code, nativeDescription(error), emptyList()))
                return
            }
            val entry = active
            val request = entry?.request
            val matches = !detached && request is GeminiNanoRequest.Draft && request.requestId == requestId
            if (matches) cancelActive("canceled")
            // Acknowledgement records intent; finish still owns cleanup and release.
            callback(GeminiNanoOutcome.Success(matches))
            return
        }
        val request = try {
            GeminiNanoRequest.parse(method, arguments)
        } catch (error: GeminiNanoFailure) {
            callback(failure(error.code, nativeDescription(error), emptyList()))
            return
        }
        val rejection = when {
            detached -> "engineDetached"
            !foreground -> "foregroundRequired"
            active != null -> "busy"
            else -> null
        }
        if (rejection != null) {
            callback(failure(rejection, "Nano request rejected: $rejection", emptyList()))
            return
        }
        val entry = Active(request, callback)
        active = entry
        entry.job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                entry.outcome = GeminiNanoOutcome.Success(withTimeout(request.deadlineMillis) {
                    runner.execute(request, entry.cleanupFailures)
                })
            } catch (error: TimeoutCancellationException) {
                entry.outcome = failure("timeout", nativeDescription(error), entry.cleanupFailures)
            } catch (error: CancellationException) {
                entry.outcome = failure(entry.cancellationCode ?: "nativeFailure", nativeDescription(error), entry.cleanupFailures)
                throw error
            } catch (error: Throwable) {
                entry.outcome = failure(
                    (error as? GeminiNanoFailure)?.code ?: "nativeFailure",
                    nativeDescription(error), entry.cleanupFailures,
                )
            }
        }
        // Completion also runs when cancellation prevents the lazy body starting.
        entry.job.invokeOnCompletion { cause ->
            dispatcher.dispatch(EmptyCoroutineContext, Runnable { finish(entry, cause) })
        }
        entry.job.start()
    }

    fun setForeground(resumed: Boolean) {
        foreground = !detached && resumed
        if (!foreground) cancelActive("foregroundRequired")
    }

    fun detachActivity() = setForeground(false)

    fun detachEngine() {
        if (detached) return
        detached = true
        foreground = false
        cancelActive("engineDetached")
        scope.cancel(CancellationException("engineDetached"))
    }

    private fun cancelActive(code: String) {
        val entry = active ?: return
        entry.cancellationCode = code
        entry.job.cancel(CancellationException(code))
    }

    private fun finish(entry: Active, cause: Throwable?) {
        if (entry.delivered) return
        entry.delivered = true
        val code = entry.cancellationCode
        val outcome = if (code != null) {
            failure(code, cause?.let(::nativeDescription) ?: "Nano request canceled: $code", entry.cleanupFailures)
        } else entry.outcome ?: failure(
            "nativeFailure", cause?.let(::nativeDescription) ?: "Nano request completed without an outcome",
            entry.cleanupFailures,
        )
        // Clear before the callback, and only for this exact request owner.
        if (active === entry) active = null
        entry.callback(outcome)
    }

    private fun failure(code: String, description: String, cleanupFailures: List<String>) =
        GeminiNanoOutcome.Error(code, description, mapOf(
            "nativeThrowable" to description,
            "cleanupFailures" to cleanupFailures.toList(),
        ))
}
