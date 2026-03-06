import Vapor
import NIOConcurrencyHelpers
import SharedModels
import Foundation

/// Manages all connected iOS client WebSocket connections.
/// Handles fan-out of messages from OpenClaw to all connected clients.
final class ClientWSManager: Sendable {
    private let connections = NIOLockedValueBox<[UUID: WebSocket]>([:])

    func add(_ id: UUID, ws: WebSocket) {
        connections.withLockedValue { $0[id] = ws }
    }

    func remove(_ id: UUID) {
        _ = connections.withLockedValue { $0.removeValue(forKey: id) }
    }

    /// Broadcast a WebSocket message to all connected clients.
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

    /// Send a message to a specific session's subscribers.
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