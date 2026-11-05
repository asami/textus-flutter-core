# Internal native authentication credential storage

Decision date: 2026-11-05. Scope: necessary internal protected-storage prerequisite for the accepted [Core authentication client](user-account-authentication-client.md), within original whole Phase 6.10. Implementation and executable specifications require the parent's validation and independent conformance review; this document is no execution receipt.

The internal Dart implementation is `lib/src/authentication/native_authentication_credential_store.dart`. It is deliberately absent from the root library exports. The native-only plugin is `packages/textus_flutter_core_native_authentication` version 0.0.1. App and Framework have no production consumer. This component stores opaque bytes; it does not verify credentials, create accounts, issue sessions, perform network/refresh work, restore accounts or publish authentication state. A profile is an exact local configuration slot, never a UserAccount/session identity. No password, HTTP field, route, JWT, TTL or queue format is inferred.

## Internal operations and lifetime

Profiles match exactly `[A-Za-z0-9][A-Za-z0-9._-]{0,127}`. Revisions match exactly lowercase `[0-9a-f]{32}`. Values contain 1 through 65536 opaque bytes. Entry construction copies inputs; every value getter yields a detached copy. Entry diagnostics expose neither revision nor bytes. Storage revisions control write concurrency and carry no authentication authority.

Construction generates a fresh 16-byte `Random.secure` local handle encoded as 32 lowercase hex characters, with no credential/channel IO. `isSupported` is read-only and true only for native Android/iOS (`!kIsWeb`). Unsupported operations fail before channel IO; unsupported close is local. The default channel is `org.textus.flutter.core/authentication_credentials`; Dart's optional channel parameter is an internal test seam, not a production native storage override.

- `read(profileId)` returns null only for an absent slot, otherwise an immutable entry. Unavailable/corrupt data is never absence.
- `replace(profileId:, expectedRevision:, value:)` copies input before channel encoding. Null expected revision creates only if absent. An exact existing revision rotates bytes and revision. Match returns a new cryptographically random 16-byte revision encoded in lowercase hex; mismatch returns null without mutation.
- `remove(profileId:, expectedRevision:)` removes only the exact matching revision; absence/mismatch returns false. A retired backend can remove its own late write without erasing a newer writer.
- `clear(profileId)` is an explicit, idempotent, unconditional recovery/logout operation for that one slot, including unreadable records. It is never automatic read-error cleanup or cancelled-write cleanup.
- `close()` retires the local handle before awaiting, starts native close immediately, joins it and every accepted call, and memoizes the same future. It observes errors, drains all work even after failure, withdraws late results and returns only a fixed safe failure. It preserves records and other handles/profiles. Already-issued writes may finish; closure is not logout, cancellation rollback or a claim of remote revocation.

Fixed argument errors never reflect inputs. Internal exception categories are `closed`, `unavailable`, `invalidResponse`, with code-only diagnostics. Unknown platform errors and MissingPlugin become unavailable without message/details/cause. Malformed replies and native invalid-argument disagreements become invalidResponse. Native closed errors remain closed. There is no hidden timeout, abandoned accepted operation, log or error containing credential data.

## Closed local ABI and binary format

All arguments are exact maps including `handleId`. Read/clear add only `profileId`; replace adds `profileId`, present nullable `expectedRevision`, and byte-typed `value`; remove adds `profileId` and nonnull `expectedRevision`; close has only `handleId`. Missing/extra keys, wrong types and invalid bounds fail safely. Unknown methods are notImplemented. Replies are null or exactly `{revision: String, value: Uint8List}` for read, null or a 32hex string for replace, bool for remove, and null for clear/close. Native errors are only `credentialStoreClosed`, `credentialStoreUnavailable`, `credentialStoreInvalidArguments`, with fixed safe messages and no details.

Plain payload is ASCII `TFC1`, 16 revision bytes, then 1..65536 opaque bytes (21..65556 total). Unknown version, truncation, oversize and corruption are unavailable. No unreadable data is silently replaced/deleted; explicit clear recovers it. These are product format/concurrency controls, not workflow hashes or proofs.

## Android storage and engine ownership

The plugin has no new runtime dependency or permission. It uses compile SDK 36, minimum SDK 26, JVM 17, AGP 9.1.0 and Kotlin 2.4.0 with the existing built-in Kotlin switch. JUnit is test-only. It uses no Google SDK, network, biometric, StrongBox or external storage permission.

Each accepted operation owns and closes a private SQLite handle at `Context.getNoBackupFilesDir()/textus_authentication_v1/credentials.db`, separate from submission settings. Version 0 is initialized transactionally only when empty except for supported default `android_metadata`. Version 1 admits only the exact `credentials(profile TEXT PRIMARY KEY NOT NULL, sealed BLOB NOT NULL)` schema and supported metadata. Incompatible versions/schema fail without reset/migration. FULL synchronization and SQLite write transactions cover read/compare/decrypt/write, matching remove and clear; independent handles/processes cannot blindly overwrite new revisions.

AndroidKeyStore keys are AES-256/GCM/NoPadding, randomized-encryption-required, encrypt/decrypt only, with no biometric/hardware requirement. Alias is `org.textus.flutter.core.authentication.v1.` plus lowercase hex of exact UTF-8 profile bytes. This injective product locator preserves case independently of alias case semantics and is separate from Drive/submission. Keys are created only when actually writing a previously absent row; existing rows with lost/unusable keys fail closed. An existing alias can be reused for an absent row. There is no key export or plaintext fallback.

Sealed framing is ASCII `TFE1`, 12-byte IV, then ciphertext plus 128-bit GCM tag of the complete TFC1 payload (53..65588 bytes). AAD is UTF-8 `org.textus.flutter.core/authentication/v1\u0000` followed by exact profile ID. Frame sizes are validated before slicing/decrypting; selected SQLite blob lengths are checked before blob copying. Tamper, wrong profile, missing/wrong key, invalid version/tag fail safely. Remove/clear delete only the exact row and alias before reporting success. A cross-service rollback/failure can leave an unavailable encrypted row; it never recreates a lost key or claims successful clear.

An engine-owned serial ExecutorService runs IO off main. Retirement is independent of queue execution: close retires before its drain barrier, queued unissued operations check current ownership before IO and again under the storage transaction, and issued operations drain. Replies are main-thread, at most once, and values/errors from retired handles become closed. Detach retires before nonblocking executor shutdown, rejects queued unissued work, suppresses late replies, and lets captured operations release DB/transaction resources while draining. Other engines/handles are independent. Registration opens no file/KeyStore and caches no credential.

Platform references: [Android Keystore](https://developer.android.com/privacy-and-security/keystore), [Context.getNoBackupFilesDir](https://developer.android.com/reference/android/content/Context#getNoBackupFilesDir()). This storage location/policy does not promise arbitrary backup, rooted-device or egress protection.

## iOS storage and process ownership

Security generic-password items use service `org.textus.flutter.core.authentication.v1`, exact profile account and default App access group. Queries use `kSecAttrSynchronizable=false` and data-protection Keychain; writes use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Normal background access after first unlock is supported without requiring a biometric choice. There is no App Group/access-group expansion, iCloud synchronization or device-setting change.

TFC1 payload is stored in `kSecValueData`. Only `errSecItemNotFound` is absence; all other OSStatus/malformed payloads are unavailable. SecItemAdd/SecItemUpdate/SecItemDelete are atomic OS calls. One shared process-wide lock covers read/compare/mutation across every plugin/store instance; default access group does not create cross-App/extension sharing. Snapshots are detached, with no plaintext/session cache. Mismatch never mutates.

Each engine uses serial off-main IO plus the same retire-before-barrier, issued-work drain, exactly-once live reply and detached-reply suppression policy. The production plugin always creates the real Security/SecRandomCopyBytes implementation. Internal narrow Keychain/random boundaries permit Swift Package host tests to inject in-memory fakes; host tests never mutate the user's Mac Keychain. CocoaPods uses iOS 15.5/Swift 5 with Flutter and Security only; the host package excludes Flutter source.

Platform references: [AfterFirstUnlockThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessibleafterfirstunlockthisdeviceonly), [Keychain synchronizable attribute](https://developer.apple.com/documentation/security/ksecattrsynchronizable).

## Required integration and qualification limits

Future Core backend work still requires accepted production HTTP specimens, server-normalized credential codec, authoritative provider-account binding, refresh/current-session logout, and account-safe queue ownership. Before persistence it must check the current client operation. A retired/cancelled operation conditionally removes only its own late returned revision, then drains before publication. It must not use store.close as logout or cancellation rollback. No backend/issuer is supplied by this prerequisite.

Dart protocol specs exercise both mobile targets and unsupported platforms; JVM specs use synthetic JCE keys; Swift host specs inject fake Keychain/random sources. They do not establish OS/hardware or genuine authentication acceptance. The App's opt-in synthetic native probe covers actual platform channels and fresh-handle reopen in one process, with reserved absent-only slots and conditional owned-revision cleanup. Parent-selected signed builds, available physical Android/iPhone runs and normal App/data restoration remain separate gates. Missing physical hardware stays pending; no host fake substitutes for native or server proof.
