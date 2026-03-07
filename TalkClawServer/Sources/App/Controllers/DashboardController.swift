import Vapor
import Fluent
import SharedModels

struct DashboardController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let dashboard = routes.grouped("dashboard")
        dashboard.get(use: index)
        dashboard.put(use: reorder)
        dashboard.group(":slug") { item in
            item.post(use: pin)
            item.delete(use: unpin)
            item.patch(use: updateItem)
        }
    }

    @Sendable
    func index(req: Request) async throws -> [DashboardItemDTO] {
        let items = try await DashboardLayout.query(on: req.db)
            .with(\.$widget)
            .sort(\.$position)
            .all()

        return items.map { item in
            let size = WidgetSize(rawValue: item.size) ?? .small
            return DashboardItemDTO(
                id: item.id!,
                widgetId: item.widget.id!,
                slug: item.widget.slug,
                title: item.widget.title,
                size: size,
                position: item.position
            )
        }
    }

    @Sendable
    func reorder(req: Request) async throws -> [DashboardItemDTO] {
        let reorderReq = try req.content.decode(ReorderDashboardRequest.self)

        // Delete all current layout entries
        try await DashboardLayout.query(on: req.db).delete()

        // Insert new layout in order
        for (index, item) in reorderReq.items.enumerated() {
            let layout = DashboardLayout(
                widgetId: item.widgetId,
                position: index,
                size: item.size.rawValue
            )
            try await layout.save(on: req.db)
        }

        return try await self.index(req: req)
    }

    @Sendable
    func pin(req: Request) async throws -> DashboardItemDTO {
        guard let slug = req.parameters.get("slug") else { throw Abort(.badRequest) }
        guard let widget = try await Widget.query(on: req.db)
            .filter(\.$slug == slug)
            .first() else {
            throw Abort(.notFound, reason: "Widget '\(slug)' not found")
        }

        // Check if already pinned
        let existing = try await DashboardLayout.query(on: req.db)
            .filter(\.$widget.$id == widget.id!)
            .first()
        guard existing == nil else {
            throw Abort(.conflict, reason: "Widget already pinned to dashboard")
        }

        let pinReq = try req.content.decode(PinWidgetRequest.self)

        // Get next position
        let maxPosition = try await DashboardLayout.query(on: req.db)
            .max(\.$position) ?? -1

        let layout = DashboardLayout(
            widgetId: widget.id!,
            position: maxPosition + 1,
            size: pinReq.size.rawValue
        )
        try await layout.save(on: req.db)

        return DashboardItemDTO(
            id: layout.id!,
            widgetId: widget.id!,
            slug: widget.slug,
            title: widget.title,
            size: pinReq.size,
            position: layout.position
        )
    }

    @Sendable
    func unpin(req: Request) async throws -> HTTPStatus {
        guard let slug = req.parameters.get("slug") else { throw Abort(.badRequest) }
        guard let widget = try await Widget.query(on: req.db)
            .filter(\.$slug == slug)
            .first() else {
            throw Abort(.notFound)
        }

        try await DashboardLayout.query(on: req.db)
            .filter(\.$widget.$id == widget.id!)
            .delete()

        return .noContent
    }

    @Sendable
    func updateItem(req: Request) async throws -> DashboardItemDTO {
        guard let slug = req.parameters.get("slug") else { throw Abort(.badRequest) }
        guard let widget = try await Widget.query(on: req.db)
            .filter(\.$slug == slug)
            .first() else {
            throw Abort(.notFound)
        }

        guard let layout = try await DashboardLayout.query(on: req.db)
            .filter(\.$widget.$id == widget.id!)
            .first() else {
            throw Abort(.notFound, reason: "Widget not pinned to dashboard")
        }

        let updateReq = try req.content.decode(UpdateDashboardItemRequest.self)
        layout.size = updateReq.size.rawValue
        layout.colSpan = updateReq.size.colSpan
        try await layout.save(on: req.db)

        return DashboardItemDTO(
            id: layout.id!,
            widgetId: widget.id!,
            slug: widget.slug,
            title: widget.title,
            size: updateReq.size,
            position: layout.position
        )
    }
}
