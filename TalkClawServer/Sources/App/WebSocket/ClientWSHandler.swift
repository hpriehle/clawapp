import Vapor
import Fluent
import SharedModels
import Foundation

/// Handles a single iOS client's WebSocket connection.
final class ClientWSHandler {
    private let ws: WebSocket
    private let manager: ClientWSManager
    private let aiClient: OpenClawHTTPClient
    private let db: Database
    private let logger: Logger
    private let connectionId = UUID()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(ws: WebSocket, manager: ClientWSManager, aiClient: OpenClawHTTPClient, db: Database, logger: Logger) {
        self.ws = ws
        self.manager = manager
        self.aiClient = aiClient
        self.db = db
        self.logger = logger
    }

    func start() {
        manager.add(connectionId, ws: ws)
        logger.info("Client connected: \(connectionId)")

        ws.onText { [weak self] _, text in
            guard let self else { return }
            await self.handleMessage(text)
        }

        ws.onClose.whenComplete { [weak self] _ in
            guard let self else { return }
            self.manager.remove(self.connectionId)
            self.logger.info("Client disconnected: \(self.connectionId)")
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8),
              let message = try? decoder.decode(WSMessage.self, from: data) else {
            logger.warning("Failed to decode WS message: \(text.prefix(100))")
            return
        }

        switch message {
        case .sendChat(let payload):
            // Save user message
            do {
                let userMsg = try Message(
                    sessionId: payload.sessionId,
                    role: .user,
                    content: .text(payload.content)
                )
                try await userMsg.save(on: db)

                // Update session timestamp
                if let session = try await Session.find(payload.sessionId, on: db) {
                    session.lastMessageAt = Date()
                    try await session.save(on: db)
                }

                // Forward to AI backend
                await aiClient.sendChat(
                    sessionId: payload.sessionId,
                    content: payload.content,
                    db: db,
                    clientManager: manager
                )
            } catch {
                logger.error("Error handling sendChat: \(error)")
                await manager.send(.error(.init(code: 500, message: error.localizedDescription)), to: connectionId)
            }

        case .ping:
            await manager.send(.pong, to: connectionId)

        case .subscribe, .unsubscribe:
            // TODO: Track per-session subscriptions for targeted delivery
            break

        default:
            // Server-to-client messages shouldn't be sent by client
            break
        }
    }
}