package org.textus.flutter.core.audio

import android.Manifest
import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
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
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Session-isolated explicit audio operations, confined to the main dispatcher. */
class TextusFlutterCoreAndroidAudioPlugin : FlutterPlugin, ActivityAware,
    MethodChannel.MethodCallHandler, PluginRegistry.RequestPermissionsResultListener,
    Application.ActivityLifecycleCallbacks {
    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var application: Application? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val sessions = mutableMapOf<String, Session>()
    private var permission: PermissionRequest? = null
    private val permissionLifecycle = AudioPermissionLifecycle()

    private class Session {
        var generation = 0L
        var terminal = false
        var operation: String? = null
        var pending: ResultOnce? = null
        var job: Job? = null
        var cleanup: Job? = null
        var cleanupFailure: Throwable? = null
        val cleanupLifecycle = AudioCleanupLifecycle()
        var recording: PcmAudioRecording? = null
        var playback: AudioPlayback? = null
        val transcriber = SavedAudioTranscriber()
    }

    private class ResultOnce(private val result: MethodChannel.Result) {
        private var terminal = false
        fun success(value: Any?) {
            if (!terminal) { terminal = true; result.success(value) }
        }
        fun error(code: String, message: String?) {
            if (!terminal) { terminal = true; result.error(code, message, null) }
        }
    }

    private data class PermissionRequest(val session: Session, val maximum: Int,
        val result: ResultOnce, val generation: Long, val activity: Activity,
        var granted: Boolean = false)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        context = binding.applicationContext
        application = binding.applicationContext as? Application
        application?.registerActivityLifecycleCallbacks(this)
        channel = MethodChannel(binding.binaryMessenger, "org.textus.flutter.core/audio")
        channel?.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val once = ResultOnce(result)
        try {
            if (context == null) throw AudioFailure("detached", "Audio engine is detached")
            val extras = when (call.method) {
                "availability", "prepare" -> setOf("locale")
                "startRecording" -> setOf("maxDurationSeconds")
                "play" -> setOf("bytes")
                "transcribe" -> setOf("bytes", "locale")
                "stopRecording", "cancelRecording", "stopPlayback", "cancelTranscription", "dispose" -> emptySet()
                else -> { result.notImplemented(); return }
            }
            val arguments = call.arguments as? Map<*, *>
                ?: throw AudioFailure("invalidArguments", "Expected an argument map")
            if (arguments.keys != extras + "sessionId") throw AudioFailure("invalidArguments", "Unexpected audio arguments")
            val id = arguments["sessionId"] as? String
                ?: throw AudioFailure("invalidSession", "Missing session identity")
            if (!Regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$").matches(id)) {
                throw AudioFailure("invalidSession", "Unsafe session identity")
            }
            val session = sessions.getOrPut(id) { Session() }
            if (call.method == "dispose") {
                disposeSession(session, once)
                return
            }
            if (session.terminal) throw AudioFailure("disposed", "Audio session is terminally disposed")
            when (call.method) {
                "availability" -> operation(session, "availability", once) {
                    session.transcriber.availability(string(arguments, "locale"))
                }
                "prepare" -> operation(session, "prepare", once) {
                    session.transcriber.prepare(string(arguments, "locale"))
                }
                "startRecording" -> {
                    val maximum = arguments["maxDurationSeconds"] as? Int
                        ?: throw AudioFailure("invalidDuration", "Expected integer recording limit")
                    if (maximum !in 1..120) throw AudioFailure("invalidDuration", "Recording limit must be 1..120 seconds")
                    startRecording(session, maximum, once)
                }
                "stopRecording" -> {
                    if (session.operation != "recording" || session.pending != null) {
                        throw AudioFailure("notRecording", "No started recording to stop")
                    }
                    session.operation = null
                    operation(session, "saving", once) {
                        val recording = session.recording
                            ?: throw AudioFailure("notRecording", "No active recorder")
                        try { recording.stop() } finally { session.recording = null }
                    }
                }
                "cancelRecording" -> interrupt(session, setOf("recording", "saving"), once, idleAllowed = true)
                "play" -> operation(session, "playing", once) {
                    val playback = AudioPlayback(context!!)
                    session.playback = playback
                    try { playback.play(bytes(arguments)); null }
                    finally { session.playback = null }
                }
                "stopPlayback" -> interrupt(session, setOf("playing"), once, idleAllowed = true)
                "transcribe" -> operation(session, "transcribing", once) {
                    session.transcriber.transcribe(bytes(arguments), string(arguments, "locale"))
                }
                "cancelTranscription" -> interrupt(session,
                    setOf("availability", "prepare", "transcribing"), once, idleAllowed = true)
            }
        } catch (error: Throwable) { failure(once, error) }
    }

    private fun startRecording(session: Session, maximum: Int, result: ResultOnce) {
        idle(session)
        val activity = activityBinding?.activity
            ?: throw AudioFailure("missingActivity", "Recording permission requires an attached Activity")
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            if (!permissionLifecycle.isResumed) {
                throw AudioFailure("activityPaused", "Recording requires a foreground Activity")
            }
            launchRecording(session, maximum, result)
            return
        }
        if (permission != null) throw AudioFailure("permissionBusy", "Another microphone permission request is active")
        session.operation = "recording"
        session.pending = result
        val request = PermissionRequest(session, maximum, result, ++session.generation, activity)
        permission = request
        try { activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), PERMISSION_REQUEST) }
        catch (error: Throwable) {
            permission = null
            permissionLifecycle.cancel()
            session.operation = null
            session.pending = null
            throw error
        }
    }

    private fun launchRecording(session: Session, maximum: Int, result: ResultOnce) {
        operation(session, "recording", result, retainRecording = true) {
            val recording = PcmAudioRecording(maximum)
            session.recording = recording
            recording.start(scope)
            null
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int,
        permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val request = permission ?: return true
        val session = request.session
        if (session.terminal || session.generation != request.generation ||
            activityBinding?.activity !== request.activity || session.pending !== request.result) {
            discardPermission(request, "cancelled", "Microphone permission request was cancelled")
            return true
        }
        val index = permissions.indexOf(Manifest.permission.RECORD_AUDIO)
        if (index < 0 || index >= grantResults.size || grantResults[index] != PackageManager.PERMISSION_GRANTED) {
            discardPermission(request, "permissionDenied", "Microphone permission was denied")
        } else {
            request.granted = true
            if (permissionLifecycle.grant()) launchGrantedPermission(request)
        }
        return true
    }

    private fun discardPermission(request: PermissionRequest, code: String, message: String) {
        if (permission === request) {
            permission = null
            permissionLifecycle.cancel()
        }
        if (request.session.pending === request.result) {
            request.session.pending = null
            request.session.operation = null
        }
        request.result.error(code, message)
    }

    private fun launchGrantedPermission(request: PermissionRequest) {
        val session = request.session
        if (permission !== request || !request.granted || !permissionLifecycle.isResumed ||
            session.terminal || session.generation != request.generation ||
            activityBinding?.activity !== request.activity || session.pending !== request.result) {
            discardPermission(request, "cancelled", "Microphone permission request was cancelled")
            return
        }
        permission = null
        permissionLifecycle.cancel()
        session.pending = null
        session.operation = null
        try { launchRecording(session, request.maximum, request.result) }
        catch (error: Throwable) { failure(request.result, error) }
    }

    private fun idle(session: Session) {
        if (session.terminal) throw AudioFailure("disposed", "Audio session is terminally disposed")
        if (session.operation != null || session.cleanup?.isActive == true) {
            throw AudioFailure("busy", "Another audio operation is active in this session")
        }
    }

    private fun operation(session: Session, name: String, result: ResultOnce,
        retainRecording: Boolean = false, block: suspend () -> Any?) {
        idle(session)
        val generation = ++session.generation
        session.operation = name
        session.pending = result
        // The job is assigned before work can complete on Main.immediate.
        val job = scope.launch(start = kotlinx.coroutines.CoroutineStart.LAZY) {
            var successful = false
            try {
                val value = block()
                if (session.terminal || session.generation != generation) {
                    result.error("cancelled", "Audio operation was cancelled")
                } else {
                    successful = true
                    result.success(value)
                }
            } catch (error: Throwable) { failure(result, error) }
            finally {
                if (name == "recording" && !successful) {
                    withContext(NonCancellable) { session.recording?.cancel() }
                    session.recording = null
                }
                if (session.generation == generation) {
                    session.pending = null
                    session.job = null
                    if (!retainRecording || !successful) session.operation = null
                }
            }
        }
        session.job = job
        job.start()
    }

    private fun interrupt(session: Session, expected: Set<String>, result: ResultOnce,
        idleAllowed: Boolean = false) {
        if (session.cleanupLifecycle.hasActive) {
            if (!session.cleanupLifecycle.canJoin(expected)) {
                throw AudioFailure("notActive", "No matching interruptible audio cleanup")
            }
            val cleanup = session.cleanup
            scope.launch {
                try {
                    cleanup?.join()
                    val error = session.cleanupFailure
                    if (error != null) failure(result, error)
                    else if (session.terminal) result.error("disposed", "Audio session was disposed")
                    else result.success(null)
                } catch (error: Throwable) { failure(result, error) }
            }
            return
        }
        if (session.operation == null && idleAllowed) { result.success(null); return }
        if (session.operation !in expected) throw AudioFailure("notActive", "No matching interruptible audio operation")
        session.cleanupLifecycle.begin(session.operation!!)
        session.cleanupFailure = null
        ++session.generation
        session.pending?.error("cancelled", "Audio operation explicitly cancelled")
        session.pending = null
        if (permission?.session === session) {
            permission = null
            permissionLifecycle.cancel()
        }
        session.operation = "cleaning"
        val prior = session.job
        prior?.cancel()
        session.cleanup = scope.launch {
            try {
                cleanupResources(session, prior)
                if (session.terminal) result.error("disposed", "Audio session was disposed")
                else result.success(null)
            } catch (error: Throwable) {
                session.cleanupFailure = error
                failure(result, error)
            }
            finally {
                session.job = null
                session.operation = null
                session.cleanupLifecycle.finish()
            }
        }
    }

    private suspend fun cleanupResources(session: Session, prior: Job?) {
        withContext(NonCancellable) {
            var failure: Throwable? = null
            suspend fun cleanup(block: suspend () -> Unit) {
                try { block() } catch (error: Throwable) { if (failure == null) failure = error }
            }
            cleanup { session.playback?.stop() }
            cleanup { session.recording?.cancel() }
            cleanup { prior?.cancelAndJoin() }
            cleanup { session.transcriber.cancel() }
            session.playback = null
            session.recording = null
            if (failure != null) throw failure!!
        }
    }

    private fun terminate(session: Session, code: String, message: String) {
        if (session.terminal) return
        session.terminal = true
        ++session.generation
        session.pending?.error(code, message)
        session.pending = null
        if (permission?.session === session) {
            permission = null
            permissionLifecycle.cancel()
        }
        val prior = session.job
        val previousCleanup = session.cleanup
        prior?.cancel()
        session.operation = "cleaning"
        session.cleanup = scope.launch {
            try {
                previousCleanup?.join()
                cleanupResources(session, prior)
            } catch (error: Throwable) {
                session.cleanupFailure = error
            } finally {
                session.job = null
                session.operation = null
            }
        }
    }

    private fun disposeSession(session: Session, result: ResultOnce) {
        terminate(session, "disposed", "Audio session disposed")
        scope.launch {
            try {
                session.cleanup?.join()
                val error = session.cleanupFailure
                if (error == null) result.success(null) else failure(result, error)
            }
            catch (error: Throwable) { failure(result, error) }
        }
    }

    private fun terminateAll(code: String, message: String) {
        sessions.values.forEach { terminate(it, code, message) }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        permissionLifecycle.pause()
        application?.unregisterActivityLifecycleCallbacks(this)
        application = null
        terminateAll("detached", "Audio engine detached")
        context = null
        val oldScope = scope
        val cleanups = sessions.values.mapNotNull { it.cleanup }
        oldScope.launch {
            try { cleanups.forEach { it.join() } }
            finally { oldScope.cancel() }
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        permissionLifecycle.resume()
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onDetachedFromActivity() = detachActivity()
    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        permissionLifecycle.pause()
        terminateAll("activityDetached", "Audio Activity detached")
    }
    override fun onActivityPaused(activity: Activity) {
        if (activityBinding?.activity !== activity) return
        permissionLifecycle.pause()
        sessions.values.forEach { pauseSession(it) }
    }
    private fun pauseSession(session: Session) {
        // Permission UI owns no microphone; preserve its request through an ordinary pause.
        if (session.terminal || permission?.session === session || session.operation == null ||
            session.operation == "cleaning" || session.cleanup?.isActive == true) return
        session.cleanupLifecycle.begin(session.operation!!)
        session.cleanupFailure = null
        ++session.generation
        session.pending?.error("activityPaused", "Audio Activity paused")
        session.pending = null
        val prior = session.job
        prior?.cancel()
        session.operation = "cleaning"
        session.cleanup = scope.launch {
            try { cleanupResources(session, prior) }
            catch (error: Throwable) { session.cleanupFailure = error }
            finally {
                session.job = null
                session.operation = null
                session.cleanupLifecycle.finish()
            }
        }
    }
    override fun onActivityDestroyed(activity: Activity) {
        if (activityBinding?.activity === activity) detachActivity()
    }
    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityStarted(activity: Activity) = Unit
    override fun onActivityResumed(activity: Activity) {
        if (activityBinding?.activity !== activity) return
        if (permissionLifecycle.resume()) {
            permission?.let { launchGrantedPermission(it) }
        }
    }
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    private fun bytes(arguments: Map<*, *>): ByteArray {
        val value = arguments["bytes"] as? ByteArray
            ?: throw AudioFailure("invalidAudio", "Expected saved WAV bytes")
        try { PcmWaveAudio.parse(value) }
        catch (error: IllegalArgumentException) { throw AudioFailure("invalidAudio", error.message) }
        return value.copyOf()
    }
    private fun string(arguments: Map<*, *>, name: String) = arguments[name] as? String
        ?: throw AudioFailure("invalidArguments", "Expected $name string")
    private fun failure(result: ResultOnce, error: Throwable) {
        when (error) {
            is AudioFailure -> result.error(error.code, error.message)
            is TimeoutCancellationException -> result.error("timeout", "Saved-audio recognition timed out")
            is CancellationException -> result.error("cancelled", "Audio operation cancelled")
            is SecurityException -> result.error("permissionDenied", error.message)
            else -> result.error("audioFailure", error.message ?: error.javaClass.simpleName)
        }
    }

    private companion object { const val PERMISSION_REQUEST = 24681 }
}

/** Pure foreground/deferred-grant state used by the plugin's permission path. */
internal class AudioPermissionLifecycle {
    var isResumed = false
        private set
    private var pendingGrant = false

    fun resume(): Boolean {
        isResumed = true
        val launch = pendingGrant
        pendingGrant = false
        return launch
    }
    fun pause() { isResumed = false }
    fun grant(): Boolean {
        if (isResumed) return true
        pendingGrant = true
        return false
    }
    fun cancel() { pendingGrant = false }
}

/** Pure operation-origin matching for session-owned cleanup joins. */
internal class AudioCleanupLifecycle {
    private var origin: String? = null
    val hasActive: Boolean get() = origin != null

    fun begin(operation: String) {
        check(origin == null) { "Audio cleanup is already active" }
        origin = operation
    }
    fun canJoin(expected: Set<String>): Boolean {
        val operation = origin ?: return false
        return operation in expected
    }
    fun finish() { origin = null }
}
