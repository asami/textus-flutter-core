package org.textus.flutter.core.submission

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.joinAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** Engine-owned secure facade. Main owns replies/activity and lazy configuration
 * contexts; serialized IO uses only captured handles. Close retires a context
 * before cancellation/disposal, permitting sequential foreground reuse. Detach
 * retires replies, cancels SDK awaits and joins IO before captured cleanup.
 * Scheduler lifetime is independent of configuration acquisition and close.
 */
class TextusFlutterCoreAndroidSubmissionPlugin : FlutterPlugin, ActivityAware,
    MethodChannel.MethodCallHandler, PluginRegistry.ActivityResultListener,
    Application.ActivityLifecycleCallbacks {
    private var channel: MethodChannel? = null
    private var binding: ActivityPluginBinding? = null
    private var application: Application? = null
    private var applicationContext: Context? = null
    private var activityResumed = false
    private class NativeConfiguration(val store: SecureSubmissionStore, val authorization: GoogleDriveAuthorization)
    private val configurations = SubmissionConfigurationLifecycle<NativeConfiguration>()
    private val ownedConfigurations = mutableSetOf<NativeConfiguration>()
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val ioMutex = Mutex()
    private val jobs = mutableSetOf<Job>()
    private val replies = mutableSetOf<ResultOnce>()
    private var generation = 0L

    private class ResultOnce(private val result: MethodChannel.Result) {
        private var completed = false
        fun success(value: Any?) {
            if (!completed) { completed = true; result.success(value) }
        }
        fun error(code: String) {
            if (!completed) {
                completed = true
                result.error(code, SubmissionConfigurationFailure.messageFor(code), null)
            }
        }
    }

    private suspend fun <T> io(current: () -> Boolean, store: SecureSubmissionStore,
        action: (SecureSubmissionStore) -> T): T =
        withContext(Dispatchers.IO) { ioMutex.withLock {
            if (!current()) throw SubmissionConfigurationFailure("configurationClosed")
            val value = action(store)
            if (!current()) throw SubmissionConfigurationFailure("configurationClosed")
            value
        } }

    /** Partial construction closes its captured store and leaves no policy slot. */
    private fun acquireConfiguration(owner: Long): SubmissionConfigurationContext<NativeConfiguration> =
        configurations.acquire(owner) { requestCode, current ->
            val context = applicationContext ?: throw SubmissionConfigurationFailure("configurationUnavailable")
            val store = SecureSubmissionStore(context)
            var partialAuthorization: GoogleDriveAuthorization? = null
            try {
                val authorization = GoogleDriveAuthorization(context,
                    row = { id -> io(current, store) { it.credentialRow(id) } },
                    grant = { id, definition, granted, consentCurrent -> io(current, store) {
                        if (!consentCurrent() || !current()) {
                            throw SubmissionConfigurationFailure("authorizationCancelled")
                        }
                        it.setDriveGrant(id, definition, granted)
                    } },
                    engineCurrent = current,
                    requestCode = requestCode)
                partialAuthorization = authorization
                binding?.let { authorization.attach(it.activity, false, activityResumed) }
                NativeConfiguration(store, authorization).also { ownedConfigurations.add(it) }
            } catch (failure: Exception) {
                try { partialAuthorization?.close() } finally { store.close() }
                throw failure
            }
        }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        generation = configurations.attach()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val context = binding.applicationContext
        applicationContext = context
        application = context as? Application
        application?.registerActivityLifecycleCallbacks(this)
        channel = MethodChannel(binding.binaryMessenger, "org.textus.flutter.core/submission")
        channel!!.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val once = ResultOnce(result)
        try {
            if (!configurations.engineCurrent(generation)) throw SubmissionConfigurationFailure("configurationClosed")
            val keys = when (call.method) {
                "snapshot", "closeConfiguration" -> emptySet()
                "putDrive", "putHttp" -> setOf("connection")
                "select" -> setOf("storageConnectionId", "transportConnectionId")
                "setReferenceAccess" -> setOf("transportConnectionId", "storageConnectionIds")
                "setHttpBearerToken" -> setOf("connectionId", "token")
                "authorizeDrive", "authorizationState", "bearerToken" -> setOf("connectionId")
                "initializeBackground" -> setOf("callbackHandle")
                "scheduleBackground" -> setOf("delayMs")
                else -> { result.notImplemented(); return }
            }
            val args = SubmissionConnectionPolicy.exact(call.arguments, keys)
            val owner = generation
            val context = applicationContext ?: throw SubmissionConfigurationFailure("configurationUnavailable")
            val configuration = when (call.method) {
                "initializeBackground", "scheduleBackground", "closeConfiguration" -> null
                else -> acquireConfiguration(owner)
            }
            // Retirement precedes auth cancellation and any suspension, so a new
            // accepted call can only capture a fresh context, never this store.
            val retired = if (call.method == "closeConfiguration") {
                configurations.peek()?.let { configurations.retire(it) }
            } else null
            retired?.handle?.authorization?.close()
            val current = { configurations.engineCurrent(owner) &&
                (configuration == null || configurations.isCurrent(configuration)) }
            val auth = configuration?.handle?.authorization
            suspend fun <T> configurationIo(action: (SecureSubmissionStore) -> T): T =
                io(current, configuration?.handle?.store
                    ?: throw SubmissionConfigurationFailure("configurationUnavailable"), action)
            replies.add(once)
            val job = scope.launch {
                try {
                    if (!current()) throw SubmissionConfigurationFailure("configurationClosed")
                    val value: Any? = when (call.method) {
                        "snapshot" -> configurationIo { it.snapshot() }
                        "putDrive" -> { configurationIo { it.put(args["connection"], "googleDrive") }; null }
                        "putHttp" -> { configurationIo { it.put(args["connection"], "http") }; null }
                        "select" -> { configurationIo { it.select(SubmissionConnectionPolicy.nullableId(args["storageConnectionId"]),
                            SubmissionConnectionPolicy.nullableId(args["transportConnectionId"])) }; null }
                        "setReferenceAccess" -> { configurationIo { it.setReferenceAccess(
                            SubmissionConnectionPolicy.safeId(args["transportConnectionId"]), args["storageConnectionIds"]) }; null }
                        "setHttpBearerToken" -> { configurationIo { it.setHttpToken(SubmissionConnectionPolicy.safeId(args["connectionId"]),
                            SubmissionConnectionPolicy.bearer(args["token"])) }; null }
                        // Explicit foreground entry gets 160 seconds; silent state/token entries retain 20 seconds.
                        "authorizeDrive" -> SubmissionAuthorizationTiming.entry(call.method) { auth!!.authorize(SubmissionConnectionPolicy.safeId(args["connectionId"])) }
                        "authorizationState" -> SubmissionAuthorizationTiming.entry(call.method) { auth!!.state(SubmissionConnectionPolicy.safeId(args["connectionId"])) }
                        "bearerToken" -> SubmissionAuthorizationTiming.entry(call.method) { auth!!.bearerToken(SubmissionConnectionPolicy.safeId(args["connectionId"])) }
                        "initializeBackground" -> {
                            val handle = SubmissionWorkPolicy.callback(args["callbackHandle"])
                            withContext(Dispatchers.IO) { SubmissionNativeScheduling.initialize(context, handle) }
                            null
                        }
                        "scheduleBackground" -> {
                            SubmissionNativeScheduling.schedule(context, SubmissionWorkPolicy.delay(args["delayMs"]))
                            null
                        }
                        "closeConfiguration" -> {
                            withContext(Dispatchers.IO) { ioMutex.withLock { retired?.handle?.store?.close() } }
                            retired?.handle?.let { ownedConfigurations.remove(it) }
                            null
                        }
                        else -> throw SubmissionConfigurationFailure("configurationInvalid")
                    }
                    if (current()) once.success(value)
                    else once.error("configurationClosed")
                } catch (failure: SubmissionConfigurationFailure) {
                    once.error(if (current()) failure.code else "configurationClosed")
                } catch (_: CancellationException) {
                    once.error(if (current()) "authorizationCancelled" else "configurationClosed")
                } catch (_: Exception) {
                    once.error(if (current()) "configurationUnavailable" else "configurationClosed")
                } finally {
                    replies.remove(once)
                }
            }
            jobs.add(job)
            job.invokeOnCompletion { jobs.remove(job) }
        } catch (failure: SubmissionConfigurationFailure) {
            once.error(failure.code)
        } catch (_: Exception) {
            once.error("configurationUnavailable")
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        configurations.detach()
        val owned = ownedConfigurations.toList()
        ownedConfigurations.clear()
        owned.forEach { it.authorization.close() }
        detachActivity(false)
        application?.unregisterActivityLifecycleCallbacks(this)
        application = null
        applicationContext = null
        channel?.setMethodCallHandler(null)
        channel = null
        replies.toList().forEach { it.error("configurationClosed") }
        replies.clear()
        val pending = jobs.toList()
        scope.cancel()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            pending.joinAll()
            ioMutex.withLock {
                owned.forEach {
                    try { it.store.close() } catch (_: Exception) {
                        // Detached cleanup has no result owner; do not reflect raw errors.
                    }
                }
            }
        }
    }

    private fun attachActivity(value: ActivityPluginBinding, reattach: Boolean) {
        binding = value
        activityResumed = (value.activity as? LifecycleOwner)?.lifecycle?.currentState
            ?.isAtLeast(Lifecycle.State.RESUMED) == true
        value.addActivityResultListener(this)
        configurations.peek()?.handle?.authorization?.attach(value.activity, reattach, activityResumed)
    }
    private fun detachActivity(configurationChange: Boolean) {
        binding?.removeActivityResultListener(this)
        binding = null
        activityResumed = false
        configurations.peek()?.handle?.authorization?.detach(configurationChange)
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) = attachActivity(binding, false)
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = attachActivity(binding, true)
    override fun onDetachedFromActivityForConfigChanges() = detachActivity(true)
    override fun onDetachedFromActivity() = detachActivity(false)
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?): Boolean =
        configurations.peek()?.handle?.authorization?.activityResult(requestCode, resultCode, data) ?: false
    override fun onActivityResumed(activity: Activity) {
        if (binding?.activity === activity) activityResumed = true
        configurations.peek()?.handle?.authorization?.resume(activity)
    }
    override fun onActivityPaused(activity: Activity) {
        if (binding?.activity === activity) activityResumed = false
        configurations.peek()?.handle?.authorization?.pause(activity)
    }
    override fun onActivityCreated(activity: Activity, state: Bundle?) {}
    override fun onActivityStarted(activity: Activity) {}
    override fun onActivityStopped(activity: Activity) {}
    override fun onActivitySaveInstanceState(activity: Activity, state: Bundle) {}
    override fun onActivityDestroyed(activity: Activity) {}
}
