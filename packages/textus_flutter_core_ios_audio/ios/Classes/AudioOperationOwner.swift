import Foundation

/// Main-queue-confined logical generations and a single physical media lease.
/// Retiring a token fences permission, foreground and media callbacks forever.
final class AudioOperationOwner {
    struct Token: Equatable {
        let sessionID: String
        fileprivate let generation: UUID
    }

    enum Failure: Error {
        case busy
        case disposed
        case retired
    }

    private var operations: [String: Token] = [:]
    private var disposedSessions: Set<String> = []
    private var media: Token?

    func acquire(sessionID: String) throws -> Token {
        guard !disposedSessions.contains(sessionID) else { throw Failure.disposed }
        guard operations[sessionID] == nil else { throw Failure.busy }
        let token = Token(sessionID: sessionID, generation: UUID())
        operations[sessionID] = token
        return token
    }

    func isCurrent(_ token: Token) -> Bool {
        !disposedSessions.contains(token.sessionID) && operations[token.sessionID] == token
    }

    func acquireMedia(_ token: Token) throws {
        guard isCurrent(token) else { throw Failure.retired }
        guard media == nil || media == token else { throw Failure.busy }
        media = token
    }

    func ownsMedia(_ token: Token) -> Bool { isCurrent(token) && media == token }

    /// Returns whether this exact token owned media that must be deactivated.
    @discardableResult
    func retire(_ token: Token) -> Bool {
        guard isCurrent(token) else { return false }
        operations.removeValue(forKey: token.sessionID)
        let owned = media == token
        if owned { media = nil }
        return owned
    }

    /// A tombstone prevents every future acquire using this session identity.
    @discardableResult
    func dispose(sessionID: String) -> Bool {
        let owned = operations[sessionID].map { retire($0) } ?? false
        disposedSessions.insert(sessionID)
        return owned
    }

    func isDisposed(sessionID: String) -> Bool { disposedSessions.contains(sessionID) }
}
