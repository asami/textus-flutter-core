package org.textus.flutter.core.submission

/** Monotonic native ownership. All cross-thread transitions are synchronized. */
internal class SubmissionRunLifecycle(val runId: String, val generation: Long) {
    init { SubmissionConnectionPolicy.safeId(runId) }
    private var current = true
    private var terminal = false

    @Synchronized fun isCurrent(id: String = runId, owner: Long = generation): Boolean =
        current && id == runId && owner == generation

    /** Retires before native stop is sent. Repeated stop cannot revive ownership. */
    @Synchronized fun retire() { current = false }

    /** A matching live terminal callback wins once; late/mismatched callbacks lose. */
    @Synchronized fun acceptTerminal(id: String, owner: Long): Boolean {
        if (!isCurrent(id, owner) || terminal) return false
        terminal = true
        current = false
        return true
    }
}

/** A captured configuration handle belongs permanently to one engine/context.
 * Retirement removes its slot before cancellation or serialized disposal. The
 * caller disposes the returned handle, never whatever a later acquire installs.
 */
internal class SubmissionConfigurationContext<T : Any>(
    val engineOwner: Long,
    val requestCode: Int,
    val handle: T,
)

/** Pure lazy configuration ownership used by the native plugin. Factories run
 * under the ownership lock; failure consumes its resolution code but installs
 * no slot. Codes are never reset, including across engine detach/attach.
 */
internal class SubmissionConfigurationLifecycle<T : Any>(
    firstRequestCode: Int = 21861,
) {
    private var generation = 0L
    private var attached = false
    private var current: SubmissionConfigurationContext<T>? = null
    private var nextRequestCode = firstRequestCode

    init { require(firstRequestCode in 21861..65535) }

    /** Starts an explicit engine lifetime; the previous owner must be detached. */
    @Synchronized fun attach(): Long {
        check(!attached)
        generation++
        attached = true
        return generation
    }

    @Synchronized fun engineCurrent(owner: Long): Boolean = attached && owner == generation

    /** Lazily constructs one handle. The guard becomes true only after install. */
    @Synchronized fun acquire(
        owner: Long,
        factory: (Int, () -> Boolean) -> T,
    ): SubmissionConfigurationContext<T> {
        if (!engineCurrent(owner)) throw SubmissionConfigurationFailure("configurationClosed")
        current?.let { return it }
        if (nextRequestCode > 65535) throw SubmissionConfigurationFailure("configurationUnavailable")
        val requestCode = nextRequestCode++
        val handle = factory(requestCode) { isCurrentCode(owner, requestCode) }
        val context = SubmissionConfigurationContext(owner, requestCode, handle)
        current = context
        return context
    }

    @Synchronized private fun isCurrentCode(owner: Long, requestCode: Int): Boolean =
        engineCurrent(owner) && current?.requestCode == requestCode

    @Synchronized fun isCurrent(context: SubmissionConfigurationContext<T>): Boolean =
        engineCurrent(context.engineOwner) && current === context

    @Synchronized fun peek(): SubmissionConfigurationContext<T>? = current

    /** Repeated retirement returns no handle and cannot close a later context. */
    @Synchronized fun retire(context: SubmissionConfigurationContext<T>): SubmissionConfigurationContext<T>? {
        if (!isCurrent(context)) return null
        val retired = current
        current = null
        return retired
    }

    /** Invalidates configuration and engine replies before any cleanup begins. */
    @Synchronized fun detach(): SubmissionConfigurationContext<T>? {
        val retired = current
        current = null
        attached = false
        generation++
        return retired
    }
}

/** Pure consent transition policy, owned by one attached engine/activity lineage. */
internal class SubmissionConsentLifecycle {
    var generation: Long = 0
        private set
    var resumed: Boolean = false
        private set
    var resolving: Boolean = false
        private set
    private var pending = false
    private var retained = false

    @Synchronized fun attach(isResumed: Boolean, reattach: Boolean) {
        if (!reattach || !retained) {
            generation++
            pending = false
            resolving = false
        }
        retained = false
        resumed = isResumed
    }

    @Synchronized fun resume() { resumed = true }
    @Synchronized fun begin(): Long {
        if (!resumed) throw SubmissionConfigurationFailure("foregroundRequired")
        if (pending) throw SubmissionConfigurationFailure("authorizationBusy")
        pending = true
        return generation
    }
    @Synchronized fun current(owner: Long): Boolean = pending && owner == generation
    @Synchronized fun launch(owner: Long) {
        if (!current(owner) || !resumed) throw SubmissionConfigurationFailure("authorizationCancelled")
        resolving = true
    }
    /** Only our launched resolution may cross its expected foreground pause. */
    @Synchronized fun pause(): Boolean {
        resumed = false
        if (pending && !resolving) {
            cancel()
            return true
        }
        return false
    }
    @Synchronized fun detach(forConfigurationChange: Boolean): Boolean {
        resumed = false
        if (forConfigurationChange && pending && resolving) {
            retained = true
            return false
        }
        val cancelled = pending
        cancel()
        return cancelled
    }
    @Synchronized fun finish(owner: Long): Boolean {
        if (!current(owner)) return false
        pending = false
        resolving = false
        return true
    }
    @Synchronized fun cancel() {
        generation++
        pending = false
        resolving = false
        retained = false
    }
}
