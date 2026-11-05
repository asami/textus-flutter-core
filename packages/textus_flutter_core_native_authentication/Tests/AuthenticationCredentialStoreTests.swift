import Foundation
import Security
import XCTest
@testable import AuthenticationContracts

/// This fake is the only Keychain boundary used by all host specifications.
private final class MemoryAuthenticationKeychain: AuthenticationKeychain {
    var records: [String: Data] = [:]
    var queries: [[String: Any]] = []
    var writes: [[String: Any]] = []
    var forcedStatus: OSStatus?
    var mutations = 0
    var nextRevision: UInt8 = 0

    private func account(_ query: [String: Any]) -> String {
        query[kSecAttrAccount as String] as! String
    }
    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        queries.append(query)
        if let status = forcedStatus { return (status, nil) }
        guard let bytes = records[account(query)] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, Data([UInt8](bytes)))
    }
    func add(_ attributes: [String: Any]) -> OSStatus {
        queries.append(attributes); writes.append(attributes)
        if let status = forcedStatus { return status }
        let profile = account(attributes)
        guard records[profile] == nil else { return errSecDuplicateItem }
        records[profile] = Data([UInt8](attributes[kSecValueData as String] as! Data))
        mutations += 1
        return errSecSuccess
    }
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        queries.append(query); writes.append(attributes)
        if let status = forcedStatus { return status }
        let profile = account(query)
        guard records[profile] != nil else { return errSecItemNotFound }
        records[profile] = Data([UInt8](attributes[kSecValueData as String] as! Data))
        mutations += 1
        return errSecSuccess
    }
    func delete(_ query: [String: Any]) -> OSStatus {
        queries.append(query)
        if let status = forcedStatus { return status }
        guard records.removeValue(forKey: account(query)) != nil else { return errSecItemNotFound }
        mutations += 1
        return errSecSuccess
    }
}

final class AuthenticationCredentialStoreTests: XCTestCase {
    private let handle = "00112233445566778899aabbccddeeff"
    private func call(_ method: String, _ profile: String = "Slot", expected: String? = nil,
                      value: Data? = nil) throws -> CredentialStoreCall {
        var args: [String: Any] = ["handleId": handle]
        if method != "close" { args["profileId"] = profile }
        if method == "replace" || method == "remove" { args["expectedRevision"] = expected.map { $0 as Any } ?? NSNull() }
        if method == "replace" { args["value"] = value }
        return try CredentialStorePolicy.call(method, args)
    }
    private func store(_ keychain: MemoryAuthenticationKeychain) -> AuthenticationCredentialStore {
        return AuthenticationCredentialStore(keychain: keychain, random: {
            keychain.nextRevision &+= 1
            return Data(repeating: keychain.nextRevision, count: 16)
        })
    }
    private func execute(_ store: AuthenticationCredentialStore, _ call: CredentialStoreCall) throws -> Any? {
        try store.execute(call, issue: {})
    }
    private func unavailable(_ action: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try action(), file: file, line: line) { error in
            XCTAssertEqual((error as? CredentialStoreFailure)?.code, "credentialStoreUnavailable", file: file, line: line)
            XCTAssertFalse(String(describing: error).contains("PRIVATE"), file: file, line: line)
        }
    }

    func testCreateReadRotateStaleRemoveAndClearPreserveOtherProfile() throws {
        // Given two store instances sharing an injected in-memory Keychain only.
        let keychain = MemoryAuthenticationKeychain()
        let first = store(keychain)
        let second = store(keychain)
        XCTAssertNil(try execute(first, call("read")))
        var input = Data([1, 2, 3])
        let request = try call("replace", value: input)
        input[0] = 9
        // When one create succeeds, a conflicting create cannot replace it.
        let revision = try XCTUnwrap(execute(first, request) as? String)
        XCTAssertNil(try execute(second, call("replace", value: Data([9]))))
        let snapshot = try XCTUnwrap(execute(second, call("read")) as? AuthenticationCredentialEntry)
        XCTAssertEqual(snapshot.value, Data([1, 2, 3]))
        XCTAssertEqual(snapshot.revision, revision)
        var copy = snapshot.value
        copy[0] = 7
        XCTAssertEqual(snapshot.value, Data([1, 2, 3]))
        let other = try XCTUnwrap(execute(second, call("replace", "slot", value: Data([4]))) as? String)
        let rotated = try XCTUnwrap(execute(first, call("replace", expected: revision, value: Data([5]))) as? String)
        XCTAssertNotEqual(rotated, revision)
        let beforeStale = keychain.mutations
        XCTAssertNil(try execute(second, call("replace", expected: revision, value: Data([6]))))
        XCTAssertEqual(try execute(second, call("remove", expected: revision)) as? Bool, false)
        // Then stale writes/removes cannot erase a new revision or case-distinct profile.
        XCTAssertEqual(keychain.mutations, beforeStale)
        let current = try XCTUnwrap(execute(second, call("read")) as? AuthenticationCredentialEntry)
        XCTAssertEqual(current.revision, rotated)
        XCTAssertEqual(current.value, Data([5]))
        XCTAssertEqual(try execute(second, call("remove", expected: rotated)) as? Bool, true)
        XCTAssertEqual(try execute(second, call("remove", expected: rotated)) as? Bool, false)
        XCTAssertEqual((try execute(first, call("read", "slot")) as? AuthenticationCredentialEntry)?.revision, other)
        XCTAssertNil(try execute(first, call("clear", "slot")))
        XCTAssertNil(try execute(first, call("clear", "slot")))
        XCTAssertNil(try execute(first, call("read", "slot")))
        XCTAssertFalse(snapshot.description.contains(revision))
        XCTAssertFalse(snapshot.description.contains("1, 2, 3"))
    }

    func testAtomicCasAcrossStoreInstancesHasExactlyOneWinner() throws {
        // Given two plugin-equivalent stores and one shared old synthetic revision.
        let keychain = MemoryAuthenticationKeychain()
        let first = store(keychain)
        let second = store(keychain)
        let revision = try XCTUnwrap(execute(first, call("replace", value: Data([1]))) as? String)
        let proposals = try [call("replace", expected: revision, value: Data([2])),
                             call("replace", expected: revision, value: Data([3]))]
        let group = DispatchGroup()
        let resultsLock = NSLock()
        var results: [String?] = []
        var failures = 0
        // When both owners compare against the same old revision concurrently.
        for (index, owner) in [first, second].enumerated() {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                do {
                    let result = try owner.execute(proposals[index], issue: {}) as? String
                    resultsLock.lock(); results.append(result); resultsLock.unlock()
                } catch {
                    resultsLock.lock(); failures += 1; resultsLock.unlock()
                }
            }
        }
        group.wait()
        // Then the shared serialization boundary makes one change and one mismatch.
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.compactMap { $0 }.count, 1)
        XCTAssertEqual(keychain.mutations, 2)
        let current = try XCTUnwrap(execute(first, call("read")) as? AuthenticationCredentialEntry)
        XCTAssertEqual(current.revision, results.compactMap { $0 }.first)
        XCTAssertTrue(current.value == Data([2]) || current.value == Data([3]))
    }

    func testRetiredHandleCannotIssueQueuedMutationAndFreshHandlePreservesRecord() throws {
        // Given an issued create and a queued mutation from the same handle.
        let keychain = MemoryAuthenticationKeychain()
        let first = store(keychain)
        let second = store(keychain)
        let lifetime = CredentialStoreLifetime()
        let create = try lifetime.accept("first")
        let created = try XCTUnwrap(first.execute(call("replace", value: Data([1])), issue: {
            try lifetime.issue(create)
        }) as? String)
        let queued = try lifetime.accept("first")
        let mutations = keychain.mutations
        let queries = keychain.queries.count
        // When close retires before the queued call obtains the shared Keychain lock.
        lifetime.retire("first")
        XCTAssertThrowsError(try first.execute(call("replace", expected: created, value: Data([2])), issue: {
            try lifetime.issue(queued)
        })) { error in
            XCTAssertEqual((error as? CredentialStoreFailure)?.code, "credentialStoreClosed")
        }
        // Then no Keychain IO issues; the old result withdraws but persisted data stays.
        XCTAssertEqual(keychain.mutations, mutations)
        XCTAssertEqual(keychain.queries.count, queries)
        XCTAssertFalse(lifetime.current(create))
        XCTAssertTrue(lifetime.complete(create))
        XCTAssertTrue(lifetime.complete(queued))
        let read = try lifetime.accept("second")
        let snapshot = try XCTUnwrap(second.execute(call("read"), issue: {
            try lifetime.issue(read)
        }) as? AuthenticationCredentialEntry)
        XCTAssertEqual(snapshot.revision, created)
        XCTAssertEqual(snapshot.value, Data([1]))
        XCTAssertTrue(lifetime.current(read))
        XCTAssertTrue(lifetime.complete(read))
    }

    func testAbsentOsFailureAndCorruptRecordsStayDistinctUntilExplicitClear() throws {
        // Given an injected store with an absent slot and a separate retained profile.
        let keychain = MemoryAuthenticationKeychain()
        let owner = store(keychain)
        XCTAssertNil(try execute(owner, call("read")))
        let other = try XCTUnwrap(execute(owner, call("replace", "Other", value: Data([8]))) as? String)
        // When OS refusal occurs, no absent result or automatic mutation is allowed.
        keychain.forcedStatus = errSecInteractionNotAllowed
        let mutations = keychain.mutations
        unavailable { _ = try self.execute(owner, self.call("read")) }
        unavailable { _ = try self.execute(owner, self.call("replace", value: Data([1]))) }
        unavailable { _ = try self.execute(owner, self.call("clear")) }
        XCTAssertEqual(keychain.mutations, mutations)
        keychain.forcedStatus = nil
        var wrongVersion = try AuthenticationCredentialEntry(revision: Data(repeating: 1, count: 16), value: Data([1])).payload
        wrongVersion[3] = 50
        for corrupt in [Data(), Data(repeating: 0, count: 20), wrongVersion, Data(repeating: 0, count: 65557)] {
            keychain.records["Slot"] = corrupt
            unavailable { _ = try self.execute(owner, self.call("read")) }
            unavailable { _ = try self.execute(owner, self.call("replace", value: Data([2]))) }
            unavailable { _ = try self.execute(owner, self.call("remove", expected: self.handle)) }
            XCTAssertEqual(keychain.records["Slot"], corrupt)
            // Then only explicit slot clear recovers unreadable data, preserving neighbors.
            XCTAssertNil(try execute(owner, call("clear")))
            XCTAssertNil(try execute(owner, call("read")))
            XCTAssertEqual((try execute(owner, call("read", "Other")) as? AuthenticationCredentialEntry)?.revision, other)
        }
    }

    func testExactPayloadBoundsCopyIsolationAndRandomFailures() throws {
        // Given synthetic byte values at both admitted size boundaries.
        let keychain = MemoryAuthenticationKeychain()
        let owner = store(keychain)
        for size in [1, 65536] {
            let value = Data(repeating: 7, count: size)
            let revision = try XCTUnwrap(execute(owner, call("replace", value: value)) as? String)
            // When the actual TFC1 payload is decoded through the store boundary.
            let entry = try XCTUnwrap(execute(owner, call("read")) as? AuthenticationCredentialEntry)
            XCTAssertEqual(entry.revision, revision)
            XCTAssertEqual(entry.value, value)
            XCTAssertEqual(keychain.records["Slot"]?.count, size + 20)
            // Then complete values survive and cleanup removes only that revision.
            XCTAssertEqual(try execute(owner, call("remove", expected: entry.revision)) as? Bool, true)
        }
        let invalidRandom = AuthenticationCredentialStore(keychain: keychain, random: { Data(repeating: 1, count: 15) })
        unavailable { _ = try self.execute(invalidRandom, self.call("replace", value: Data([1]))) }
        let throwingRandom = AuthenticationCredentialStore(keychain: keychain, random: {
            throw NSError(domain: "PRIVATE_RANDOM", code: -1)
        })
        unavailable { _ = try self.execute(throwingRandom, self.call("replace", value: Data([1]))) }
        XCTAssertNil(keychain.records["Slot"])
        unavailable { _ = try AuthenticationCredentialEntry(revision: Data(count: 15), value: Data([1])) }
        unavailable { _ = try AuthenticationCredentialEntry(revision: Data(count: 16), value: Data()) }
        unavailable { _ = try AuthenticationCredentialEntry(revision: Data(count: 16), value: Data(count: 65537)) }
    }

    func testAllOperationsUseDefaultGroupNoSyncAndDeviceBoundBackgroundPolicy() throws {
        // Given a fake collecting the actual query/attribute dictionaries.
        let keychain = MemoryAuthenticationKeychain()
        let owner = store(keychain)
        let created = try XCTUnwrap(execute(owner, call("replace", value: Data([1]))) as? String)
        // When read, rotate and clear exercise every Keychain mutation kind.
        _ = try execute(owner, call("read"))
        _ = try execute(owner, call("replace", expected: created, value: Data([2])))
        _ = try execute(owner, call("clear"))
        // Then every query is exact-profile/default-group/data-protection/no-sync.
        XCTAssertFalse(keychain.queries.isEmpty)
        for query in keychain.queries {
            XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
            XCTAssertEqual(query[kSecAttrService as String] as? String, CredentialStorePolicy.service)
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "Slot")
            XCTAssertEqual(query[kSecAttrSynchronizable as String] as? Bool, false)
            XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
            XCTAssertNil(query[kSecAttrAccessGroup as String])
        }
        XCTAssertEqual(keychain.writes.count, 2)
        for attributes in keychain.writes {
            XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String,
                           kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        }
    }

    func testClosedAbiRejectsUnsafeProfilesRevisionsTypesAndExtraFields() throws {
        // Given complete maps containing only synthetic bytes.
        let valid: [String: Any] = ["handleId": handle, "profileId": "Slot", "expectedRevision": NSNull(), "value": Data([1])]
        XCTAssertNotNil(try CredentialStorePolicy.call("replace", valid).value)
        // When any key is missing/extra or an exact input is invalid.
        var cases: [[String: Any]] = valid.keys.map { key in var map = valid; map.removeValue(forKey: key); return map }
        var extra = valid; extra["extra"] = true; cases.append(extra)
        for profile in ["", ".slot", "slot\n", "a/b", "é", String(repeating: "a", count: 129)] {
            var map = valid; map["profileId"] = profile; cases.append(map)
        }
        for revision in ["", String(repeating: "A", count: 32), handle + "\n"] {
            var map = valid; map["expectedRevision"] = revision; cases.append(map)
        }
        for value in [Data(), Data(count: 65537), [1, 2], "PRIVATE"] as [Any] {
            var map = valid; map["value"] = value; cases.append(map)
        }
        for map in cases {
            XCTAssertThrowsError(try CredentialStorePolicy.call("replace", map)) { error in
                XCTAssertEqual((error as? CredentialStoreFailure)?.code, "credentialStoreInvalidArguments")
                XCTAssertFalse(String(describing: error).contains("PRIVATE"))
            }
        }
        // Then allowed bounds/case remain exact and close has no profile/value ABI.
        XCTAssertEqual(try CredentialStorePolicy.profile(String(repeating: "Z", count: 128)).count, 128)
        XCTAssertNotEqual(CredentialStorePolicy.query("Slot")[kSecAttrAccount as String] as? String,
                          CredentialStorePolicy.query("slot")[kSecAttrAccount as String] as? String)
        XCTAssertThrowsError(try CredentialStorePolicy.call("close", ["handleId": handle, "profileId": "Slot"]))
        XCTAssertThrowsError(try CredentialStorePolicy.call("remove", ["handleId": handle, "profileId": "Slot", "expectedRevision": NSNull()]))
        XCTAssertNil(CredentialStorePolicy.keys("login"))
    }
}
