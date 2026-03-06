import Vapor
import Fluent
import SharedModels

struct WidgetController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let widgets = routes.grouped("widgets")
        widgets.get(use: index)
        widgets.post(use: create)
        widgets.group(":slug") { widget in
            widget.get(use: show)
            widget.patch(use: update)
            widget.delete(use: delete)
            widget.get("versions", use: listVersions)
            widget.post("rollback", ":version", use: rollback)
        }
    }

    @Sendable
    func index(req: Request) async throws -> [WidgetListItemDTO] {
        var query = Widget.query(on: req.db)
        if let surface = try? req.query.get(String.self, at: "surface") {
            query = query.filter(\.$surface == surface)
        }
        let widgets = try await query.sort(\.$createdAt, .descending).all()
        return widgets.map { $0.toListItemDTO() }
    }

    @Sendable
    func create(req: Request) async throws -> WidgetDTO {
        let createReq = try req.content.decode(CreateWidgetRequest.self)

        // Check slug uniqueness
        let existing = try await Widget.query(on: req.db)
            .filter(\.$slug == createReq.slug)
            .first()
        guard existing == nil else {
            throw Abort(.conflict, reason: "Widget with slug '\(createReq.slug)' already exists")
        }

        let widget = Widget(
            slug: createReq.slug,
            title: createReq.title,
            description: createReq.description,
            surface: createReq.surface,
            html: createReq.html,
            createdBySession: createReq.sessionId
        )
        try await widget.save(on: req.db)

        // Extract and store routes from HTML
        let routeDefs = WidgetSectionParser.parseRoutes(from: createReq.html)
        for def in routeDefs {
            let route = WidgetRoute(
                widgetId: widget.id!,
                method: def.method,
                path: def.path,
                handlerJS: def.handler,
                description: def.description
            )
            try await route.save(on: req.db)
        }

        // Register routes with sandbox
        if !routeDefs.isEmpty {
            let sandboxRoutes = routeDefs.map { def -> [String: Any] in
                [
                    "routeId": UUID().uuidString,
                    "method": def.method,
                    "path": def.path,
                    "handlerJS": def.handler,
                ]
            }
            try? await req.sandboxClient.register(widgetId: widget.id!.uuidString, routes: sandboxRoutes)
        }

        // Create widget message in the originating chat session
        let payload = widget.toPayload()
        if let sessionId = createReq.sessionId {
            do {
                let widgetMsg = try Message(
                    sessionId: sessionId,
                    role: .assistant,
                    content: .widget(payload)
                )
                try await widgetMsg.save(on: req.db)

                // Update session timestamp
                if let session = try await Session.find(sessionId, on: req.db) {
                    session.lastMessageAt = Date()
                    try await session.save(on: req.db)
                }

                // Send complete message to subscribed clients
                let msgDTO = try widgetMsg.toDTO()
                await req.application.clientWSManager.sendToSession(
                    .chatComplete(msgDTO),
                    sessionId: sessionId,
                    logger: req.logger
                )
            } catch {
                req.logger.error("Failed to create widget message: \(error)")
            }
        }

        // Also broadcast widget injection event for dashboard refresh
        await req.application.clientWSManager.broadcast(.widgetInjected(payload))

        return widget.toDTO()
    }

    @Sendable
    func show(req: Request) async throws -> WidgetDTO {
        let widget = try await findWidget(slug: req.parameters.get("slug"), on: req.db)
        return widget.toDTO()
    }

    @Sendable
    func update(req: Request) async throws -> WidgetDTO {
        let widget = try await findWidget(slug: req.parameters.get("slug"), on: req.db)
        let updateReq = try req.content.decode(UpdateWidgetSectionsRequest.self)

        // Snapshot current version before modifying
        let snapshot = WidgetVersion(
            widgetId: widget.id!,
            version: widget.version,
            html: widget.html,
            renderVarsSnapshot: widget.renderVarsJSON
        )
        try await snapshot.save(on: req.db)

        // Merge sections into HTML
        widget.html = WidgetSectionParser.mergeSections(updateReq.sections, into: widget.html)
        widget.version += 1

        // If TC:ROUTES changed, re-extract and replace routes
        if updateReq.sections["TC:ROUTES"] != nil {
            // Delete existing routes
            try await WidgetRoute.query(on: req.db)
                .filter(\.$widget.$id == widget.id!)
                .delete()

            // Insert new routes
            let routeDefs = WidgetSectionParser.parseRoutes(from: widget.html)
            for def in routeDefs {
                let route = WidgetRoute(
                    widgetId: widget.id!,
                    method: def.method,
                    path: def.path,
                    handlerJS: def.handler,
                    description: def.description
                )
                try await route.save(on: req.db)
            }

            // Reload routes in sandbox
            if !routeDefs.isEmpty {
                let sandboxRoutes = routeDefs.map { def -> [String: Any] in
                    [
                        "routeId": UUID().uuidString,
                        "method": def.method,
                        "path": def.path,
                        "handlerJS": def.handler,
                    ]
                }
                try? await req.sandboxClient.reload(widgetId: widget.id!.uuidString, routes: sandboxRoutes)
            } else {
                try? await req.sandboxClient.unregister(widgetId: widget.id!.uuidString)
            }
        }

        try await widget.save(on: req.db)

        // Broadcast update event
        let payload = widget.toPayload()
        await req.application.clientWSManager.broadcast(.widgetUpdated(payload))

        return widget.toDTO()
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let widget = try await findWidget(slug: req.parameters.get("slug"), on: req.db)
        try? await req.sandboxClient.unregister(widgetId: widget.id!.uuidString)
        try await widget.delete(on: req.db)
        return .noContent
    }

    @Sendable
    func listVersions(req: Request) async throws -> [WidgetVersionDTO] {
        let widget = try await findWidget(slug: req.parameters.get("slug"), on: req.db)
        let versions = try await WidgetVersion.query(on: req.db)
            .filter(\.$widget.$id == widget.id!)
            .sort(\.$version, .descending)
            .all()
        return versions.map { v in
            WidgetVersionDTO(id: v.id!, version: v.version, snapshotAt: v.snapshotAt)
        }
    }

    @Sendable
    func rollback(req: Request) async throws -> WidgetDTO {
        let widget = try await findWidget(slug: req.parameters.get("slug"), on: req.db)
        guard let versionNum = req.parameters.get("version", as: Int.self) else {
            throw Abort(.badRequest, reason: "Invalid version number")
        }

        guard let snapshot = try await WidgetVersion.query(on: req.db)
            .filter(\.$widget.$id == widget.id!)
            .filter(\.$version == versionNum)
            .first() else {
            throw Abort(.notFound, reason: "Version \(versionNum) not found")
        }

        // Snapshot current before rollback
        let currentSnapshot = WidgetVersion(
            widgetId: widget.id!,
            version: widget.version,
            html: widget.html,
            renderVarsSnapshot: widget.renderVarsJSON
        )
        try await currentSnapshot.save(on: req.db)

        // Restore
        widget.html = snapshot.html
        widget.renderVarsJSON = snapshot.renderVarsSnapshot
        widget.version += 1

        // Re-extract routes
        try await WidgetRoute.query(on: req.db)
            .filter(\.$widget.$id == widget.id!)
            .delete()
        let routeDefs = WidgetSectionParser.parseRoutes(from: widget.html)
        for def in routeDefs {
            let route = WidgetRoute(
                widgetId: widget.id!,
                method: def.method,
                path: def.path,
                handlerJS: def.handler,
                description: def.description
            )
            try await route.save(on: req.db)
        }

        try await widget.save(on: req.db)

        let payload = widget.toPayload()
        await req.application.clientWSManager.broadcast(.widgetUpdated(payload))

        return widget.toDTO()
    }

    // MARK: - Helpers

    private func findWidget(slug: String?, on db: Database) async throws -> Widget {
        guard let slug else { throw Abort(.badRequest) }
        guard let widget = try await Widget.query(on: db)
            .filter(\.$slug == slug)
            .first() else {
            throw Abort(.notFound, reason: "Widget '\(slug)' not found")
        }
        return widget
    }
}
