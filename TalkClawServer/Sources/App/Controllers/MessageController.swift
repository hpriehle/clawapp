import Vapor
import Fluent
import SharedModels

struct MessageController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let messages = routes.grouped("sessions", ":sessionId", "messages")
        messages.get(use: index)
        messages.post(use: create)
    }

    @Sendable
    func index(req: Request) async throws -> PaginatedResponse<MessageDTO> {
        guard let sessionId: UUID = req.parameters.get("sessionId") else {
            throw Abort(.badRequest, reason: "Missing session ID")
        }

        let page = (try? req.query.get(Int.self, at: "page")) ?? 1
        let perPage = min((try? req.query.get(Int.self, at: "perPage")) ?? 50, 100)

        let total = try await Message.query(on: req.db)
            .filter(\.$session.$id == sessionId)
            .count()

        let messages = try await Message.query(on: req.db)
            .filter(\.$session.$id == sessionId)
            .sort(\.$createdAt, .ascending)
            .range((page - 1) * perPage ..< page * perPage)
            .all()

        let dtos = try messages.map { try $0.toDTO() }

        return PaginatedResponse(items: dtos, total: total, page: page, perPage: perPage)
    }

    @Sendable
    func create(req: Request) async throws -> MessageDTO {
        guard let sessionId: UUID = req.parameters.get("sessionId") else {
            throw Abort(.badRequest, reason: "Missing session ID")
        }

        let sendReq = try req.content.decode(SendMessageRequest.self)

        // Save the user message
        let message = try Message(
            sessionId: sessionId,
            role: .user,
            content: .text(sendReq.content)
        )
        try await message.save(on: req.db)

        // Update session timestamp
        if let session = try await Session.find(sessionId, on: req.db) {
            session.lastMessageAt = Date()
            try await session.save(on: req.db)
        }

        // Forward to AI backend (non-blocking)
        let aiClient = req.application.aiClient
        let manager = req.application.clientWSManager
        let db = req.db
        Task {
            await aiClient.sendChat(
                sessionId: sessionId,
                content: sendReq.content,
                db: db,
                clientManager: manager
            )
        }

        return try message.toDTO()
    }
}