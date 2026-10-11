package org.textus.flutter.core.submission

import java.net.URI

/** Closed safe failures. No SDK cause, input, account or credential is retained. */
internal class SubmissionConfigurationFailure(val code: String) : Exception(messageFor(code)) {
    companion object {
        fun messageFor(code: String): String = when (code) {
            "configurationInvalid" -> "Submission configuration is invalid."
            "connectionConflict" -> "Submission connection identity conflicts."
            "connectionMissing" -> "Submission connection is not configured."
            "configurationClosed" -> "Submission configuration is closed."
            "authorizationRequired" -> "Submission authorization is required."
            "authorizationCancelled" -> "Submission authorization was cancelled."
            "authorizationBusy" -> "Submission authorization is already in progress."
            "foregroundRequired" -> "Submission authorization requires a foreground activity."
            "credentialUnavailable" -> "Submission credentials are unavailable."
            else -> "Submission configuration is unavailable."
        }
    }
}

/** Given observed metadata fields, when captured as values, then each column is immutable. */
internal data class SubmissionMetadataColumn(
    val index: Int,
    val name: String,
    val type: String,
    val notNull: Boolean,
    val defaultValue: String?,
    val primaryKey: Int
)

/** Pure closed-schema and immutable-identity policy; no Android or persistence IO. */
internal object SubmissionConnectionPolicy {
    private fun invalid(): Nothing = throw SubmissionConfigurationFailure("configurationInvalid")

    fun validateInitialSchema(tableNames: List<String>, metadataColumns: List<SubmissionMetadataColumn>) {
        // Given the exact Android-owned locale column signature before Core initialization.
        val androidMetadataColumns = listOf(SubmissionMetadataColumn(0, "locale", "TEXT", false, null, 0))
        // When the observed tables and columns are compared without normalization or mutation.
        val accepted = (tableNames.isEmpty() && metadataColumns.isEmpty()) ||
            (tableNames == listOf("android_metadata") && metadataColumns == androidMetadataColumns)
        // Then only empty or canonical platform-only schemas permit initialization.
        if (!accepted) throw SubmissionConfigurationFailure("configurationUnavailable")
    }

    fun objectValue(value: Any?): Map<String, Any?> {
        if (value !is Map<*, *> || value.keys.any { it !is String }) invalid()
        return value.entries.associate { (key, item) -> key as String to item }
    }

    fun exact(value: Any?, keys: Set<String>): Map<String, Any?> {
        val map = objectValue(value)
        if (map.keys != keys) invalid()
        return map
    }

    fun string(value: Any?): String = value as? String ?: invalid()
    fun boolean(value: Any?): Boolean = value as? Boolean ?: invalid()
    fun integer(value: Any?): Long = when (value) {
        is Int -> value.toLong()
        is Long -> value
        else -> invalid()
    }

    fun safeId(value: Any?): String {
        val text = string(value)
        if (!Regex("^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$").matches(text)) invalid()
        return text
    }

    fun nullableId(value: Any?): String? = if (value == null) null else safeId(value)

    fun bearer(value: Any?): String? {
        if (value == null) return null
        val text = string(value)
        if (text.length > 8192 || !Regex("^[A-Za-z0-9._~+/-]+=*$").matches(text)) invalid()
        return text
    }

    fun definition(value: Any?, requiredType: String? = null): Map<String, Any?> {
        val map = objectValue(value)
        val type = string(map["type"])
        if (requiredType != null && type != requiredType) invalid()
        val keys = when (type) {
            "googleDrive" -> setOf("version", "type", "id", "accountId", "folderId")
            "http" -> setOf("version", "type", "id", "endpoint", "requiresBearerToken")
            else -> invalid()
        }
        exact(map, keys)
        if (integer(map["version"]) != 1L) invalid()
        safeId(map["id"])
        if (type == "googleDrive") {
            val account = string(map["accountId"])
            if (account.toByteArray(Charsets.UTF_8).size > 256 ||
                account.count { it == '@' } != 1 || account.startsWith('@') ||
                account.endsWith('@') || account.any { it.isWhitespace() || it.code < 32 || it.code == 127 }) invalid()
            if (!Regex("^[A-Za-z0-9_-]{1,256}$").matches(string(map["folderId"]))) invalid()
        } else {
            boolean(map["requiresBearerToken"])
            val text = string(map["endpoint"])
            val uri = try { URI(text) } catch (_: Exception) { invalid() }
            if (text.toByteArray(Charsets.UTF_8).size > 65536 || uri.scheme != "https" ||
                uri.host.isNullOrEmpty() || uri.rawPath.isNullOrEmpty() ||
                !uri.rawPath.startsWith('/') || uri.rawUserInfo != null ||
                uri.rawQuery != null || uri.rawFragment != null) invalid()
        }
        return map + ("version" to 1)
    }

    /** Equal identity is idempotent; no kind/account/folder/endpoint/auth retarget. */
    fun insert(existing: Map<String, Any?>?, proposed: Map<String, Any?>): Map<String, Any?> {
        val validated = definition(proposed)
        if (existing != null && definition(existing) != validated) {
            throw SubmissionConfigurationFailure("connectionConflict")
        }
        return existing ?: validated
    }

    fun row(value: Any?): Map<String, Any?> {
        val map = exact(value, setOf("version", "connection", "httpBearerToken", "driveGranted"))
        if (integer(map["version"]) != 1L) invalid()
        val connection = definition(map["connection"])
        val token = bearer(map["httpBearerToken"])
        val granted = boolean(map["driveGranted"])
        if (connection["type"] == "googleDrive" && token != null) invalid()
        if (connection["type"] == "http" && (granted ||
                (connection["requiresBearerToken"] == false && token != null))) invalid()
        return map
    }

    fun selection(value: Any?): Map<String, Any?> {
        val supplied = objectValue(value)
        val version = integer(supplied["version"])
        if (version != 1L && version != 2L) invalid()
        val keys = setOf("version", "storageConnectionId", "transportConnectionId") +
            if (version == 2L) setOf("referenceAccessBindings") else emptySet()
        val map = exact(supplied, keys)
        nullableId(map["storageConnectionId"])
        nullableId(map["transportConnectionId"])
        if (version == 2L) bindings(map["referenceAccessBindings"])
        return map
    }

    /** Deeply detached exact ids; empty is explicit revocation, absent unknown. */
    fun bindings(value: Any?): Map<String, List<String>> {
        val map = objectValue(value)
        if (map.size > 128) invalid()
        var associations = 0
        return map.entries.associate { (key, value) ->
            val id = safeId(key)
            val list = value as? List<*> ?: invalid()
            val ids = list.map { safeId(it) }
            associations += ids.size
            if (associations > 128 || ids.toSet().size != ids.size) invalid()
            id to ids
        }
    }

    /** Exact old literal selection grants no access and is never rewritten here. */
    fun referenceAccessBindings(value: Map<String, Any?>): Map<String, List<String>> {
        val validated = selection(value)
        return if (integer(validated["version"]) == 1L) emptyMap()
            else bindings(validated["referenceAccessBindings"])
    }

    fun select(definitions: List<Map<String, Any?>>, storage: String?, transport: String?) {
        nullableId(storage)
        nullableId(transport)
        if (definitions.size > 128 || definitions.map { safeId(definition(it)["id"]) }.toSet().size != definitions.size) invalid()
        if ((storage != null && definitions.none { it["id"] == storage && it["type"] == "googleDrive" }) ||
            (transport != null && definitions.none { it["id"] == transport && it["type"] == "http" })) {
            throw SubmissionConfigurationFailure("connectionMissing")
        }
    }

    /** Every transaction validates selection and registered binding kinds. */
    fun validateSelection(definitions: List<Map<String, Any?>>, value: Map<String, Any?>) {
        val selected = selection(value)
        select(definitions, nullableId(selected["storageConnectionId"]), nullableId(selected["transportConnectionId"]))
        for ((transport, storage) in referenceAccessBindings(selected)) {
            if (definitions.none { it["id"] == transport && it["type"] == "http" } ||
                storage.any { id -> definitions.none { it["id"] == id && it["type"] == "googleDrive" } }) {
                throw SubmissionConfigurationFailure("connectionMissing")
            }
        }
    }

    /** Canonical v2 selection changes preserve every existing explicit binding. */
    fun withSelection(definitions: List<Map<String, Any?>>, current: Map<String, Any?>,
        storage: String?, transport: String?): Map<String, Any?> {
        validateSelection(definitions, current)
        val changed = mapOf("version" to 2, "storageConnectionId" to storage,
            "transportConnectionId" to transport, "referenceAccessBindings" to referenceAccessBindings(current))
        validateSelection(definitions, changed)
        return changed
    }

    /** Canonical v2 one-key replace; validates the entire map before a write. */
    fun setReferenceAccess(definitions: List<Map<String, Any?>>, current: Map<String, Any?>,
        transportConnectionId: String, storageConnectionIds: Any?): Map<String, Any?> {
        validateSelection(definitions, current)
        val transport = safeId(transportConnectionId)
        val access = bindings(mapOf(transport to storageConnectionIds))[transport]!!
        val changed = mapOf("version" to 2,
            "storageConnectionId" to current["storageConnectionId"],
            "transportConnectionId" to current["transportConnectionId"],
            "referenceAccessBindings" to (referenceAccessBindings(current) + (transport to access)))
        validateSelection(definitions, changed)
        return changed
    }
}
