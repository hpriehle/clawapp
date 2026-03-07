import Vapor
import Fluent
import SharedModels
import Foundation

/// Handles a single iOS client's WebSocket connection.
final class ClientWSHandler {
    private let ws: WebSocket
    private let manager: ClientWSManager
    private let channelClient: OpenClawChannelClient
    private let db: Database
    private let logger: Logger
    let connectionId = UUID()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(ws: WebSocket, manager: ClientWSManager, channelClient: OpenClawChannelClient, db: Database, logger: Logger) {
        self.ws = ws
        self.manager = manager
        self.channelClient = channelClient
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
        logger.info("WS received from \(connectionId): \(text.prefix(200))")
        guard let data = text.data(using: .utf8),
              let message = try? decoder.decode(WSMessage.self, from: data) else {
            logger.warning("Failed to decode WS message: \(text.prefix(100))")
            return
        }

        switch message {
        case .sendChat(let payload):
            // Auto-subscribe this connection and all others to the session
            manager.subscribe(connectionId: connectionId, sessionId: payload.sessionId)
            manager.subscribeAll(to: payload.sessionId)

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

                // Forward to AI backend via channel
                try await channelClient.sendToChannel(
                    sessionId: payload.sessionId,
                    content: payload.content
                )
            } catch {
                logger.error("Error handling sendChat: \(error)")
                await manager.send(.error(.init(code: 500, message: error.localizedDescription)), to: connectionId)
            }

        case .ping:
            await manager.send(.pong, to: connectionId)

        case .subscribe(let sessionId):
            manager.subscribe(connectionId: connectionId, sessionId: sessionId)
            logger.info("Client \(connectionId) subscribed to session \(sessionId)")

        case .unsubscribe(let sessionId):
            manager.unsubscribe(connectionId: connectionId, sessionId: sessionId)
            logger.info("Client \(connectionId) unsubscribed from session \(sessionId)")

        default:
            break
        }
    }
}
