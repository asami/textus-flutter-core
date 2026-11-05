package org.textus.flutter.core.authentication

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class AuthenticationCredentialEntry(revision: ByteArray, value: ByteArray) {
    private val revisionBytes = revision.copyOf()
    private val valueBytes = value.copyOf()
    init {
        if (revisionBytes.size != 16 || valueBytes.size !in 1..CredentialStorePolicy.MAX_VALUE) {
            throw CredentialStoreFailure(CredentialStoreFailure.UNAVAILABLE)
        }
    }
    val revision: String get() = revisionBytes.joinToString("") {
        (it.toInt() and 255).toString(16).padStart(2, '0')
    }
    val value: ByteArray get() = valueBytes.copyOf()
    fun payload(): ByteArray = byteArrayOf(84, 70, 67, 49) + revisionBytes + valueBytes
    fun reply(): Map<String, Any> = mapOf("revision" to revision, "value" to value)
    override fun toString() = "AuthenticationCredentialEntry"
}

/** Complete frames are bounded before slicing/decrypting. No Android dependencies. */
internal object AuthenticationCredentialCipher {
    const val MAX_SEALED = 65588
    private val sealedMagic = byteArrayOf(84, 70, 69, 49)
    private val payloadMagic = byteArrayOf(84, 70, 67, 49)

    fun fresh(value: ByteArray): AuthenticationCredentialEntry {
        CredentialStorePolicy.value(value)
        val revision = ByteArray(16)
        SecureRandom().nextBytes(revision)
        return AuthenticationCredentialEntry(revision, value)
    }

    fun decode(payload: ByteArray): AuthenticationCredentialEntry {
        if (payload.size !in 21..65556 ||
            !payload.copyOfRange(0, 4).contentEquals(payloadMagic)) {
            throw CredentialStoreFailure(CredentialStoreFailure.UNAVAILABLE)
        }
        return AuthenticationCredentialEntry(payload.copyOfRange(4, 20),
            payload.copyOfRange(20, payload.size))
    }

    fun seal(profileId: String, entry: AuthenticationCredentialEntry, key: SecretKey): ByteArray = safe {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        val iv = cipher.iv
        if (iv.size != 12) throw CredentialStoreFailure(CredentialStoreFailure.UNAVAILABLE)
        cipher.updateAAD(CredentialStorePolicy.aad(profileId))
        sealedMagic + iv + cipher.doFinal(entry.payload())
    }

    fun unseal(profileId: String, sealed: ByteArray, key: SecretKey): AuthenticationCredentialEntry = safe {
        if (sealed.size !in 53..MAX_SEALED ||
            !sealed.copyOfRange(0, 4).contentEquals(sealedMagic)) {
            throw CredentialStoreFailure(CredentialStoreFailure.UNAVAILABLE)
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed.copyOfRange(4, 16)))
        cipher.updateAAD(CredentialStorePolicy.aad(profileId))
        decode(cipher.doFinal(sealed.copyOfRange(16, sealed.size)))
    }

    private fun <T> safe(action: () -> T): T = try { action() } catch (_: Exception) {
        throw CredentialStoreFailure(CredentialStoreFailure.UNAVAILABLE)
    }
}
