import Foundation
import Security

enum CredentialStoreFailure: Error, CustomStringConvertible {
    case closed, unavailable, invalidArguments
    var code: String {
        switch self {
        case .closed: return "credentialStoreClosed"
        case .unavailable: return "credentialStoreUnavailable"
        case .invalidArguments: return "credentialStoreInvalidArguments"
        }
    }
    var message: String {
        switch self {
        case .closed: return "Credential store closed"
        case .unavailable: return "Credential store unavailable"
        case .invalidArguments: return "Invalid credential store arguments"
        }
    }
    var description: String { "CredentialStoreFailure(\(code))" }
}

struct CredentialStoreCall: CustomStringConvertible {
    let method: String
    let handleId: String
    let profileId: String?
    let expectedRevision: String?
    private let bytes: Data?
    var value: Data? { bytes.map { Data([UInt8]($0)) } }
    init(method: String, handleId: String, profileId: String? = nil,
         expectedRevision: String? = nil, value: Data? = nil) {
        self.method = method
        self.handleId = handleId
        self.profileId = profileId
        self.expectedRevision = expectedRevision
        self.bytes = value.map { Data([UInt8]($0)) }
    }
    var description: String { "CredentialStoreCall" }
}

enum CredentialStorePolicy {
    static let service = "org.textus.flutter.core.authentication.v1"
    static let maximumValue = 65536

    static func matches(_ value: String, _ pattern: String) -> Bool {
        let whole = NSRange(value.startIndex..<value.endIndex, in: value)
        return value.range(of: pattern, options: .regularExpression).map {
            NSRange($0, in: value) == whole
        } ?? false
    }
    static func profile(_ value: Any?) throws -> String {
        guard let value = value as? String,
              matches(value, "[A-Za-z0-9][A-Za-z0-9._-]{0,127}") else {
            throw CredentialStoreFailure.invalidArguments
        }
        return value
    }
    static func revision(_ value: Any?) throws -> String {
        guard let value = value as? String, matches(value, "[0-9a-f]{32}") else {
            throw CredentialStoreFailure.invalidArguments
        }
        return value
    }
    static func keys(_ method: String) -> Set<String>? {
        switch method {
        case "read", "clear": return ["handleId", "profileId"]
        case "replace": return ["handleId", "profileId", "expectedRevision", "value"]
        case "remove": return ["handleId", "profileId", "expectedRevision"]
        case "close": return ["handleId"]
        default: return nil
        }
    }
    /// The plugin converts only byte-typed Flutter data to owned Foundation Data.
    static func call(_ method: String, _ arguments: Any?) throws -> CredentialStoreCall {
        guard let keys = keys(method), let map = arguments as? [String: Any],
              Set(map.keys) == keys else { throw CredentialStoreFailure.invalidArguments }
        let handle = try revision(map["handleId"])
        let profileId: String?
        if method == "close" { profileId = nil }
        else { profileId = try profile(map["profileId"]) }
        var expected: String?
        if method == "remove" { expected = try revision(map["expectedRevision"]) }
        if method == "replace", !(map["expectedRevision"] is NSNull) {
            expected = try revision(map["expectedRevision"])
        }
        var bytes: Data?
        if method == "replace" {
            guard let value = map["value"] as? Data,
                  (1...maximumValue).contains(value.count) else {
                throw CredentialStoreFailure.invalidArguments
            }
            bytes = Data([UInt8](value))
        }
        return CredentialStoreCall(method: method, handleId: handle, profileId: profileId,
                                   expectedRevision: expected, value: bytes)
    }

    static func query(_ profileId: String) -> [String: Any] {
        // No access-group key: use this App's default group only.
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: profileId,
         kSecAttrSynchronizable as String: false,
         kSecUseDataProtectionKeychain as String: true]
    }
    static func attributes(_ payload: Data) -> [String: Any] {
        [kSecValueData as String: Data([UInt8](payload)),
         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
    }
}

/// A lock independent of the IO queue allows retirement before a queued barrier.
final class CredentialStoreLifetime {
    final class Operation {
        let handleId: String
        fileprivate var issued = false
        fileprivate var completed = false
        fileprivate init(_ handleId: String) { self.handleId = handleId }
    }
    private let lock = NSLock()
    private var live = true
    private var retired: Set<String> = []
    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body()
    }
    func accept(_ handleId: String) throws -> Operation {
        try locked {
            guard live, !retired.contains(handleId) else { throw CredentialStoreFailure.closed }
            return Operation(handleId)
        }
    }
    func retire(_ handleId: String) { locked { _ = retired.insert(handleId) } }
    func detach() { locked { live = false } }
    var isLive: Bool { locked { live } }
    func current(_ operation: Operation) -> Bool {
        locked { live && !retired.contains(operation.handleId) }
    }
    /// Called while the shared Keychain serialization boundary is held.
    func issue(_ operation: Operation) throws {
        try locked {
            guard live, !retired.contains(operation.handleId),
                  !operation.issued, !operation.completed else { throw CredentialStoreFailure.closed }
            operation.issued = true
        }
    }
    func complete(_ operation: Operation) -> Bool {
        locked {
            guard !operation.completed else { return false }
            operation.completed = true
            return live
        }
    }
}
