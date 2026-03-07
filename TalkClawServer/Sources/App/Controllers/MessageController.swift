import Vapor
import Fluent
import SharedModels

extension SearchResultDTO: @retroactive Content {}

struct MessageController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let messages = routes.grouped("sessions", ":sessionId", "messages")
        messages.get(use: index)
        messages.post(use: create)

        // Global search across all sessions
        routes.get("search", use: search)
    }

    @Sendable
    func index(req: Request) async throws -> PaginatedResponse<MessageDTO> {
        guard let sessionId: UUID = req.parameters.get("sessionId") else {
            throw Abort(.badRequest, reason: "Missing session ID")
        }

        let page = (try? req.query.get(Int.self, at: "page")) ?? 1
        let perPage = min((try? req.query.get(Int.self, at: "perPage")) ?? 50, 100)
        let query = try? req.query.get(String.self, at: "q")

        let allMessages = try await Message.query(on: req.db)
            .filter(\.$session.$id == sessionId)
            .sort(\.$createdAt, .ascending)
            .all()

        let dtos: [MessageDTO]
        if let query, !query.isEmpty {
            let lowered = query.lowercased()
            dtos = try allMessages.compactMap { msg -> MessageDTO? in
                let dto = try msg.toDTO()
                guard dto.searchableText.lowercased().contains(lowered) else { return nil }
                return dto
            }
        } else {
            dtos = try allMessages.map { try $0.toDTO() }
        }

        let total = dtos.count
        let start = (page - 1) * perPage
        let end = min(start + perPage, total)
        let paged = start < total ? Array(dtos[start..<end]) : []

        return PaginatedResponse(items: paged, total: total, page: page, perPage: perPage)
    }

    @Sendable
    func search(req: Request) async throws -> [SearchResultDTO] {
        guard let query = try? req.query.get(String.self, at: "q"), !query.isEmpty else {
            throw Abort(.badRequest, reason: "Missing search query 'q'")
        }

        let lowered = query.lowercased()
        let limit = min((try? req.query.get(Int.self, at: "limit")) ?? 50, 100)

        // Fetch all messages with their sessions
        let messages = try await Message.query(on: req.db)
            .with(\.$session)
            .sort(\.$createdAt, .descending)
            .all()

        var results: [SearchResultDTO] = []
        for msg in messages {
            guard results.count < limit else { break }
            let dto = try msg.toDTO()
            guard dto.searchableText.lowercased().contains(lowered) else { continue }
            results.append(SearchResultDTO(
                message: dto,
                sessionTitle: msg.session.title
            ))
        }

        return results
    }

    @Sendable
    func create(req: Request) async throws -> MessageDTO {
        guard let sessionId: UUID = req.parameters.get("sessionId") else {
            throw Abort(.badRequest, reason: "Missing session ID")
        }

        let sendReq = try req.content.decode(SendMessageRequest.self)
        let messageRole: MessageRole = (sendReq.role == "assistant") ? .assistant : .user

        // Save attachment messages (user messages only)
        if messageRole == .user {
            let baseURL = req.application.http.server.configuration.hostname == "0.0.0.0"
                ? "http://localhost:\(req.application.http.server.configuration.port)"
                : "http://\(req.application.http.server.configuration.hostname):\(req.application.http.server.configuration.port)"

            if let attachments = sendReq.attachments {
                for att in attachments {
                    let fileURL = URL(string: "\(baseURL)/api/v1/files/\(att.serverPath)")!
                    if att.mimeType.hasPrefix("image/") {
                        let imgMsg = try Message(
                            sessionId: sessionId,
                            role: .user,
                            content: .image(url: fileURL, caption: nil)
                        )
                        try await imgMsg.save(on: req.db)
                    } else {
                        let fileMsg = try Message(
                            sessionId: sessionId,
                            role: .user,
                            content: .file(name: att.filename, url: fileURL, size: att.size)
                        )
                        try await fileMsg.save(on: req.db)
                    }
                }
            }
        }

        let message = try Message(
            sessionId: sessionId,
            role: messageRole,
            content: .text(sendReq.content)
        )
        try await message.save(on: req.db)

        // Update session timestamp
        if let session = try await Session.find(sessionId, on: req.db) {
            session.lastMessageAt = Date()
            try await session.save(on: req.db)
        }

        let manager = req.application.clientWSManager

        if messageRole == .assistant {
            // Proactive push — deliver to iOS via WS, no AI call
            manager.subscribeAll(to: sessionId)
            let dto = try message.toDTO()
            await manager.sendToSession(.chatComplete(dto), sessionId: sessionId, logger: req.logger)
        } else {
            // Normal user message — forward to AI
            let channelClient = req.application.channelClient
            manager.subscribeAll(to: sessionId)
            Task {
                do {
                    try await channelClient.sendToChannel(
                        sessionId: sessionId,
                        content: sendReq.content
                    )
                } catch {
                    req.logger.error("Failed to send to channel: \(error)")
                    await manager.sendToSession(
                        .error(.init(code: 500, message: "Failed to reach AI: \(error.localizedDescription)")),
                        sessionId: sessionId,
                        logger: req.logger
                    )
                }
            }
        }

        return try message.toDTO()
    }
}