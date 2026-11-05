package org.textus.flutter.core.authentication

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/** Engine-owned serial IO. Registration does not open a database or KeyStore. */
class TextusFlutterCoreNativeAuthenticationPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private class Engine(val store: AndroidAuthenticationCredentialStore) {
        val lifetime = CredentialStoreLifetime()
        val io = Executors.newSingleThreadExecutor()
    }
    private val main = Handler(Looper.getMainLooper())
    private var engine: Engine? = null
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        engine = Engine(AndroidAuthenticationCredentialStore(binding.applicationContext))
        channel = MethodChannel(binding.binaryMessenger, "org.textus.flutter.core/authentication_credentials")
        channel!!.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (CredentialStorePolicy.keys(call.method) == null) { result.notImplemented(); return }
        val captured = engine
        try {
            if (captured == null || !captured.lifetime.isLive()) throw CredentialStoreFailure(CredentialStoreFailure.CLOSED)
            val request = CredentialStorePolicy.call(call.method, call.arguments)
            if (request.method == "close") {
                // Retirement happens on receipt, before the serial drain barrier.
                captured.lifetime.retire(request.handleId)
                captured.io.execute {
                    main.post { if (captured.lifetime.isLive()) result.success(null) }
                }
                return
            }
            val operation = captured.lifetime.accept(request.handleId)
            captured.io.execute {
                var value: Any? = null
                var failure: String? = null
                try {
                    if (!captured.lifetime.current(operation)) throw CredentialStoreFailure(CredentialStoreFailure.CLOSED)
                    value = captured.store.execute(request) { captured.lifetime.issue(operation) }
                } catch (error: CredentialStoreFailure) {
                    failure = error.code
                } catch (_: Exception) {
                    failure = CredentialStoreFailure.UNAVAILABLE
                }
                val response = value
                val errorCode = failure
                main.post {
                    if (captured.lifetime.complete(operation)) {
                        val code = if (!captured.lifetime.current(operation)) CredentialStoreFailure.CLOSED else errorCode
                        if (code == null) result.success(response)
                        else result.error(code, CredentialStoreFailure.messageFor(code), null)
                    }
                }
            }
        } catch (failure: CredentialStoreFailure) {
            result.error(failure.code, CredentialStoreFailure.messageFor(failure.code), null)
        } catch (_: RejectedExecutionException) {
            result.error(CredentialStoreFailure.CLOSED, CredentialStoreFailure.messageFor(CredentialStoreFailure.CLOSED), null)
        } catch (_: Exception) {
            result.error(CredentialStoreFailure.UNAVAILABLE, CredentialStoreFailure.messageFor(CredentialStoreFailure.UNAVAILABLE), null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val captured = engine
        captured?.lifetime?.detach()
        engine = null
        channel?.setMethodCallHandler(null)
        channel = null
        // shutdown drains queued tasks without cancellation or blocking main.
        // Each task releases its captured DB/transaction in finally; no persistent
        // resource survives a task and late main deliveries suppress themselves.
        captured?.io?.shutdown()
    }
}
