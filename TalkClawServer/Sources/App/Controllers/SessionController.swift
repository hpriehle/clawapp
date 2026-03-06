import Vapor
import Fluent
import SharedModels

struct SessionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let sessions = routes.grouped("sessions")
        sessions.get(use: index)
        sessions.post(use: create)
        sessions.group(":sessionId") { session in
            session.get(use: show)
            session.patch(use: update)
            session.delete(use: delete)
        }
    }

    @Sendable
    func index(req: Request) async throws -> [SessionDTO] {
        let sessions = try await Session.query(on: req.db)
            .sort(\.$lastMessageAt, .descending)
            .all()

        var dtos: [SessionDTO] = []
        for session in sessions {
            let lastMessage = try await Message.query(on: req.db)
                .filter(\.$session.$id == session.id!)
                .sort(\.$createdAt, .descending)
                .first()
            let preview = lastMessage?.textContent.map { String($0.prefix(100)) }
            dtos.append(session.toDTO(lastMessagePreview: preview))
        }
        return dtos
    }

    @Sendable
    func create(req: Request) async throws -> SessionDTO {
        let createReq = try req.content.decode(CreateSessionRequest.self)
        let session = Session(title: createReq.title)
        try await session.save(on: req.db)
        return session.toDTO()
    }

    @Sendable
    func show(req: Request) async throws -> SessionDTO {
        guard let session = try await Session.find(req.parameters.get("sessionId"), on: req.db) else {
            throw Abort(.notFound)
        }
        return session.toDTO()
    }

    @Sendable
    func update(req: Request) async throws -> SessionDTO {
        guard let session = try await Session.find(req.parameters.get("sessionId"), on: req.db) else {
            throw Abort(.notFound)
        }

        let updateReq = try req.content.decode(UpdateSessionRequest.self)

        if let title = updateReq.title { session.title = title }
        if let isPinned = updateReq.isPinned { session.isPinned = isPinned }
        if let isArchived = updateReq.isArchived { session.isArchived = isArchived }

        try await session.save(on: req.db)
        return session.toDTO()
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        guard let session = try await Session.find(req.parameters.get("sessionId"), on: req.db) else {
            throw Abort(.notFound)
        }
        try await session.delete(on: req.db)
        return .noContent
    }
}
