package org.textus.flutter.core.authentication

import org.junit.Assert.*
import org.junit.Test
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec

/** Synthetic JCE keys establish framing/GCM semantics, never AndroidKeyStore acceptance. */
class AuthenticationCredentialCipherTest {
    private fun key(): SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
    private fun unavailable(action: () -> Unit) {
        try { action(); fail("Expected safe unavailable") }
        catch (error: CredentialStoreFailure) {
            assertEquals(CredentialStoreFailure.UNAVAILABLE, error.code)
            assertFalse(error.toString().contains("PRIVATE"))
            assertNull(error.cause)
        }
    }

    @Test fun gcmRoundtripCopiesAndRedactsOpaqueEntries() {
        // Given a synthetic key and caller-owned revision/value bytes.
        val key = key()
        val revision = ByteArray(16) { it.toByte() }
        val value = byteArrayOf(7, 8, 9)
        val entry = AuthenticationCredentialEntry(revision, value)
        revision[0] = 99; value[0] = 99
        // When the entry is encrypted/decrypted for one exact profile.
        val sealed = AuthenticationCredentialCipher.seal("Slot", entry, key)
        val decoded = AuthenticationCredentialCipher.unseal("Slot", sealed, key)
        val readCopy = decoded.value
        readCopy[0] = 88
        // Then copies, exact storage revision and authenticated bytes survive.
        assertArrayEquals(byteArrayOf(7, 8, 9), decoded.value)
        assertEquals("000102030405060708090a0b0c0d0e0f", decoded.revision)
        assertEquals(entry.revision, decoded.revision)
        assertFalse(decoded.toString().contains(decoded.revision))
        assertFalse(decoded.toString().contains("7, 8, 9"))
        val payload = decoded.payload(); payload[20] = 0
        assertArrayEquals(byteArrayOf(7, 8, 9), decoded.value)
    }

    @Test fun tamperWrongProfileWrongKeyAndTruncationFailClosed() {
        // Given one complete encrypted synthetic record.
        val key = key()
        val sealed = AuthenticationCredentialCipher.seal("Profile", AuthenticationCredentialCipher.fresh(byteArrayOf(1)), key)
        // When AAD/profile, key, header, IV, tag or ciphertext is changed.
        unavailable { AuthenticationCredentialCipher.unseal("profile", sealed, key) }
        unavailable { AuthenticationCredentialCipher.unseal("Other", sealed, key) }
        unavailable { AuthenticationCredentialCipher.unseal("Profile", sealed, key()) }
        unavailable { AuthenticationCredentialCipher.unseal("Profile", sealed, SecretKeySpec(byteArrayOf(1), "AES")) }
        for (index in listOf(0, 3, 4, 15, 16, sealed.lastIndex)) {
            val changed = sealed.copyOf(); changed[index] = (changed[index].toInt() xor 1).toByte()
            unavailable { AuthenticationCredentialCipher.unseal("Profile", changed, key) }
        }
        for (length in listOf(0, 4, 16, 32, 52, sealed.size - 1)) {
            unavailable { AuthenticationCredentialCipher.unseal("Profile", sealed.copyOf(length), key) }
        }
        // Then no partial/plaintext fallback or OS/JCE error details are exposed.
        unavailable { AuthenticationCredentialCipher.unseal("Profile", ByteArray(65589), key) }
    }

    @Test fun exactPayloadBoundsAndVersionAreEnforced() {
        // Given minimum and maximum allowed opaque values with a synthetic key.
        val key = key()
        for (size in listOf(1, 65536)) {
            val value = ByteArray(size) { (it % 251).toByte() }
            val entry = AuthenticationCredentialCipher.fresh(value)
            // When a complete payload and sealed frame are round-tripped.
            val payload = entry.payload()
            val sealed = AuthenticationCredentialCipher.seal("bounds", entry, key)
            assertEquals(size + 20, payload.size)
            assertEquals(size + 52, sealed.size)
            assertArrayEquals(value, AuthenticationCredentialCipher.decode(payload).value)
            assertArrayEquals(value, AuthenticationCredentialCipher.unseal("bounds", sealed, key).value)
            // Then a version change cannot become absence or an accepted record.
            payload[3] = 50
            unavailable { AuthenticationCredentialCipher.decode(payload) }
        }
        unavailable { AuthenticationCredentialCipher.decode(ByteArray(20)) }
        unavailable { AuthenticationCredentialCipher.decode(ByteArray(65557)) }
        unavailable { AuthenticationCredentialEntry(ByteArray(15), byteArrayOf(1)) }
        unavailable { AuthenticationCredentialEntry(ByteArray(16), ByteArray(0)) }
        unavailable { AuthenticationCredentialEntry(ByteArray(16), ByteArray(65537)) }
        // Given fresh production revision generation, repeated writes yield independent ids.
        val one = AuthenticationCredentialCipher.fresh(byteArrayOf(1))
        val two = AuthenticationCredentialCipher.fresh(byteArrayOf(1))
        assertNotEquals(one.revision, two.revision)
        assertTrue(Regex("[0-9a-f]{32}").matches(one.revision))
    }
}
