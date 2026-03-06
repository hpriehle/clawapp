import Fluent
import Vapor

final class DashboardLayout: Model, Content, @unchecked Sendable {
    static let schema = "dashboard_layout"

    @ID(key: .id) var id: UUID?
    @Parent(key: "widget_id") var widget: Widget
    @Field(key: "position") var position: Int
    @Field(key: "col_span") var colSpan: Int
    @Field(key: "pinned_at") var pinnedAt: Date

    init() {}

    init(id: UUID? = nil, widgetId: UUID, position: Int, colSpan: Int = 1) {
        self.id = id
        self.$widget.id = widgetId
        self.position = position
        self.colSpan = colSpan
        self.pinnedAt = .now
    }
}
