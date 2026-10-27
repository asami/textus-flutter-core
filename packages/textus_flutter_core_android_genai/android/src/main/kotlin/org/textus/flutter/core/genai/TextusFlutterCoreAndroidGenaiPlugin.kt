package org.textus.flutter.core.genai

import android.app.Activity
import android.app.Application
import android.os.Bundle
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Engine-local registration; only its attached resumed Activity admits work. */
class TextusFlutterCoreAndroidGenaiPlugin : FlutterPlugin, ActivityAware,
    Application.ActivityLifecycleCallbacks, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var application: Application? = null
    private var activity: Activity? = null
    private var session: GeminiNanoSession? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        session = GeminiNanoSession(GeminiNanoRequestRunner(GeminiNanoModelFactory { AicoreGeminiNanoModel() }))
        channel = MethodChannel(binding.binaryMessenger, "org.textus.flutter.core/genai.v1").also {
            it.setMethodCallHandler(this)
        }
        application = (binding.applicationContext as Application).also {
            it.registerActivityLifecycleCallbacks(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method !in setOf("probe", "prepare", "recognize")) {
            result.notImplemented()
            return
        }
        val current = session
        if (current == null) {
            result.error("engineDetached", "Nano engine is detached", null)
            return
        }
        current.submit(call.method, call.arguments) { outcome ->
            when (outcome) {
                is GeminiNanoOutcome.Success -> result.success(outcome.value)
                is GeminiNanoOutcome.Error -> result.error(outcome.code, outcome.message, outcome.details)
            }
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        // An already resumed attach may have missed the resume callback.
        session?.setForeground(binding.activity.hasWindowFocus())
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() = detachActivity()
    override fun onDetachedFromActivity() = detachActivity()

    private fun detachActivity() {
        session?.detachActivity()
        activity = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        detachActivity()
        session?.detachEngine()
        session = null
        channel?.setMethodCallHandler(null)
        channel = null
        application?.unregisterActivityLifecycleCallbacks(this)
        application = null
    }

    override fun onActivityResumed(activity: Activity) {
        if (activity === this.activity) session?.setForeground(true)
    }

    override fun onActivityPaused(activity: Activity) {
        if (activity === this.activity) session?.setForeground(false)
    }

    override fun onActivityDestroyed(activity: Activity) {
        if (activity === this.activity) detachActivity()
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityStarted(activity: Activity) = Unit
    override fun onActivityStopped(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
}
