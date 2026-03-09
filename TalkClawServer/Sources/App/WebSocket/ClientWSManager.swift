import Vapor
import NIOConcurrencyHelpers
import SharedModels
import Foundation

/// Manages all connected iOS client WebSocket connections.
/// Tracks per-session subscriptions for targeted delivery.
final class ClientWSManager: Sendable {
    private let connections = NIOLockedValueBox<[UUID: WebSocket]>([:])
    private let subscriptions = NIOLockedValueBox<[UUID: Set<UUID>]>([:])  // connectionId → sessionIds

    func add(_ id: UUID, ws: WebSocket) {
        connections.withLockedValue { $0[id] = ws }
    }

    func remove(_ id: UUID) {
        _ = connections.withLockedValue { $0.removeValue(forKey: id) }
        _ = subscriptions.withLockedValue { $0.removeValue(forKey: id) }
    }

    func subscribe(connectionId: UUID, sessionId: UUID) {
        subscriptions.withLockedValue { subs in
            var set = subs[connectionId] ?? []
            set.insert(sessionId)
            subs[connectionId] = set
        }
    }

    func unsubscribe(connectionId: UUID, sessionId: UUID) {
        subscriptions.withLockedValue { subs in
            subs[connectionId]?.remove(sessionId)
        }
    }

    /// Subscribe ALL connected clients to a session (single-user system).
    /// Called when the server processes a REST-initiated chat, ensuring
    /// responses reach the iOS app even if client-side subscribe failed.
    func subscribeAll(to sessionId: UUID) {
        let allIds = connections.withLockedValue { Array($0.keys) }
        subscriptions.withLockedValue { subs in
            for connId in allIds {
                var set = subs[connId] ?? []
                set.insert(sessionId)
                subs[connId] = set
            }
        }
    }

    /// Send a message only to connections subscribed to the given session.
    /// Returns `true` if at least one client received the message.
    @discardableResult
    func sendToSession(_ message: WSMessage, sessionId: UUID, logger: Logger? = nil) async -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(message),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }

        // Find all connectionIds subscribed to this session
        let subscribedIds = subscriptions.withLockedValue { subs in
            subs.compactMap { (connId, sessionIds) in
                sessionIds.contains(sessionId) ? connId : nil
            }
        }

        if subscribedIds.isEmpty {
            logger?.info("No subscribed connections for session \(sessionId), message dropped")
            return false
        }

        let targetConnections = connections.withLockedValue { dict in
            subscribedIds.compactMap { id in dict[id] }
        }

        for ws in targetConnections {
            try? await ws.send(text)
        }
        return true
    }

    /// Broadcast a WebSocket message to all connected clients (session-agnostic).
    func broadcast(_ message: WSMessage) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(message),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        let allConnections = connections.withLockedValue { Array($0.values) }
        for ws in allConnections {
            try? await ws.send(text)
        }
    }

    /// Send a message to a specific connection.
    func send(_ message: WSMessage, to connectionId: UUID) async {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(message),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        let ws = connections.withLockedValue { $0[connectionId] }
        try? await ws?.send(text)
    }
}
