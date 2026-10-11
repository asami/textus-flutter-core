package org.textus.flutter.core.submission

import android.accounts.Account
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.util.Log
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.api.Scope
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.tasks.Task
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeout
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Account-specific authorization. SDK tokens live only in a call result. Main
 * dispatcher owns Activity/consent state; IO callbacks own the encrypted store.
 * Every SDK await is bounded/observed and engine/configuration/activity ownership
 * fences late Tasks. Its context-specific request code never routes a retired
 * resolution into a replacement context. Only explicit authorize may launch one
 * foreground consent resolution; close cancels pending resolution idempotently.
 */
internal class GoogleDriveAuthorization(
    private val context: Context,
    private val row: suspend (String) -> Map<String, Any?>,
    private val grant: suspend (String, Map<String, Any?>, Boolean, () -> Boolean) -> Unit,
    private val engineCurrent: () -> Boolean,
    private val requestCode: Int,
) {
    companion object {
        private const val driveScope = "https://www.googleapis.com/auth/drive.file"
    }
    private val consent = SubmissionConsentLifecycle()
    private var activity: Activity? = null
    private var resolution: CompletableDeferred<Intent>? = null

    /** Fixed debug events never retain SDK contents or affect credential cleanup. */
    private fun diagnostic(event: String, value: Int? = null) {
        try {
            if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                Log.d("TextusDriveProof", if (value == null) event else "$event:$value")
            }
        } catch (_: Exception) { }
    }

    fun attach(value: Activity, reattach: Boolean, resumed: Boolean? = null) {
        activity = value
        val isResumed = resumed ?: ((value as? LifecycleOwner)?.lifecycle?.currentState
            ?.isAtLeast(Lifecycle.State.RESUMED) == true)
        consent.attach(isResumed, reattach)
        diagnostic("attach_resumed", if (isResumed) 1 else 0)
        diagnostic("attach_reattach", if (reattach) 1 else 0)
    }
    fun resume(value: Activity) {
        if (activity === value) {
            consent.resume()
            diagnostic("resume")
        }
    }
    fun pause(value: Activity) {
        if (activity === value) {
            val cancel = consent.pause()
            diagnostic("pause_cancel", if (cancel) 1 else 0)
            if (cancel) cancelResolution()
        }
    }
    fun detach(configurationChange: Boolean) {
        activity = null
        val cancel = consent.detach(configurationChange)
        diagnostic("detach_configuration_change", if (configurationChange) 1 else 0)
        diagnostic("detach_cancel", if (cancel) 1 else 0)
        if (cancel) cancelResolution()
    }
    fun close() {
        diagnostic("close")
        activity = null
        consent.cancel()
        cancelResolution()
    }
    private fun cancelResolution() {
        diagnostic("cancel_resolution")
        resolution?.completeExceptionally(SubmissionConfigurationFailure("authorizationCancelled"))
        resolution = null
    }

    fun activityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != requestCode) return false
        if (!engineCurrent()) {
            diagnostic("guard_engine_rejected")
            return false
        }
        val pending = resolution ?: return true
        diagnostic("activity_result_code", resultCode)
        diagnostic("activity_result_data", if (data != null) 1 else 0)
        resolution = null
        if (resultCode == Activity.RESULT_OK && data != null) pending.complete(data)
        else {
            if (resultCode != Activity.RESULT_OK && data != null) {
                try {
                    if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
                        try {
                            Identity.getAuthorizationClient(context).getAuthorizationResultFromIntent(data)
                            diagnostic("cancelled_result_parseable")
                        } catch (failure: ApiException) {
                            diagnostic("cancelled_result_status", failure.statusCode)
                        } catch (_: Exception) {
                            diagnostic("cancelled_result_without_status")
                        }
                    }
                } catch (_: Exception) { }
            }
            pending.completeExceptionally(SubmissionConfigurationFailure("authorizationCancelled"))
        }
        return true
    }

    private fun available(): Boolean = GoogleApiAvailability.getInstance()
        .isGooglePlayServicesAvailable(context) == ConnectionResult.SUCCESS

    private fun guard(current: () -> Boolean) {
        if (!engineCurrent()) {
            diagnostic("guard_engine_rejected")
            throw SubmissionConfigurationFailure("authorizationCancelled")
        }
        if (!current()) {
            diagnostic("guard_owner_rejected")
            throw SubmissionConfigurationFailure("authorizationCancelled")
        }
    }
    private fun request(definition: Map<String, Any?>): AuthorizationRequest =
        AuthorizationRequest.builder()
            .setAccount(Account(SubmissionConnectionPolicy.string(definition["accountId"]), "com.google"))
            .setRequestedScopes(listOf(Scope(driveScope)))
            .build()

    /** Listener consumes late Task completion without retaining the SDK failure. */
    private suspend fun <T> await(task: Task<T>): T = suspendCancellableCoroutine { continuation ->
        task.addOnCompleteListener { finished ->
            if (continuation.isActive) {
                if (finished.isSuccessful) continuation.resume(finished.result)
                else {
                    try {
                        val status = (finished.exception as? ApiException)?.statusCode
                        if (status == null) diagnostic("sdk_failure_without_status")
                        else diagnostic("sdk_failure_status", status)
                    } catch (_: Exception) { }
                    continuation.resumeWithException(SubmissionConfigurationFailure("credentialUnavailable"))
                }
            }
        }
    }

    private fun verified(result: AuthorizationResult): String? {
        if (result.hasResolution() || result.grantedScopes.none { it == driveScope }) return null
        return try { SubmissionConnectionPolicy.bearer(result.accessToken) }
        catch (_: SubmissionConfigurationFailure) { null }
    }

    suspend fun authorize(id: String): String = SubmissionAuthorizationTiming.authorization {
        diagnostic("authorize_begin")
        if (!engineCurrent()) {
            diagnostic("guard_engine_rejected")
            throw SubmissionConfigurationFailure("configurationClosed")
        }
        val owner = consent.begin()
        diagnostic("authorize_owner_acquired")
        val current = { consent.current(owner) }
        try {
            val stored = row(id)
            guard(current)
            val definition = SubmissionConnectionPolicy.definition(stored["connection"], "googleDrive")
            if (!available()) throw SubmissionConfigurationFailure("credentialUnavailable")
            guard(current)
            val client = Identity.getAuthorizationClient(context)
            diagnostic("sdk_request")
            var result = SubmissionAuthorizationTiming.sdk {
                await(client.authorize(request(definition)))
            }
            guard(current)
            val hasResolution = result.hasResolution()
            diagnostic("sdk_result_resolution", if (hasResolution) 1 else 0)
            if (hasResolution) {
                val host = activity ?: throw SubmissionConfigurationFailure("foregroundRequired")
                consent.launch(owner)
                val pending = CompletableDeferred<Intent>()
                resolution = pending
                try {
                    val sender = result.pendingIntent?.intentSender
                        ?: throw SubmissionConfigurationFailure("credentialUnavailable")
                    diagnostic("resolution_launch")
                    host.startIntentSenderForResult(sender, requestCode, null, 0, 0, 0)
                    val intent = SubmissionAuthorizationTiming.foregroundConsent { pending.await() }
                    diagnostic("resolution_returned")
                    guard(current)
                    result = client.getAuthorizationResultFromIntent(intent)
                } finally {
                    if (resolution === pending) resolution = null
                    if (!pending.isCompleted) pending.cancel()
                }
            }
            guard(current)
            if (verified(result) == null) {
                guard(current)
                diagnostic("grant_begin")
                grant(id, definition, false, current)
                diagnostic("grant_complete")
                throw SubmissionConfigurationFailure("authorizationRequired")
            }
            guard(current)
            diagnostic("grant_begin")
            grant(id, definition, true, current)
            diagnostic("grant_complete")
            guard(current)
            "available"
        } finally {
            diagnostic("authorize_finish_begin")
            val cancel = consent.finish(owner)
            diagnostic("authorize_finish_result", if (cancel) 1 else 0)
            if (cancel) cancelResolution()
        }
    }

    /** Silent exact-account retrieval has no Activity access or UI resolution. */
    suspend fun bearerToken(id: String): String? = withTimeout(20000L) {
        guard { true }
        val stored = row(id)
        guard { true }
        val definition = SubmissionConnectionPolicy.definition(stored["connection"])
        if (definition["type"] == "http") return@withTimeout SubmissionConnectionPolicy.bearer(stored["httpBearerToken"])
        if (!available()) throw SubmissionConfigurationFailure("credentialUnavailable")
        if (stored["driveGranted"] != true) return@withTimeout null
        guard { true }
        diagnostic("sdk_request")
        val result = await(Identity.getAuthorizationClient(context).authorize(request(definition)))
        guard { true }
        val token = verified(result)
        if (token == null) {
            guard { true }
            diagnostic("grant_begin")
            grant(id, definition, false) { true }
            diagnostic("grant_complete")
            guard { true }
        }
        token
    }

    suspend fun state(id: String): String {
        guard { true }
        val stored = row(id)
        guard { true }
        val definition = SubmissionConnectionPolicy.definition(stored["connection"])
        if (definition["type"] == "http") {
            return if (definition["requiresBearerToken"] == false || stored["httpBearerToken"] != null)
                "available" else "authorizationRequired"
        }
        if (!available()) return "unavailable"
        return try {
            if (bearerToken(id) == null) "authorizationRequired" else "available"
        } catch (failure: SubmissionConfigurationFailure) {
            if (failure.code == "credentialUnavailable") "unavailable" else throw failure
        }
    }
}
