package org.textus.flutter.core.submission

import org.junit.Assert.*
import org.junit.Test

/** Pure NB5 evidence. These scenarios do not open Android SQLite or a Keystore. */
class SubmissionConnectionPolicyTest {
    private fun drive(id: String = "drive", account: String = "owner@example.test", folder: String = "Folder_1"): Map<String, Any?> {
        // Given an explicit safe account/folder identity.
        val definition = mapOf("version" to 1, "type" to "googleDrive", "id" to id,
            "accountId" to account, "folderId" to folder)
        // When the test supplies the complete accepted connection schema.
        val supplied = definition.toMap()
        // Then policy assertions can exercise actual immutable values.
        return supplied
    }
    private fun http(id: String = "server", endpoint: String = "https://example.test:8443/v1/submit%2Fmaterial", auth: Boolean = true): Map<String, Any?> {
        // Given an exact encoded HTTPS endpoint and explicit authentication policy.
        val definition = mapOf("version" to 1, "type" to "http", "id" to id,
            "endpoint" to endpoint, "requiresBearerToken" to auth)
        // When the complete closed schema is supplied to the pure policy.
        val supplied = definition.toMap()
        // Then later assertions observe acceptance/conflict rather than source shape.
        return supplied
    }
    private fun failure(code: String = "configurationInvalid", action: () -> Unit) {
        // Given a rejected public-policy operation expected to expose only safe fields.
        val expected = code
        // When the actual policy operation fails.
        val failure = assertThrows(SubmissionConfigurationFailure::class.java) { action() }
        // Then no account, bearer marker or SDK cause is reflected.
        assertEquals(expected, failure.code)
        assertFalse(failure.toString().contains("PRIVATE_MARKER"))
        assertFalse(failure.message!!.contains("owner@example.test"))
        assertNull(failure.cause)
    }

    @Test fun acceptsExactTargetsAndIdempotentIdentity() {
        // Given one accepted exact account/folder and one encoded endpoint definition.
        val drive = drive()
        val http = http()
        // When values are validated and equal identities are inserted again.
        val acceptedDrive = SubmissionConnectionPolicy.insert(null, drive)
        val acceptedHttp = SubmissionConnectionPolicy.insert(null, http)
        // Then no rewriting occurs and the exact endpoint/account remain stable.
        assertEquals(drive, SubmissionConnectionPolicy.insert(acceptedDrive, drive.toMap()))
        assertEquals(http, SubmissionConnectionPolicy.insert(acceptedHttp, http.toMap()))
        assertEquals("owner@example.test", acceptedDrive["accountId"])
        assertEquals("https://example.test:8443/v1/submit%2Fmaterial", acceptedHttp["endpoint"])
    }

    @Test fun rejectsRetargetAcrossEveryIdentityComponent() {
        // Given definitions already referenced by immutable queue intent.
        val acceptedDrive = drive()
        val acceptedHttp = http()
        // When another account/folder/kind/endpoint/auth requirement reuses an id.
        for (proposed in listOf(drive(account = "other@example.test"), drive(folder = "OtherFolder"), http(id = "drive"))) {
            failure("connectionConflict") { SubmissionConnectionPolicy.insert(acceptedDrive, proposed) }
        }
        for (proposed in listOf(http(endpoint = "https://other.example.test/submit"), http(auth = false), drive(id = "server"))) {
            failure("connectionConflict") { SubmissionConnectionPolicy.insert(acceptedHttp, proposed) }
        }
        // Then the previously accepted maps are unchanged after all rejected writes.
        assertEquals(drive(), acceptedDrive)
        assertEquals(http(), acceptedHttp)
    }

    @Test fun rejectsUnsafeIdsAccountsFoldersEndpointsAndScalarSchemas() {
        // Given unsafe identity tokens, account emails and Drive file identities.
        val ids = listOf("", "../private", "-leading", "a".repeat(129), "PRIVATE_MARKER\n")
        // When typed policy constructors inspect each invalid input.
        for (id in ids) failure { SubmissionConnectionPolicy.definition(drive(id = id)) }
        for (account in listOf("opaque", "@example.test", "owner@", "owner@@example.test", "owner @example.test", "owner\u0001@example.test", "a".repeat(257) + "@x")) {
            failure { SubmissionConnectionPolicy.definition(drive(account = account)) }
        }
        for (folder in listOf("", "../private", "a".repeat(257), "Folder space")) {
            failure { SubmissionConnectionPolicy.definition(drive(folder = folder)) }
        }
        // Then HTTPS targets reject credentials, missing host/path, query and fragments.
        for (endpoint in listOf("http://example.test/submit", "/submit", "https://example.test", "https://user:PRIVATE_MARKER@example.test/submit", "https://example.test/submit?x=1", "https://example.test/submit#fragment")) {
            failure { SubmissionConnectionPolicy.definition(http(endpoint = endpoint)) }
        }
        // When closed-schema versions/types/keys are malformed.
        for (value in listOf(drive() + ("version" to 2), drive() + ("version" to 1.0),
                drive() + ("token" to "PRIVATE_MARKER"), drive() - "folderId",
                http() + ("requiresBearerToken" to "true"), drive() + ("type" to "unknown"))) {
            failure { SubmissionConnectionPolicy.definition(value) }
        }
        // Then a valid safe definition is still accepted after rejected input.
        assertEquals(drive(), SubmissionConnectionPolicy.definition(drive(), "googleDrive"))
    }

    @Test fun validatesSecretRotationRemovalAndAnonymousOrDriveRejection() {
        // Given complete secure-row values with separately held HTTP secret/grant fields.
        val initial = mapOf("version" to 1, "connection" to http(), "httpBearerToken" to null, "driveGranted" to false)
        val marker = "PRIVATE_MARKER_token"
        // When only the secret changes or is removed under the same definition.
        val rotated = SubmissionConnectionPolicy.row(initial + ("httpBearerToken" to marker))
        val cleared = SubmissionConnectionPolicy.row(rotated + ("httpBearerToken" to null))
        // Then definition is unchanged, null clears it, and no error exposes the marker.
        assertEquals(initial["connection"], rotated["connection"])
        assertNull(cleared["httpBearerToken"])
        failure { SubmissionConnectionPolicy.row(initial + ("httpBearerToken" to "PRIVATE_MARKER\r\n")) }
        failure { SubmissionConnectionPolicy.row(initial + ("httpBearerToken" to "a".repeat(8193))) }
        failure { SubmissionConnectionPolicy.row(initial + ("connection" to http(auth = false)) + ("httpBearerToken" to marker)) }
        failure { SubmissionConnectionPolicy.row(initial + ("connection" to drive()) + ("httpBearerToken" to marker)) }
        failure { SubmissionConnectionPolicy.row(initial + ("driveGranted" to true)) }
        failure { SubmissionConnectionPolicy.row(initial + ("driveGranted" to 1)) }
        assertEquals(marker, SubmissionConnectionPolicy.bearer(marker))
    }

    @Test fun selectionRequiresExactKindsUniqueIdsAndBoundedCounts() {
        // Given all previously registered immutable targets, including old choices.
        val definitions = listOf(drive(), http(), drive(id = "laterDrive", account = "later@example.test"))
        // When selection changes only for future intent and null clears it.
        SubmissionConnectionPolicy.select(definitions, "laterDrive", "server")
        SubmissionConnectionPolicy.select(definitions, null, null)
        // Then definitions are retained and wrong/missing kinds cannot be selected.
        assertEquals(3, definitions.size)
        failure("connectionMissing") { SubmissionConnectionPolicy.select(definitions, "server", "server") }
        failure("connectionMissing") { SubmissionConnectionPolicy.select(definitions, "absent", null) }
        failure { SubmissionConnectionPolicy.select(listOf(drive(), http(id = "drive")), null, null) }
        failure { SubmissionConnectionPolicy.select((0..128).map { http(id = "server_$it") }, null, null) }
        failure { SubmissionConnectionPolicy.selection(mapOf("version" to 1, "storageConnectionId" to 9, "transportConnectionId" to null)) }
        assertEquals(mapOf("version" to 1, "storageConnectionId" to null, "transportConnectionId" to null),
            SubmissionConnectionPolicy.selection(mapOf("version" to 1, "storageConnectionId" to null, "transportConnectionId" to null)))
    }

    @Test fun RA6ExactLegacyAndCurrentSelectionPreserveUnrelatedBindings() {
        // Given an independently literal exact v1 selection, including old choices.
        val legacy = mapOf("version" to 1, "storageConnectionId" to "drive", "transportConnectionId" to "server")
        val definitions = listOf(drive(), drive(id = "laterDrive"), http(), http(id = "laterServer"))
        // When the actual pure codec reads old data and explicitly provisions two maps.
        val read = SubmissionConnectionPolicy.selection(legacy)
        val first = SubmissionConnectionPolicy.setReferenceAccess(definitions, read, "server", listOf("drive"))
        val both = SubmissionConnectionPolicy.setReferenceAccess(definitions, first, "laterServer", listOf("laterDrive"))
        val changedSelection = SubmissionConnectionPolicy.withSelection(definitions, both, "laterDrive", "laterServer")
        val revoked = SubmissionConnectionPolicy.setReferenceAccess(definitions, changedSelection, "server", emptyList<String>())
        val equal = SubmissionConnectionPolicy.setReferenceAccess(definitions, revoked, "server", emptyList<String>())
        // Then old reads neither rewrite nor grant; v2 writes preserve unrelated facts.
        assertEquals(legacy, read)
        assertTrue(SubmissionConnectionPolicy.referenceAccessBindings(read).isEmpty())
        assertEquals(2, first["version"])
        assertEquals("drive", first["storageConnectionId"])
        assertEquals("server", first["transportConnectionId"])
        assertEquals(mapOf("server" to listOf("drive"), "laterServer" to listOf("laterDrive")),
            SubmissionConnectionPolicy.referenceAccessBindings(changedSelection))
        assertEquals("laterDrive", revoked["storageConnectionId"])
        assertEquals("laterServer", revoked["transportConnectionId"])
        assertEquals(mapOf("server" to emptyList<String>(), "laterServer" to listOf("laterDrive")),
            SubmissionConnectionPolicy.referenceAccessBindings(revoked))
        assertEquals(revoked, equal)
        assertEquals(both, SubmissionConnectionPolicy.selection(both))
        assertEquals(4, definitions.size)
    }

    @Test fun RA6MalformedSelectionAndBindingsFailSafelyWithoutChangingInputs() {
        // Given exact current selection values and explicit registered kinds.
        val definitions = listOf(drive(), http())
        val current = mapOf("version" to 2, "storageConnectionId" to "drive",
            "transportConnectionId" to "server", "referenceAccessBindings" to mapOf("server" to listOf("drive")))
        val legacy = mapOf("version" to 1, "storageConnectionId" to null, "transportConnectionId" to null)
        // When closed keys, versions, scalars, ids, duplicates or list bounds corrupt the row.
        for (value in listOf(current - "referenceAccessBindings", current + ("extra" to true),
                current + ("version" to 3), current + ("version" to 2.0),
                current + ("version" to "2"), current + ("storageConnectionId" to false),
                legacy + ("referenceAccessBindings" to emptyMap<String, Any?>()))) {
            // Then the actual pure decoder rejects without retaining private details.
            failure { SubmissionConnectionPolicy.selection(value) }
        }
        for (bindings in listOf(null, listOf("server"), mapOf("server" to "drive"),
                mapOf("server" to listOf(9)), mapOf("server" to listOf("drive", "drive")),
                mapOf("../PRIVATE_MARKER" to emptyList<String>()), mapOf("server" to listOf("../PRIVATE_MARKER")),
                (0..128).associate { "server_$it" to emptyList<String>() })) {
            // Given a malformed map inside an otherwise exact current selection.
            // When its bindings are decoded by actual policy.
            failure { SubmissionConnectionPolicy.selection(current + ("referenceAccessBindings" to bindings)) }
            // Then no empty or permissive fallback is returned.
        }
        for ((transport, storage) in listOf("missing" to emptyList<String>(), "drive" to emptyList(),
                "server" to listOf("missing"), "server" to listOf("server"))) {
            // Given dangling or wrong-kind ids can be syntactically safe.
            // When whole-map validation is attempted before any persisted write.
            failure("connectionMissing") { SubmissionConnectionPolicy.setReferenceAccess(definitions, current, transport, storage) }
            // Then exact registered membership is required independently of syntax.
        }
        // Given 65 Drive and two HTTP definitions fit the combined 128 limit.
        val drives = (0..64).map { drive(id = "drive_$it") }
        val servers = listOf(http(id = "server_0"), http(id = "server_1"))
        val access = drives.map { it["id"] as String }
        val once = SubmissionConnectionPolicy.setReferenceAccess(drives + servers, legacy, "server_0", access)
        // When a second valid ordered list raises total associations to 130.
        failure { SubmissionConnectionPolicy.setReferenceAccess(drives + servers, once, "server_1", access) }
        // Then rejection preserves the accepted one-map value and original inputs.
        assertEquals(mapOf("server_0" to access), SubmissionConnectionPolicy.referenceAccessBindings(once))
        assertEquals(mapOf("server" to listOf("drive")), SubmissionConnectionPolicy.referenceAccessBindings(current))
        assertEquals(1, legacy["version"])
    }

    @Test fun initialSchemaAcceptsEmptyAndAndroidMetadataOnly() {
        // Given either no application tables or Android's exact nullable locale column.
        val canonical = SubmissionMetadataColumn(0, "locale", "TEXT", false, null, 0)
        val schemas = listOf(
            mutableListOf<String>() to mutableListOf<SubmissionMetadataColumn>(),
            mutableListOf("android_metadata") to mutableListOf(canonical)
        )
        for ((tables, columns) in schemas) {
            val originalTables = tables.toList()
            val originalColumns = columns.toList()
            // When the actual initial-schema policy validates each observed schema.
            SubmissionConnectionPolicy.validateInitialSchema(tables, columns)
            // Then initialization is permitted without modifying supplied observations.
            assertEquals(originalTables, tables)
            assertEquals(originalColumns, columns)
        }
    }

    @Test fun initialSchemaRejectsUnknownTablesAndInconsistentMetadata() {
        // Given unknown/Core tables, mixed or duplicate metadata, case changes or orphan columns.
        val canonical = SubmissionMetadataColumn(0, "locale", "TEXT", false, null, 0)
        val schemas = listOf(
            listOf("PRIVATE_MARKER_unknown") to emptyList<SubmissionMetadataColumn>(),
            listOf("connections") to emptyList(),
            listOf("selection") to emptyList(),
            listOf("connections", "selection") to emptyList(),
            listOf("android_metadata", "PRIVATE_MARKER_unknown") to listOf(canonical),
            listOf("android_metadata", "android_metadata") to listOf(canonical),
            listOf("Android_metadata") to listOf(canonical),
            emptyList<String>() to listOf(canonical)
        )
        for ((suppliedTables, suppliedColumns) in schemas) {
            val tables = suppliedTables.toMutableList()
            val columns = suppliedColumns.toMutableList()
            val originalTables = tables.toList()
            val originalColumns = columns.toList()
            // When the actual policy attempts to admit an inconsistent initial schema.
            failure("configurationUnavailable") {
                SubmissionConnectionPolicy.validateInitialSchema(tables, columns)
            }
            // Then only the fixed safe failure escapes and both inputs remain unchanged.
            assertEquals(originalTables, tables)
            assertEquals(originalColumns, columns)
        }
    }

    @Test fun initialSchemaRejectsMalformedAndroidMetadataColumns() {
        // Given the exact table name with missing, extra or altered column-signature fields.
        val canonical = SubmissionMetadataColumn(0, "locale", "TEXT", false, null, 0)
        val signatures = listOf(
            emptyList(),
            listOf(canonical, canonical.copy(index = 1, name = "PRIVATE_MARKER_extra")),
            listOf(canonical, canonical),
            listOf(canonical.copy(name = "PRIVATE_MARKER_renamed")),
            listOf(canonical.copy(type = "BLOB")),
            listOf(canonical.copy(type = "text")),
            listOf(canonical.copy(type = "")),
            listOf(canonical.copy(index = 1)),
            listOf(canonical.copy(notNull = true)),
            listOf(canonical.copy(defaultValue = "'PRIVATE_MARKER'")),
            listOf(canonical.copy(defaultValue = "NULL")),
            listOf(canonical.copy(defaultValue = "")),
            listOf(canonical.copy(primaryKey = 1))
        )
        for (signature in signatures) {
            val tables = mutableListOf("android_metadata")
            val columns = signature.toMutableList()
            val originalTables = tables.toList()
            val originalColumns = columns.toList()
            // When the actual policy inspects a malformed metadata column signature.
            failure("configurationUnavailable") {
                SubmissionConnectionPolicy.validateInitialSchema(tables, columns)
            }
            // Then malformed metadata is rejected safely without rewriting either input.
            assertEquals(originalTables, tables)
            assertEquals(originalColumns, columns)
        }
    }
}
