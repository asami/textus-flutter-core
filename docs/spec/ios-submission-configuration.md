# iOS submission configuration

`IosSubmissionConfigurationStore` implements `SubmissionConfigurationStore` and
`SubmissionCredentialProvider`. Its private constructor is reached through
`open(databasePath:, factory:, credentials:)`. The handle owns one independent
SQLite connection; the optional credential provider is borrowed and read-only.

## Opening and durable representation

Only non-Web iOS is supported, including when a database factory is injected.
Unsupported platforms fail with `UnsupportedError` before path-provider,
database or credential IO. An explicit path must be nonblank and must not be
`:memory:`; invalid paths fail with a safe `ArgumentError`. The default file is
`textus_ios_submission_configuration.sqlite` in application support.

Opening uses the existing sqflite and path-provider dependencies. It performs no
consent, token issuance, credential read, network access, environment lookup or
App token-state mutation. The database has version 1, independent handles
(`singleInstance: false`), a 5000 ms SQLite busy timeout and FULL synchronous
writes. Schema creation atomically creates `ios_submission_configuration` with
`singleton INTEGER PRIMARY KEY CHECK(singleton = 1)` and `body TEXT NOT NULL`,
and inserts the legitimate empty version 2 `SubmissionConfigurationSnapshot`.
An absent database is the only source of that initial empty configuration.

The sole body is exactly `snapshot.toJson()`: safe immutable Drive and HTTP
definitions, selection and explicit reference-access bindings. The existing
strict snapshot and connection codecs govern accepted schemas and versions.
The shared bounds remain 128 total connection IDs, 65536 UTF-8 bytes per
definition, 128 × 65536 UTF-8 bytes per snapshot, and 128 aggregate reference
associations. No additional persisted fields are allowed. Before returning a
new handle, open reads and validates the singleton. Missing, malformed, extra
or unknown-version stored values fail visibly. There is no empty fallback,
migration, downgrade, deletion or replacement on failure. Acquired handles are
closed after partial-open failure without replacing the primary safe error.

This file stores public configuration; it is not a secret vault. Tokens,
headers, passwords, private credential-store values and queue data must never
be written to it. Protected authentication storage belongs to the credential
owner. Account and folder identities in safe connection definitions remain
part of the public configuration projection.

## Transactional immutable identities

Every read or mutation uses a fresh SQLite transaction. A handle serializes
accepted operations and keeps no snapshot cache. Within one isolate, stores
using the same selected database path share a private SQL coordinator while
retaining independent owned database handles. It serializes each complete open
(including configuration, initial validation and partial-open cleanup), each
complete transaction and each owned database close. Concurrent registrations
therefore preserve all distinct accepted identities without overlapping same-path
SQL operations on a shared SQL isolate. Path acceptance and canonicalization are
unchanged; SQLite transactions, the busy timeout and FULL synchronous writes
retain their role for other path aliases, engines and processes.

The coordinator retains in-progress opens and live handles. Failed opens release
their reference after cleanup; a retired handle releases its reference after its
drained database close, including a failed close. An unused coordinator is removed
only after its last reference is released. SQL failures do not prevent another
handle's later operation. A handle waiting for coordination rechecks retirement
before beginning a new transaction. No borrowed credential call runs inside a
database transaction or holds the shared SQL coordinator.

`snapshot()` returns the strict current detached, frozen shared value.
`putDrive` and `putHttp` accept identical `toJson()` definitions idempotently
using shared deep equality. An existing ID is immutable across kinds: changed
account, folder, endpoint, authentication requirement or type fails with
`connectionConflict`. Existing connection validators and bounds apply unchanged.
Invalid whole snapshots fail before committing any partial addition.

`select` accepts only registered IDs of the exact requested kind; null clears
that selection. Unknown or wrong-kind IDs fail with `connectionMissing`.
Definitions and reference declarations remain unchanged.

`setReferenceAccess` validates exact safe IDs, at most 128 supplied storage IDs
and no duplicates before IO. Its transaction requires a registered HTTP target
and registered Drive storage targets; wrong-kind or missing IDs fail with
`connectionMissing`. It replaces only that target's declaration. An empty list
is explicit revocation; an absent key means access has not been declared.
Selection and definitions are preserved, and the complete resulting snapshot
must satisfy the aggregate bound before commit. A declaration records operator
intent; it does not prove actual server or Drive permissions.

Failed input validation, identity conflicts and invalid resulting snapshots
leave accepted durable state unchanged. No operation changes a queue, a
credential or a previously accepted immutable target.

## Borrowed credential reads

`bearerToken(id)` validates the exact ID and reads its immutable definition in
a fresh transaction independently of current selection. An unknown target
fails with `connectionMissing`. Anonymous HTTP targets return null without
calling a provider. Any other registered target returns null when no provider
is supplied. Null means explicit authorization is needed.

Otherwise only that exact configured connection ID is delegated to the borrowed
provider after the transaction ends and the shared SQL coordinator is released.
A pending credential read or its closing owner does not block another handle's
snapshot or mutation. Each call requests the current token;
tokens are returned ephemerally without caching, storage or implicit lookup.
A nonnull token must be at most 8192 characters and must fully match
`[A-Za-z0-9._~+/-]+=*`, including at least one prefix character. Malformed tokens
and all provider failures become the fixed `credentialUnavailable` error,
without retaining or reflecting their inputs, exceptions or causes. The facade
does not invent provider retries, timeouts, authorization UI or token writers.
The provider retains responsibility for its bounded lifetime and secure storage.

## Retirement and failures

`close()` retires the handle synchronously and shares one idempotent Future.
New calls fail with `configurationClosed`. Calls accepted but not dispatched at
retirement perform no new IO. Close joins all accepted operations, including an
already dispatched credential read, and suppresses their late success or failure
with `configurationClosed`. Internal completion errors are observed without
replacing the result delivered to their actual callers.

Already dispatched writes may finish. Close is not rollback or logout: it closes
only this owned database handle through shared SQL coordination, never the
borrowed provider, and never clears
definitions, credentials or queued intent. Other independent handles remain
usable, and reopening retains committed data.

Errors use only `SubmissionConfigurationException.safe` and its fixed public
messages: strict stored-value or whole-snapshot invalidity is
`configurationInvalid`; database/plugin acquisition and IO failures are
`configurationUnavailable`; immutable conflicts, missing targets, retirement
and borrowed credential failures use the categories described above. Public
pre-IO validation retains safe `ArgumentError` behavior. No path, raw input,
provider exception or ordinary-error cause is exposed or logged by the store.

## Execution and acceptance boundary

This configuration contract supplies durable target/reference definitions and
borrowed credential reads. iOS queue execution, stop/resume, Framework/App
connection and real participant/server behavior require their own connected
implementation and acceptance. Temporary file-backed host SQLite scenarios
exercise the storage and ownership contract only. Native iPhone operation,
authentication, server acceptance and the Phase's full validation and review
remain separate required evidence; host FFI is not native acceptance.
