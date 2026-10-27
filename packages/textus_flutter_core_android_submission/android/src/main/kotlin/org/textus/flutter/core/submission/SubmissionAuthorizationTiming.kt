package org.textus.flutter.core.submission

import kotlinx.coroutines.withTimeout

/** Fixed bounds for SDK waiting, explicit human consent and the complete foreground call. */
internal object SubmissionAuthorizationTiming {
    internal const val sdkMillis = 20000L
    internal const val foregroundConsentMillis = 120000L
    internal const val authorizationMillis = 160000L

    suspend fun <T> sdk(operation: suspend () -> T): T =
        withTimeout(sdkMillis) { operation() }

    suspend fun <T> foregroundConsent(operation: suspend () -> T): T =
        withTimeout(foregroundConsentMillis) { operation() }

    suspend fun <T> authorization(operation: suspend () -> T): T =
        withTimeout(authorizationMillis) { operation() }

    internal suspend fun <T> entry(method: String, operation: suspend () -> T): T =
        when (method) {
            "authorizeDrive" -> authorization(operation)
            "authorizationState", "bearerToken" -> sdk(operation)
            else -> throw SubmissionConfigurationFailure("configurationInvalid")
        }
}
