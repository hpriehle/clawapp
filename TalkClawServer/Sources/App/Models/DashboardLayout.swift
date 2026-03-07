import Fluent
import Vapor

final class DashboardLayout: Model, Content, @unchecked Sendable {
    static let schema = "dashboard_layout"

    @ID(key: .id) var id: UUID?
    @Parent(key: "widget_id") var widget: Widget
    @Field(key: "position") var position: Int
    @Field(key: "col_span") var colSpan: Int
    @Field(key: "size") var size: String
    @Field(key: "pinned_at") var pinnedAt: Date

    init() {}

    init(id: UUID? = nil, widgetId: UUID, position: Int, size: String = "small") {
        self.id = id
        self.$widget.id = widgetId
        self.position = position
        self.colSpan = size == "small" ? 1 : 2
        self.size = size
        self.pinnedAt = .now
    }
}
