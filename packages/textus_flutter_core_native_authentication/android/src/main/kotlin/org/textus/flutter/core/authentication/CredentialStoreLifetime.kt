package org.textus.flutter.core.authentication

/** Retirement is independent of the IO queue: queued work must acquire issuance
 * under its storage transaction. Issued IO may finish; delivery is withdrawn.
 */
internal class CredentialStoreLifetime {
    internal class Operation internal constructor(val handleId: String) {
        internal var issued = false
        internal var completed = false
    }
    private var live = true
    private val retired = mutableSetOf<String>()

    @Synchronized fun accept(handleId: String): Operation {
        if (!live || handleId in retired) throw CredentialStoreFailure(CredentialStoreFailure.CLOSED)
        return Operation(handleId)
    }

    @Synchronized fun retire(handleId: String) { retired.add(handleId) }
    @Synchronized fun detach() { live = false }
    @Synchronized fun isLive(): Boolean = live
    @Synchronized fun current(operation: Operation): Boolean = live && operation.handleId !in retired

    /** Called only after obtaining the platform storage serialization boundary. */
    @Synchronized fun issue(operation: Operation) {
        if (!current(operation) || operation.issued || operation.completed) {
            throw CredentialStoreFailure(CredentialStoreFailure.CLOSED)
        }
        operation.issued = true
    }

    /** One completion while live. False means suppress (detach or duplicate). */
    @Synchronized fun complete(operation: Operation): Boolean {
        if (operation.completed) return false
        operation.completed = true
        return live
    }
}
