package org.textus.flutter.core.authentication

import org.junit.Assert.*
import org.junit.Test

class CredentialStorePolicyTest {
    private val handle = "00112233445566778899aabbccddeeff"
    private fun invalid(action: () -> Unit) {
        try { action(); fail("Expected closed ABI rejection") }
        catch (error: CredentialStoreFailure) {
            assertEquals(CredentialStoreFailure.INVALID, error.code)
            assertFalse(error.toString().contains("PRIVATE"))
        }
    }

    @Test fun exactMapsAndValuesRejectMissingExtraAndWrongTypedFields() {
        // Given a complete create request with an explicitly null comparison.
        val bytes = byteArrayOf(1, 2)
        val valid = mapOf("handleId" to handle, "profileId" to "Profile", "expectedRevision" to null, "value" to bytes)
        val call = CredentialStorePolicy.call("replace", valid)
        // When caller/returned byte arrays change and malformed requests arrive.
        bytes[0] = 9
        call.value!![1] = 9
        assertArrayEquals(byteArrayOf(1, 2), call.value)
        for (field in valid.keys) invalid { CredentialStorePolicy.call("replace", valid - field) }
        invalid { CredentialStorePolicy.call("replace", valid + ("extra" to true)) }
        invalid { CredentialStorePolicy.call("replace", valid + ("value" to listOf(1))) }
        invalid { CredentialStorePolicy.call("replace", valid + ("value" to ByteArray(0))) }
        invalid { CredentialStorePolicy.call("replace", valid + ("value" to ByteArray(65537))) }
        invalid { CredentialStorePolicy.call("remove", mapOf("handleId" to handle, "profileId" to "Profile", "expectedRevision" to null)) }
        invalid { CredentialStorePolicy.call("read", mapOf("handleId" to handle, "profileId" to "Profile", "value" to bytes)) }
        invalid { CredentialStorePolicy.call("close", mapOf("handleId" to handle, "profileId" to "Profile")) }
        invalid { CredentialStorePolicy.call("clear", mapOf("handleId" to handle)) }
        invalid { CredentialStorePolicy.call("read", "PRIVATE") }
        // Then only the closed ABI reaches storage and no request diagnostics reveal ids.
        assertNull(CredentialStorePolicy.keys("login"))
        assertEquals("Profile", call.profileId)
        assertNull(call.expectedRevision)
        assertFalse(call.toString().contains("Profile"))
        assertEquals(65536, CredentialStorePolicy.call("replace", valid + ("value" to ByteArray(65536))).value!!.size)
    }

    @Test fun exactProfileIdentitiesHaveDistinctCasePreservingLocatorsAndAad() {
        // Given valid profiles including a case-only difference and length boundary.
        val profiles = listOf("Profile", "profile", "a._-0", "Z".repeat(128))
        // When the product alias/AAD locators are derived from exact UTF-8.
        val aliases = profiles.map { CredentialStorePolicy.alias(it) }
        val aads = profiles.map { CredentialStorePolicy.aad(it).toList() }
        // Then no profile identity collapses and invalid identities never enter storage.
        assertEquals(profiles.size, aliases.toSet().size)
        assertEquals(profiles.size, aads.toSet().size)
        assertTrue(aliases.all { Regex("org\\.textus\\.flutter\\.core\\.authentication\\.v1\\.[0-9a-f]+").matches(it) })
        for (profile in listOf("", ".first", "slot\n", "a/b", "é", "a".repeat(129))) invalid { CredentialStorePolicy.profile(profile) }
        for (revision in listOf("", "A".repeat(32), "f".repeat(31), "f".repeat(33), "$handle\n")) invalid { CredentialStorePolicy.revision(revision) }
    }

    @Test fun schemaAdmitsOnlyEmptyInitializationOrExactVersionOne() {
        // Given platform-default Android metadata and the credential table shape.
        val metadata = listOf(CredentialStoreColumn(0, "locale", "TEXT", false, null, 0))
        val credentials = listOf(CredentialStoreColumn(0, "profile", "TEXT", true, null, 1),
            CredentialStoreColumn(1, "sealed", "BLOB", true, null, 0))
        // When compatible initial/existing schemas are observed, admission succeeds.
        CredentialStorePolicy.schema(0, emptySet(), emptyList(), emptyList())
        CredentialStorePolicy.schema(0, setOf("android_metadata"), metadata, emptyList())
        CredentialStorePolicy.schema(1, setOf("android_metadata", "credentials"), metadata, credentials)
        // Then other versions/tables/constraints cannot trigger reset or migration.
        val incompatible: List<() -> Unit> = listOf(
            { CredentialStorePolicy.schema(2, setOf("credentials"), emptyList(), credentials) },
            { CredentialStorePolicy.schema(0, setOf("connections"), emptyList(), emptyList()) },
            { CredentialStorePolicy.schema(0, setOf("credentials"), emptyList(), credentials) },
            { CredentialStorePolicy.schema(1, emptySet(), emptyList(), emptyList()) },
            { CredentialStorePolicy.schema(1, setOf("credentials"), emptyList(), credentials.dropLast(1)) },
            { CredentialStorePolicy.schema(0, setOf("android_metadata"), metadata.map { it.copy(notNull = true) }, emptyList()) })
        for (action in incompatible) {
            try { action(); fail("Expected incompatible storage") }
            catch (error: CredentialStoreFailure) { assertEquals(CredentialStoreFailure.UNAVAILABLE, error.code) }
        }
    }
}
