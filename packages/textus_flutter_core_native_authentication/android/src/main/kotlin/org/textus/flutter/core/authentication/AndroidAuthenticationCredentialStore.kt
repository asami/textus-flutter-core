package org.textus.flutter.core.authentication

import android.content.Context
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.File
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/** No cached database, key or plaintext. Each explicit operation owns its DB
 * handle and write transaction, including the comparison and key cleanup.
 */
internal class AndroidAuthenticationCredentialStore(private val context: Context) {
    private fun unavailable(): Nothing = throw CredentialStoreFailure(CredentialStoreFailure.UNAVAILABLE)

    private fun open(): SQLiteDatabase {
        val directory = File(context.noBackupFilesDir, "textus_authentication_v1")
        if (!directory.isDirectory && !directory.mkdirs()) unavailable()
        return SQLiteDatabase.openDatabase(File(directory, "credentials.db").path, null,
            SQLiteDatabase.CREATE_IF_NECESSARY,
            DatabaseErrorHandler { throw CredentialStoreFailure(CredentialStoreFailure.UNAVAILABLE) })
    }

    private fun columns(db: SQLiteDatabase, metadata: Boolean): List<CredentialStoreColumn> {
        val result = mutableListOf<CredentialStoreColumn>()
        val query = if (metadata) "PRAGMA table_info(android_metadata)" else "PRAGMA table_info(credentials)"
        db.rawQuery(query, null).use { cursor ->
            while (cursor.moveToNext()) {
                if (result.size >= 8) unavailable()
                result.add(CredentialStoreColumn(cursor.getInt(0), cursor.getString(1),
                    cursor.getString(2), cursor.getInt(3) != 0,
                    if (cursor.isNull(4)) null else cursor.getString(4), cursor.getInt(5)))
            }
        }
        return result
    }

    private fun schema(db: SQLiteDatabase) {
        val tables = mutableSetOf<String>()
        db.rawQuery("SELECT type,name,sql FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'", null).use { cursor ->
            while (cursor.moveToNext()) {
                if (cursor.getString(0) != "table" || tables.size >= 2) unavailable()
                val name = cursor.getString(1)
                if (name == "credentials" && cursor.getString(2) !=
                    "CREATE TABLE credentials (profile TEXT PRIMARY KEY NOT NULL, sealed BLOB NOT NULL)") unavailable()
                tables.add(name)
            }
        }
        CredentialStorePolicy.schema(db.version, tables,
            if ("android_metadata" in tables) columns(db, true) else emptyList(),
            if ("credentials" in tables) columns(db, false) else emptyList())
        if (db.version == 0) {
            db.execSQL("CREATE TABLE credentials (profile TEXT PRIMARY KEY NOT NULL, sealed BLOB NOT NULL)")
            db.version = 1
        }
    }

    private fun key(profileId: String, allowCreate: Boolean): SecretKey {
        val alias = CredentialStorePolicy.alias(profileId)
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (keys.containsAlias(alias)) return keys.getKey(alias, null) as? SecretKey ?: unavailable()
        if (!allowCreate) unavailable()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(alias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true).build())
        return generator.generateKey()
    }

    private fun deleteKey(profileId: String) {
        val keys = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val alias = CredentialStorePolicy.alias(profileId)
        if (keys.containsAlias(alias)) keys.deleteEntry(alias)
        if (keys.containsAlias(alias)) unavailable()
    }

    private fun row(db: SQLiteDatabase, profileId: String): AuthenticationCredentialEntry? {
        db.rawQuery("SELECT length(sealed),sealed FROM credentials WHERE profile=?", arrayOf(profileId)).use { cursor ->
            if (!cursor.moveToFirst()) return null
            if (cursor.isNull(0) || cursor.getLong(0) !in 53L..AuthenticationCredentialCipher.MAX_SEALED.toLong()) unavailable()
            val sealed = cursor.getBlob(1)
            if (cursor.moveToNext()) unavailable()
            return AuthenticationCredentialCipher.unseal(profileId, sealed, key(profileId, false))
        }
    }

    fun execute(call: CredentialStoreCall, issue: () -> Unit): Any? {
        try {
            open().use { db ->
                db.execSQL("PRAGMA synchronous = FULL")
                db.compileStatement("PRAGMA busy_timeout = 5000").use {
                    if (it.simpleQueryForLong() != 5000L) unavailable()
                }
                db.beginTransaction()
                try {
                    // Unissued queued work cannot mutate after close/detach.
                    issue()
                    schema(db)
                    val profile = call.profileId ?: unavailable()
                    val result: Any? = when (call.method) {
                        "read" -> row(db, profile)?.reply()
                        "replace" -> {
                            val previous = row(db, profile)
                            if (previous?.revision != call.expectedRevision) null
                            else {
                                val entry = AuthenticationCredentialCipher.fresh(call.value ?: unavailable())
                                val sealed = AuthenticationCredentialCipher.seal(profile, entry, key(profile, previous == null))
                                if (previous == null) db.execSQL("INSERT INTO credentials(profile,sealed) VALUES(?,?)", arrayOf(profile, sealed))
                                else db.execSQL("UPDATE credentials SET sealed=? WHERE profile=?", arrayOf(sealed, profile))
                                entry.revision
                            }
                        }
                        "remove" -> {
                            val previous = row(db, profile)
                            if (previous == null || previous.revision != call.expectedRevision) false
                            else {
                                db.execSQL("DELETE FROM credentials WHERE profile=?", arrayOf(profile))
                                deleteKey(profile)
                                true
                            }
                        }
                        "clear" -> {
                            db.execSQL("DELETE FROM credentials WHERE profile=?", arrayOf(profile))
                            deleteKey(profile)
                            null
                        }
                        else -> unavailable()
                    }
                    db.setTransactionSuccessful()
                    return result
                } finally {
                    db.endTransaction()
                }
            }
        } catch (failure: CredentialStoreFailure) {
            throw failure
        } catch (_: Exception) {
            unavailable()
        }
    }
}
