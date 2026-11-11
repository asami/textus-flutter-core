package org.textus.flutter.core.authentication

internal class CredentialStoreFailure(val code: String) : Exception(messageFor(code)) {
    override fun toString() = "CredentialStoreFailure($code)"

    companion object {
        const val CLOSED = "credentialStoreClosed"
        const val UNAVAILABLE = "credentialStoreUnavailable"
        const val INVALID = "credentialStoreInvalidArguments"
        fun messageFor(code: String): String = when (code) {
            CLOSED -> "Credential store closed"
            INVALID -> "Invalid credential store arguments"
            else -> "Credential store unavailable"
        }
    }
}

internal class CredentialStoreCall(
    val method: String,
    val handleId: String,
    val profileId: String?,
    val expectedRevision: String?,
    value: ByteArray?
) {
    private val bytes = value?.copyOf()
    val value: ByteArray? get() = bytes?.copyOf()
    override fun toString() = "CredentialStoreCall"
}

internal data class CredentialStoreColumn(
    val id: Int, val name: String, val type: String,
    val notNull: Boolean, val defaultValue: String?, val primaryKey: Int
)

/** Closed ABI and product locators, independent of Android for host specs. */
internal object CredentialStorePolicy {
    const val MAX_VALUE = 65536
    private val profilePattern = Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
    private val revisionPattern = Regex("[0-9a-f]{32}")

    fun profile(value: Any?): String = (value as? String)?.takeIf {
        profilePattern.matches(it)
    } ?: throw CredentialStoreFailure(CredentialStoreFailure.INVALID)

    fun revision(value: Any?): String = (value as? String)?.takeIf {
        revisionPattern.matches(it)
    } ?: throw CredentialStoreFailure(CredentialStoreFailure.INVALID)

    fun value(value: Any?): ByteArray = (value as? ByteArray)?.takeIf {
        it.size in 1..MAX_VALUE
    }?.copyOf() ?: throw CredentialStoreFailure(CredentialStoreFailure.INVALID)

    fun keys(method: String): Set<String>? = when (method) {
        "read", "clear" -> setOf("handleId", "profileId")
        "replace" -> setOf("handleId", "profileId", "expectedRevision", "value")
        "remove" -> setOf("handleId", "profileId", "expectedRevision")
        "close" -> setOf("handleId")
        else -> null
    }

    fun call(method: String, arguments: Any?): CredentialStoreCall {
        val keys = keys(method) ?: throw CredentialStoreFailure(CredentialStoreFailure.INVALID)
        val map = arguments as? Map<*, *>
            ?: throw CredentialStoreFailure(CredentialStoreFailure.INVALID)
        if (map.keys != keys) throw CredentialStoreFailure(CredentialStoreFailure.INVALID)
        val handle = revision(map["handleId"])
        val profile = if (method == "close") null else profile(map["profileId"])
        val revision = when (method) {
            "replace" -> map["expectedRevision"]?.let { revision(it) }
            "remove" -> revision(map["expectedRevision"])
            else -> null
        }
        return CredentialStoreCall(method, handle, profile, revision,
            if (method == "replace") value(map["value"]) else null)
    }

    fun alias(profileId: String): String =
        "org.textus.flutter.core.authentication.v1." +
            profile(profileId).toByteArray(Charsets.UTF_8).joinToString("") {
                (it.toInt() and 255).toString(16).padStart(2, '0')
            }

    fun aad(profileId: String): ByteArray =
        ("org.textus.flutter.core/authentication/v1\u0000" + profile(profileId))
            .toByteArray(Charsets.UTF_8)

    fun schema(version: Int, tables: Set<String>,
        metadata: List<CredentialStoreColumn>, columns: List<CredentialStoreColumn>) {
        val allowed = if (version == 0) setOf("android_metadata")
            else setOf("android_metadata", "credentials")
        val metadataShape = listOf(CredentialStoreColumn(0, "locale", "TEXT", false, null, 0))
        val credentialShape = listOf(
            CredentialStoreColumn(0, "profile", "TEXT", true, null, 1),
            CredentialStoreColumn(1, "sealed", "BLOB", true, null, 0))
        if (version !in 0..1 || !allowed.containsAll(tables) ||
            ("android_metadata" in tables && metadata != metadataShape) ||
            ("android_metadata" !in tables && metadata.isNotEmpty()) ||
            (version == 0 && columns.isNotEmpty()) ||
            (version == 1 && ("credentials" !in tables || columns != credentialShape))) {
            throw CredentialStoreFailure(CredentialStoreFailure.UNAVAILABLE)
        }
    }
}
