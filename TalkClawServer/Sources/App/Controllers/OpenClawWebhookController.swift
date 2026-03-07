import Vapor
import Fluent
import SharedModels

struct OpenClawWebhookController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let webhook = routes.grouped("webhooks", "openclaw")
            .grouped(WebhookAuthMiddleware())
        webhook.post(use: handleWebhook)
    }

    @Sendable
    func handleWebhook(req: Request) async throws -> HTTPStatus {
        let payload = try req.content.decode(ChannelWebhookPayload.self)
        let manager = req.application.clientWSManager

        switch payload.type {
        case "chat_delta":
            guard let delta = payload.delta, let messageId = payload.messageId else {
                throw Abort(.badRequest, reason: "chat_delta requires delta and messageId")
            }
            let deltaPayload = WSMessage.ChatDeltaPayload(
                sessionId: payload.sessionId,
                delta: delta,
                messageId: messageId
            )
            await manager.sendToSession(.chatDelta(deltaPayload), sessionId: payload.sessionId, logger: req.logger)

        case "chat_complete":
            guard let text = payload.text, let messageId = payload.messageId else {
                throw Abort(.badRequest, reason: "chat_complete requires text and messageId")
            }
            let message = try Message(
                id: messageId,
                sessionId: payload.sessionId,
                role: .assistant,
                content: .text(text)
            )
            try await message.save(on: req.db)

            if let session = try await Session.find(payload.sessionId, on: req.db) {
                session.lastMessageAt = Date()
                try await session.save(on: req.db)
            }

            // Ensure all connected iOS clients receive this message,
            // even for proactive/cron pushes where the client hasn't explicitly subscribed
            manager.subscribeAll(to: payload.sessionId)

            let dto = try message.toDTO()
            await manager.sendToSession(.chatComplete(dto), sessionId: payload.sessionId, logger: req.logger)

            // Auto-title (fire-and-forget)
            let db = req.db
            let sessionId = payload.sessionId
            let logger = req.logger
            Task {
                try? await autoTitleIfNeeded(sessionId: sessionId, db: db, manager: manager, logger: logger)
            }

        case "chat_error":
            let errorMsg = payload.error ?? "Unknown AI error"
            await manager.sendToSession(
                .error(.init(code: 500, message: errorMsg)),
                sessionId: payload.sessionId,
                logger: req.logger
            )

        default:
            req.logger.warning("Unknown webhook type: \(payload.type)")
        }

        return .ok
    }

    private func autoTitleIfNeeded(
        sessionId: UUID,
        db: Database,
        manager: ClientWSManager,
        logger: Logger
    ) async throws {
        guard let session = try await Session.find(sessionId, on: db),
              session.title == nil || session.title?.isEmpty == true else {
            return
        }
        let firstUserMsg = try await Message.query(on: db)
            .filter(\.$session.$id == sessionId)
            .filter(\.$role == "user")
            .sort(\.$createdAt, .ascending)
            .first()
        if let firstMsg = firstUserMsg, let text = firstMsg.textContent {
            session.title = String(text.prefix(50))
            try await session.save(on: db)
            let lastMsg = try await Message.query(on: db)
                .filter(\.$session.$id == sessionId)
                .sort(\.$createdAt, .descending)
                .first()
            let preview: String? = try lastMsg.map { msg in
                let content = try JSONDecoder().decode(MessageContent.self, from: msg.contentJSON)
                return String(content.previewText.prefix(100))
            }
            await manager.sendToSession(.sessionUpdated(session.toDTO(lastMessagePreview: preview)), sessionId: sessionId, logger: logger)
        }
    }
}

// MARK: - Webhook Payload

struct ChannelWebhookPayload: Content {
    let type: String
    let sessionId: UUID
    let messageId: UUID?
    let delta: String?
    let text: String?
    let error: String?
}

// MARK: - Webhook Auth Middleware

struct WebhookAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let auth = request.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Missing webhook authorization")
        }
        guard auth.token == request.application.webhookSecret else {
            throw Abort(.unauthorized, reason: "Invalid webhook secret")
        }
        return try await next.respond(to: request)
    }
}
