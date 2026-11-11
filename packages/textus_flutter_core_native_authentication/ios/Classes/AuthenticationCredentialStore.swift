import Foundation
import Security

/// Host specs inject this narrow boundary and never touch the user's Keychain.
protocol AuthenticationKeychain {
    func read(_ query: [String: Any]) -> (OSStatus, Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

private struct SystemAuthenticationKeychain: AuthenticationKeychain {
    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        return (status, value as? Data)
    }
    func add(_ attributes: [String: Any]) -> OSStatus { SecItemAdd(attributes as CFDictionary, nil) }
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
    func delete(_ query: [String: Any]) -> OSStatus { SecItemDelete(query as CFDictionary) }
}

struct AuthenticationCredentialEntry: CustomStringConvertible {
    private let revisionBytes: Data
    private let bytes: Data
    var revision: String { revisionBytes.map { String(format: "%02x", $0) }.joined() }
    var value: Data { Data([UInt8](bytes)) }
    var payload: Data { Data([84, 70, 67, 49]) + revisionBytes + bytes }
    var description: String { "AuthenticationCredentialEntry" }

    init(revision: Data, value: Data) throws {
        guard revision.count == 16, (1...CredentialStorePolicy.maximumValue).contains(value.count) else {
            throw CredentialStoreFailure.unavailable
        }
        revisionBytes = Data([UInt8](revision))
        bytes = Data([UInt8](value))
    }
    static func decode(_ payload: Data) throws -> AuthenticationCredentialEntry {
        guard (21...65556).contains(payload.count), payload.prefix(4) == Data([84, 70, 67, 49]) else {
            throw CredentialStoreFailure.unavailable
        }
        let owned = Data([UInt8](payload))
        return try AuthenticationCredentialEntry(revision: owned.subdata(in: 4..<20),
                                                 value: owned.subdata(in: 20..<owned.count))
    }
}

/// Shared across every plugin/store in this process. The default App access
/// group does not create cross-App or extension sharing.
final class AuthenticationCredentialStore {
    private static let serialization = NSLock()
    private let keychain: AuthenticationKeychain
    private let random: () throws -> Data

    init() {
        keychain = SystemAuthenticationKeychain()
        random = {
            var bytes = [UInt8](repeating: 0, count: 16)
            let status = bytes.withUnsafeMutableBytes {
                SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!)
            }
            guard status == errSecSuccess else { throw CredentialStoreFailure.unavailable }
            return Data(bytes)
        }
    }
    /// Internal host-test seam; the plugin always uses the production initializer.
    init(keychain: AuthenticationKeychain, random: @escaping () throws -> Data) {
        self.keychain = keychain
        self.random = random
    }

    private func read(_ query: [String: Any]) throws -> AuthenticationCredentialEntry? {
        let (status, value) = keychain.read(query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let value = value else { throw CredentialStoreFailure.unavailable }
        return try AuthenticationCredentialEntry.decode(value)
    }

    func execute(_ call: CredentialStoreCall, issue: () throws -> Void) throws -> Any? {
        Self.serialization.lock(); defer { Self.serialization.unlock() }
        do {
            try issue()
            guard let profile = call.profileId else { throw CredentialStoreFailure.invalidArguments }
            let query = CredentialStorePolicy.query(profile)
            switch call.method {
            case "read": return try read(query)
            case "replace":
                let previous = try read(query)
                guard previous?.revision == call.expectedRevision else { return nil }
                guard let value = call.value else { throw CredentialStoreFailure.invalidArguments }
                let entry = try AuthenticationCredentialEntry(revision: random(), value: value)
                let attributes = CredentialStorePolicy.attributes(entry.payload)
                let status: OSStatus
                if previous == nil {
                    status = keychain.add(query.merging(attributes) { _, new in new })
                } else {
                    status = keychain.update(query, attributes)
                }
                guard status == errSecSuccess else { throw CredentialStoreFailure.unavailable }
                return entry.revision
            case "remove":
                guard let previous = try read(query), previous.revision == call.expectedRevision else { return false }
                let status = keychain.delete(query)
                guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialStoreFailure.unavailable }
                return true
            case "clear":
                let status = keychain.delete(query)
                guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialStoreFailure.unavailable }
                return nil
            default: throw CredentialStoreFailure.invalidArguments
            }
        } catch let failure as CredentialStoreFailure { throw failure }
        catch { throw CredentialStoreFailure.unavailable }
    }
}
