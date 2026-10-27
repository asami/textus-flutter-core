package org.textus.flutter.core.submission

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Durable app-private Core callback registration and serial WorkManager wakes. */
internal object SubmissionNativeScheduling {
    private const val preferences = "textus_submission_runtime"
    private const val callbackKey = "callback_handle"

    fun initialize(context: Context, handle: Long) {
        SubmissionWorkPolicy.callback(handle)
        if (FlutterCallbackInformation.lookupCallbackInformation(handle) == null) {
            throw SubmissionConfigurationFailure("configurationUnavailable")
        }
        if (!context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit()
                .putLong(callbackKey, handle).commit()) {
            throw SubmissionConfigurationFailure("configurationUnavailable")
        }
    }

    fun callback(context: Context): Long = SubmissionWorkPolicy.callback(
        context.getSharedPreferences(preferences, Context.MODE_PRIVATE).getLong(callbackKey, 0))

    /** Completion means enqueue was persisted; an active run retains appended wakes. */
    suspend fun schedule(context: Context, delayMs: Long) {
        val instruction = SubmissionWorkPolicy.wake(callback(context), delayMs)
        val request = OneTimeWorkRequestBuilder<SubmissionWorker>()
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
            .setInitialDelay(instruction.delayMs, TimeUnit.MILLISECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, instruction.backoffMs, TimeUnit.MILLISECONDS)
            .build()
        val operation = WorkManager.getInstance(context).enqueueUniqueWork(
            instruction.uniqueName, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
        val future = operation.result
        suspendCancellableCoroutine<Unit> { continuation ->
            future.addListener({
                try {
                    future.get()
                    if (continuation.isActive) continuation.resume(Unit)
                } catch (_: Exception) {
                    if (continuation.isActive) continuation.resumeWithException(
                        SubmissionConfigurationFailure("configurationUnavailable"))
                }
            }, java.util.concurrent.Executor { it.run() })
        }
    }
}

/** One engine per invocation. Root isolate uses normal automatic registration,
 * installs its handshake before executing Core's verified callback, and returns
 * only a strictly decoded terminal. Stop retires native ownership first, allows
 * at most five seconds for Dart cleanup, then destroys the owned engine on main.
 * An unfinished claim survives engine death and recovers through the queue lease.
 */
class SubmissionWorker(context: Context, parameters: WorkerParameters) : CoroutineWorker(context, parameters) {
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    @Volatile private var lifecycle: SubmissionRunLifecycle? = null
    private val drained = CompletableDeferred<Unit>()
    private var stopSent = false

    private fun networkAllowed(): Boolean {
        val manager = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val capabilities = manager.getNetworkCapabilities(manager.activeNetwork) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    }

    private fun signalStop() {
        val run = lifecycle ?: return
        run.retire()
        if (!stopSent && channel != null) {
            stopSent = true
            channel?.invokeMethod("stop", mapOf("runId" to run.runId))
        }
    }

    // CoroutineWorker.onStopped is final and cancels doWork on OS stoppage.
    // The cancellation path below retires ownership before bounded stop/drain.
    override suspend fun doWork(): Result {
        var completed = false
        try {
            return withTimeout(270000L) {
                if (isStopped) throw CancellationException("Submission worker stopped")
                val handle = SubmissionNativeScheduling.callback(applicationContext)
                val ready = CompletableDeferred<Unit>()
                val terminal = CompletableDeferred<SubmissionTerminal>()
                val run = SubmissionRunLifecycle("run_${UUID.randomUUID()}", 1L)
                lifecycle = run
                withContext(Dispatchers.Main.immediate) {
                    val loader = FlutterInjector.instance().flutterLoader()
                    loader.startInitialization(applicationContext)
                    loader.ensureInitializationComplete(applicationContext, null)
                    val callback = FlutterCallbackInformation.lookupCallbackInformation(handle)
                        ?: throw SubmissionConfigurationFailure("configurationUnavailable")
                    val owned = FlutterEngine(applicationContext)
                    engine = owned
                    val dispatch = MethodChannel(owned.dartExecutor.binaryMessenger,
                        "org.textus.flutter.core/submission-background")
                    channel = dispatch
                    dispatch.setMethodCallHandler { call, result ->
                        try {
                            if (call.method != "ready" || !run.isCurrent() || ready.isCompleted) {
                                throw SubmissionConfigurationFailure("configurationInvalid")
                            }
                            SubmissionConnectionPolicy.exact(call.arguments, emptySet())
                            ready.complete(Unit)
                            result.success(null)
                        } catch (_: Exception) {
                            result.error("configurationUnavailable", "Submission configuration is unavailable.", null)
                            if (!ready.isCompleted) ready.completeExceptionally(
                                SubmissionConfigurationFailure("configurationUnavailable"))
                        }
                    }
                    owned.dartExecutor.executeDartCallback(DartExecutor.DartCallback(
                        applicationContext.assets, loader.findAppBundlePath(), callback))
                }
                ready.await()
                if (isStopped || !run.isCurrent()) throw CancellationException("Submission worker stopped")
                withContext(Dispatchers.Main.immediate) {
                    channel!!.invokeMethod("start", mapOf("runId" to run.runId,
                        "networkAllowed" to networkAllowed()), object : MethodChannel.Result {
                        private var replied = false
                        private fun deliver(value: Any?, failed: Boolean) {
                            if (replied) return
                            replied = true
                            drained.complete(Unit)
                            if (!run.isCurrent()) return
                            try {
                                if (failed) throw SubmissionConfigurationFailure("configurationUnavailable")
                                val packet = SubmissionWorkPolicy.terminal(value)
                                if (run.acceptTerminal(run.runId, 1L)) terminal.complete(packet)
                            } catch (_: Exception) {
                                if (run.acceptTerminal(run.runId, 1L)) terminal.completeExceptionally(
                                    SubmissionConfigurationFailure("configurationUnavailable"))
                            }
                        }
                        override fun success(result: Any?) = deliver(result, false)
                        override fun error(code: String, message: String?, details: Any?) = deliver(null, true)
                        override fun notImplemented() = deliver(null, true)
                    })
                }
                val packet = terminal.await()
                if (isStopped) throw CancellationException("Submission worker stopped")
                val result = when (SubmissionWorkPolicy.decision(packet)) {
                    "success" -> Result.success()
                    "schedule" -> {
                        SubmissionNativeScheduling.schedule(applicationContext, packet.nextDelayMs!!)
                        Result.success()
                    }
                    "cancelled" -> throw CancellationException("Submission worker stopped")
                    else -> Result.retry()
                }
                completed = true
                result
            }
        } catch (error: TimeoutCancellationException) {
            lifecycle?.retire()
            if (isStopped) throw CancellationException("Submission worker stopped")
            return Result.retry()
        } catch (error: CancellationException) {
            lifecycle?.retire()
            throw error
        } catch (_: Exception) {
            if (isStopped) throw CancellationException("Submission worker stopped")
            return Result.retry()
        } finally {
            lifecycle?.retire()
            withContext(NonCancellable) {
                if (!completed) {
                    withContext(Dispatchers.Main.immediate) { signalStop() }
                    if (engine != null) withTimeoutOrNull(5000L) { drained.await() }
                }
                withContext(Dispatchers.Main.immediate) {
                    channel?.setMethodCallHandler(null)
                    channel = null
                    val owned = engine
                    engine = null
                    owned?.destroy()
                }
            }
        }
    }
}
