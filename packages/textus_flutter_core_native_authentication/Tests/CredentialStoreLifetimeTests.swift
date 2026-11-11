import Foundation
import XCTest
@testable import AuthenticationContracts

final class CredentialStoreLifetimeTests: XCTestCase {
    func testRetirementRejectsQueuedWorkAndWithdrawsLateValuesWithoutAffectingOtherHandles() throws {
        // Given one issued call, one queued call, and a separate live handle.
        let owner = CredentialStoreLifetime()
        let issued = try owner.accept("first")
        let queued = try owner.accept("first")
        let other = try owner.accept("second")
        try owner.issue(issued)
        // When close retires before the serial queue's barrier can execute.
        owner.retire("first")
        XCTAssertThrowsError(try owner.issue(queued)) { error in
            XCTAssertEqual((error as? CredentialStoreFailure)?.code, "credentialStoreClosed")
        }
        XCTAssertThrowsError(try owner.accept("first"))
        try owner.issue(other)
        // Then late work drains exactly once while its value/error is withdrawn.
        XCTAssertFalse(owner.current(issued))
        XCTAssertTrue(owner.complete(issued))
        XCTAssertFalse(owner.complete(issued))
        XCTAssertTrue(owner.complete(queued))
        XCTAssertTrue(owner.current(other))
        XCTAssertTrue(owner.complete(other))
        XCTAssertFalse(owner.complete(other))
    }

    func testDetachSuppressesLateRepliesAndRetiresUnissuedWorkAcrossHandles() throws {
        // Given live issued/queued work before engine detach.
        let owner = CredentialStoreLifetime()
        let issued = try owner.accept("first")
        let queued = try owner.accept("second")
        try owner.issue(issued)
        // When detach retires synchronously before queue drain and release.
        owner.detach()
        XCTAssertThrowsError(try owner.issue(queued))
        XCTAssertThrowsError(try owner.accept("third"))
        // Then no result addresses the retired messenger, including duplicates.
        XCTAssertFalse(owner.isLive)
        XCTAssertFalse(owner.current(issued))
        XCTAssertFalse(owner.complete(issued))
        XCTAssertFalse(owner.complete(queued))
        XCTAssertFalse(owner.complete(issued))
        let anotherEngine = CredentialStoreLifetime()
        let independent = try anotherEngine.accept("first")
        try anotherEngine.issue(independent)
        XCTAssertTrue(anotherEngine.complete(independent))
    }
}
