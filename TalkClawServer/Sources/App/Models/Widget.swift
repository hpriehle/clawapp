import Fluent
import Vapor
import SharedModels

final class Widget: Model, Content, @unchecked Sendable {
    static let schema = "widgets"

    @ID(key: .id) var id: UUID?
    @Field(key: "slug") var slug: String
    @Field(key: "title") var title: String
    @Field(key: "description") var description: String
    @Field(key: "surface") var surface: String
    @Field(key: "html") var html: String
    @Field(key: "render_vars") var renderVarsJSON: Data
    @Field(key: "version") var version: Int
    @OptionalField(key: "created_by_session") var createdBySession: UUID?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    @Children(for: \.$widget) var routes: [WidgetRoute]

    init() {}

    init(
        id: UUID? = nil,
        slug: String,
        title: String,
        description: String,
        surface: WidgetSurface,
        html: String,
        renderVars: [String: String] = [:],
        createdBySession: UUID? = nil
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.description = description
        self.surface = surface.rawValue
        self.html = html
        self.renderVarsJSON = (try? JSONEncoder().encode(renderVars)) ?? Data("{}".utf8)
        self.version = 1
        self.createdBySession = createdBySession
    }

    var renderVars: [String: String] {
        get { (try? JSONDecoder().decode([String: String].self, from: renderVarsJSON)) ?? [:] }
        set { renderVarsJSON = (try? JSONEncoder().encode(newValue)) ?? Data("{}".utf8) }
    }

    var widgetSurface: WidgetSurface {
        WidgetSurface(rawValue: surface) ?? .inline
    }

    func toDTO() -> WidgetDTO {
        WidgetDTO(
            id: id!,
            slug: slug,
            title: title,
            description: description,
            surface: widgetSurface,
            html: html,
            renderVars: renderVars,
            version: version,
            createdBySession: createdBySession,
            createdAt: createdAt ?? .now,
            updatedAt: updatedAt ?? .now
        )
    }

    func toListItemDTO() -> WidgetListItemDTO {
        WidgetListItemDTO(
            id: id!,
            slug: slug,
            title: title,
            description: description,
            surface: widgetSurface,
            version: version,
            createdAt: createdAt ?? .now
        )
    }

    func toPayload() -> WidgetPayload {
        WidgetPayload(
            slug: slug,
            title: title,
            description: description,
            surface: widgetSurface,
            version: version
        )
    }
}
