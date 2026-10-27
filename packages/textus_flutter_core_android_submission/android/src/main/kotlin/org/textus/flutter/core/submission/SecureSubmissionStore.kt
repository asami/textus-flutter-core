package org.textus.flutter.core.submission

import android.content.Context
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** One engine-owned IO-only SQLite handle. Complete definitions and secrets are
 * authenticated AES-GCM envelopes; only safe identities remain plaintext. No
 * corruption handler deletes a database and no missing key replaces an old key.
 * Callers serialize methods on Dispatchers.IO and close this handle on detach.
 */
internal class SecureSubmissionStore(private val context: Context) {
    private var database: SQLiteDatabase? = null
    private var closed = false

    companion object {
        private val keyLock = Any()
        private const val keyAlias = "org.textus.flutter.core.submission.config.v1"
        private const val prefix = "textus-submission-config-v1:"
        private const val maximumPlaintext = 65536
    }

    private fun unavailable(): Nothing = throw SubmissionConfigurationFailure("configurationUnavailable")

    private fun open(): SQLiteDatabase {
        if (closed) throw SubmissionConfigurationFailure("configurationClosed")
        database?.let { return it }
        var acquired: SQLiteDatabase? = null
        try {
            val path = java.io.File(context.noBackupFilesDir, "textus_submission_config.sqlite")
            acquired = SQLiteDatabase.openDatabase(path.path, null,
                SQLiteDatabase.CREATE_IF_NECESSARY,
                DatabaseErrorHandler { throw SubmissionConfigurationFailure("configurationUnavailable") })
            acquired.execSQL("PRAGMA synchronous = FULL")
            // Given a newly acquired database with FULL write durability already configured.
            // When the scalar setting executes, consume its result and close the owned statement.
            acquired.compileStatement("PRAGMA busy_timeout = 5000").use { statement ->
                if (statement.simpleQueryForLong() != 5000L) unavailable()
            }
            // Then the exact existing 5000ms wait is set before transactional schema admission.
            acquired.beginTransaction()
            try {
                if (acquired.version == 0) {
                    // Given a version-zero database whose platform metadata may already exist.
                    val tableNames = mutableListOf<String>()
                    acquired.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name", null).use { cursor ->
                        while (cursor.moveToNext()) tableNames.add(cursor.getString(0))
                    }
                    val metadataColumns = mutableListOf<SubmissionMetadataColumn>()
                    if (tableNames.contains("android_metadata")) {
                        acquired.rawQuery("PRAGMA table_info(android_metadata)", null).use { cursor ->
                            val defaultValueIndex = cursor.getColumnIndexOrThrow("dflt_value")
                            while (cursor.moveToNext()) {
                                metadataColumns.add(SubmissionMetadataColumn(
                                    cursor.getInt(cursor.getColumnIndexOrThrow("cid")),
                                    cursor.getString(cursor.getColumnIndexOrThrow("name")),
                                    cursor.getString(cursor.getColumnIndexOrThrow("type")),
                                    cursor.getInt(cursor.getColumnIndexOrThrow("notnull")) != 0,
                                    if (cursor.isNull(defaultValueIndex)) null else cursor.getString(defaultValueIndex),
                                    cursor.getInt(cursor.getColumnIndexOrThrow("pk"))
                                ))
                            }
                        }
                    }
                    // When the actual observed tables and six column fields satisfy the closed policy.
                    SubmissionConnectionPolicy.validateInitialSchema(tableNames, metadataColumns)
                    // Then create the original Core tables and version in this same transaction.
                    acquired.execSQL("CREATE TABLE connections (id TEXT PRIMARY KEY NOT NULL, sealed BLOB NOT NULL)")
                    acquired.execSQL("CREATE TABLE selection (id INTEGER PRIMARY KEY CHECK(id=1), sealed BLOB NOT NULL)")
                    acquired.version = 1
                } else if (acquired.version != 1) unavailable()
                acquired.setTransactionSuccessful()
            } finally {
                acquired.endTransaction()
            }
            database = acquired
            return acquired
        } catch (_: Exception) {
            acquired?.close()
            unavailable()
        }
    }

    private fun hasSealedRows(db: SQLiteDatabase): Boolean {
        db.rawQuery("SELECT 1 FROM connections UNION ALL SELECT 1 FROM selection LIMIT 1", null).use {
            return it.moveToFirst()
        }
    }

    /** Key initialization is synchronized across engines and always checks rows. */
    private fun key(db: SQLiteDatabase, allowCreate: Boolean): SecretKey = synchronized(keyLock) {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(keyAlias)) {
            return@synchronized (store.getKey(keyAlias, null) as? SecretKey ?: unavailable())
        }
        if (!allowCreate || hasSealedRows(db)) unavailable()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true).build())
        generator.generateKey()
    }

    private fun seal(db: SQLiteDatabase, value: Map<String, Any?>, identity: String): ByteArray {
        val bytes = toJson(value).toString().toByteArray(Charsets.UTF_8)
        if (bytes.size > maximumPlaintext) throw SubmissionConfigurationFailure("configurationInvalid")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(db, true))
        val iv = cipher.iv
        if (iv.size != 12) unavailable()
        cipher.updateAAD((prefix + identity).toByteArray(Charsets.UTF_8))
        return byteArrayOf(1) + iv + cipher.doFinal(bytes)
    }

    private fun unseal(db: SQLiteDatabase, bytes: ByteArray, identity: String): Map<String, Any?> {
        if (bytes.size < 29 || bytes.size > maximumPlaintext + 29 || bytes[0] != 1.toByte()) unavailable()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(db, false), GCMParameterSpec(128, bytes.copyOfRange(1, 13)))
        cipher.updateAAD((prefix + identity).toByteArray(Charsets.UTF_8))
        val plaintext = cipher.doFinal(bytes.copyOfRange(13, bytes.size))
        if (plaintext.size > maximumPlaintext) unavailable()
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
            .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
        val parsed = JSONObject(decoder.decode(java.nio.ByteBuffer.wrap(plaintext)).toString())
        return SubmissionConnectionPolicy.objectValue(fromJson(parsed))
    }

    private fun rows(db: SQLiteDatabase): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        db.rawQuery("SELECT id,sealed FROM connections ORDER BY id", null).use { cursor ->
            while (cursor.moveToNext()) {
                if (result.size >= 128) unavailable()
                val id = SubmissionConnectionPolicy.safeId(cursor.getString(0))
                val row = SubmissionConnectionPolicy.row(unseal(db, cursor.getBlob(1), "connection:$id"))
                if (SubmissionConnectionPolicy.objectValue(row["connection"])["id"] != id) unavailable()
                result.add(row)
            }
        }
        return result
    }

    private fun selected(db: SQLiteDatabase): Map<String, Any?> {
        db.rawQuery("SELECT id,sealed FROM selection", null).use { cursor ->
            if (!cursor.moveToFirst()) return mapOf("version" to 1,
                "storageConnectionId" to null, "transportConnectionId" to null)
            if (cursor.getInt(0) != 1) unavailable()
            val selected = SubmissionConnectionPolicy.selection(unseal(db, cursor.getBlob(1), "selection"))
            if (cursor.moveToNext()) unavailable()
            return selected
        }
    }

    private fun definitions(rows: List<Map<String, Any?>>) = rows.map {
        SubmissionConnectionPolicy.definition(it["connection"])
    }

    private fun <T> transaction(action: (SQLiteDatabase, List<Map<String, Any?>>, Map<String, Any?>) -> T): T {
        try {
            val db = open()
            db.beginTransaction()
            try {
                val rows = rows(db)
                val selection = selected(db)
                SubmissionConnectionPolicy.validateSelection(definitions(rows), selection)
                val result = action(db, rows, selection)
                db.setTransactionSuccessful()
                return result
            } finally {
                db.endTransaction()
            }
        } catch (failure: SubmissionConfigurationFailure) {
            throw failure
        } catch (_: Exception) {
            unavailable()
        }
    }

    fun snapshot(): Map<String, Any?> = transaction { _, rows, selection ->
        val definitions = definitions(rows)
        mapOf("version" to 2,
            "driveConnections" to definitions.filter { it["type"] == "googleDrive" },
            "httpConnections" to definitions.filter { it["type"] == "http" },
            "selectedStorageConnectionId" to selection["storageConnectionId"],
            "selectedTransportConnectionId" to selection["transportConnectionId"],
            "referenceAccessBindings" to SubmissionConnectionPolicy.referenceAccessBindings(selection))
    }

    fun put(value: Any?, type: String) {
        val proposed = SubmissionConnectionPolicy.definition(value, type)
        transaction { db, rows, _ ->
            val id = SubmissionConnectionPolicy.safeId(proposed["id"])
            val existing = rows.firstOrNull { SubmissionConnectionPolicy.objectValue(it["connection"])["id"] == id }
            SubmissionConnectionPolicy.insert(existing?.let { SubmissionConnectionPolicy.objectValue(it["connection"]) }, proposed)
            if (existing == null) {
                if (rows.size >= 128) throw SubmissionConfigurationFailure("configurationInvalid")
                val row = mapOf("version" to 1, "connection" to proposed,
                    "httpBearerToken" to null, "driveGranted" to false)
                db.execSQL("INSERT INTO connections(id,sealed) VALUES(?,?)",
                    arrayOf(id, seal(db, row, "connection:$id")))
            }
        }
    }

    fun select(storage: String?, transport: String?) {
        transaction { db, rows, current ->
            val selected = SubmissionConnectionPolicy.withSelection(definitions(rows), current, storage, transport)
            db.execSQL("INSERT OR REPLACE INTO selection(id,sealed) VALUES(1,?)",
                arrayOf(seal(db, selected, "selection")))
        }
    }

    /** Reuses the existing authenticated singleton envelope without migration.
     * Empty preserves explicit revocation; selection, secrets and rows survive.
     */
    fun setReferenceAccess(transportConnectionId: String, storageConnectionIds: Any?) {
        transaction { db, rows, current ->
            val selected = SubmissionConnectionPolicy.setReferenceAccess(definitions(rows), current,
                transportConnectionId, storageConnectionIds)
            db.execSQL("INSERT OR REPLACE INTO selection(id,sealed) VALUES(1,?)",
                arrayOf(seal(db, selected, "selection")))
        }
    }

    /** Returns an ephemeral owned value for an exact id, never a global cache. */
    fun credentialRow(id: String): Map<String, Any?> = transaction { _, rows, _ ->
        rows.firstOrNull { SubmissionConnectionPolicy.objectValue(it["connection"])["id"] == id }
            ?: throw SubmissionConfigurationFailure("connectionMissing")
    }

    fun setHttpToken(id: String, token: String?) = update(id) { row, definition ->
        if (definition["type"] != "http" || (token != null && definition["requiresBearerToken"] == false)) {
            throw SubmissionConfigurationFailure("configurationInvalid")
        }
        row + ("httpBearerToken" to SubmissionConnectionPolicy.bearer(token))
    }

    /** Rechecks exact immutable account after SDK awaits before persisting grant. */
    fun setDriveGrant(id: String, definition: Map<String, Any?>, granted: Boolean) = update(id) { row, actual ->
        if (actual != definition || actual["type"] != "googleDrive") {
            throw SubmissionConfigurationFailure("connectionConflict")
        }
        row + ("driveGranted" to granted)
    }

    private fun update(id: String, change: (Map<String, Any?>, Map<String, Any?>) -> Map<String, Any?>) {
        SubmissionConnectionPolicy.safeId(id)
        transaction { db, rows, _ ->
            val row = rows.firstOrNull { SubmissionConnectionPolicy.objectValue(it["connection"])["id"] == id }
                ?: throw SubmissionConfigurationFailure("connectionMissing")
            val changed = SubmissionConnectionPolicy.row(change(row, SubmissionConnectionPolicy.definition(row["connection"])))
            db.execSQL("UPDATE connections SET sealed=? WHERE id=?",
                arrayOf(seal(db, changed, "connection:$id"), id))
        }
    }

    /** Caller joins engine IO before closing; no persisted state is removed. */
    fun close() {
        closed = true
        database?.close()
        database = null
    }

    private fun toJson(value: Any?): Any = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> JSONObject().also { json -> value.forEach { (key, item) -> json.put(key as String, toJson(item)) } }
        is List<*> -> JSONArray().also { json -> value.forEach { json.put(toJson(it)) } }
        else -> value
    }

    private fun fromJson(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { fromJson(value.get(it)) }
        is JSONArray -> (0 until value.length()).map { fromJson(value.get(it)) }
        is String, is Boolean, is Int, is Long -> value
        else -> unavailable()
    }
}
