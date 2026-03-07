import Vapor
import Fluent
import SharedModels

struct WidgetLibraryController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let library = routes.grouped("widget-library")
        library.get(use: index)
        library.post(":slug", use: instantiate)
    }

    @Sendable
    func index(req: Request) async throws -> [WidgetTemplateDTO] {
        WidgetTemplateCatalog.templates.map(\.dto)
    }

    @Sendable
    func instantiate(req: Request) async throws -> DashboardItemDTO {
        guard let slug = req.parameters.get("slug") else {
            throw Abort(.badRequest)
        }

        guard let template = WidgetTemplateCatalog.find(slug: slug) else {
            throw Abort(.notFound, reason: "Template '\(slug)' not found")
        }

        let instantiateReq = try req.content.decode(InstantiateTemplateRequest.self)

        // Generate unique widget slug
        let randomSuffix = (0..<6).map { _ in
            let chars = "abcdefghijklmnopqrstuvwxyz0123456789"
            return String(chars.randomElement()!)
        }.joined()
        let widgetSlug = "\(template.slug)-\(randomSuffix)"

        // Create widget record
        let widget = Widget(
            slug: widgetSlug,
            title: template.title,
            description: template.description,
            surface: .dashboard,
            html: template.html
        )
        try await widget.save(on: req.db)

        // Get next dashboard position
        let maxPosition = try await DashboardLayout.query(on: req.db)
            .max(\.$position) ?? -1

        // Create dashboard layout entry
        let layout = DashboardLayout(
            widgetId: widget.id!,
            position: maxPosition + 1,
            size: instantiateReq.size.rawValue
        )
        try await layout.save(on: req.db)

        // Broadcast widget injection for live refresh
        let payload = widget.toPayload()
        await req.application.clientWSManager.broadcast(.widgetInjected(payload))

        return DashboardItemDTO(
            id: layout.id!,
            widgetId: widget.id!,
            slug: widget.slug,
            title: widget.title,
            size: instantiateReq.size,
            position: layout.position
        )
    }
}
