import Vapor
import Fluent
import SharedModels

struct RenderVarsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let vars = routes.grouped("widgets", ":slug", "vars")
        vars.patch(use: mergeVars)
        vars.put(use: replaceVars)
        vars.delete(":key", use: deleteVar)
    }

    @Sendable
    func mergeVars(req: Request) async throws -> WidgetDTO {
        let widget = try await findWidget(slug: req.parameters.get("slug"), on: req.db)
        let updateReq = try req.content.decode(UpdateRenderVarsRequest.self)

        var current = widget.renderVars
        for (key, value) in updateReq.vars {
            current[key] = value
        }
        widget.renderVars = current
        try await widget.save(on: req.db)

        return widget.toDTO()
    }

    @Sendable
    func replaceVars(req: Request) async throws -> WidgetDTO {
        let widget = try await findWidget(slug: req.parameters.get("slug"), on: req.db)
        let updateReq = try req.content.decode(UpdateRenderVarsRequest.self)

        widget.renderVars = updateReq.vars
        try await widget.save(on: req.db)

        return widget.toDTO()
    }

    @Sendable
    func deleteVar(req: Request) async throws -> WidgetDTO {
        let widget = try await findWidget(slug: req.parameters.get("slug"), on: req.db)
        guard let key = req.parameters.get("key") else { throw Abort(.badRequest) }

        var current = widget.renderVars
        current.removeValue(forKey: key)
        widget.renderVars = current
        try await widget.save(on: req.db)

        return widget.toDTO()
    }

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
