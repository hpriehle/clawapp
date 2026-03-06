import Fluent
import Vapor

final class WidgetRoute: Model, Content, @unchecked Sendable {
    static let schema = "widget_routes"

    @ID(key: .id) var id: UUID?
    @Parent(key: "widget_id") var widget: Widget
    @Field(key: "method") var method: String
    @Field(key: "path") var path: String
    @Field(key: "handler_js") var handlerJS: String
    @Field(key: "description") var description: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, widgetId: UUID, method: String, path: String, handlerJS: String, description: String) {
        self.id = id
        self.$widget.id = widgetId
        self.method = method
        self.path = path
        self.handlerJS = handlerJS
        self.description = description
    }
}
