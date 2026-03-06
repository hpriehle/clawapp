import Fluent
import Vapor

final class WidgetVersion: Model, Content, @unchecked Sendable {
    static let schema = "widget_versions"

    @ID(key: .id) var id: UUID?
    @Parent(key: "widget_id") var widget: Widget
    @Field(key: "version") var version: Int
    @Field(key: "html") var html: String
    @Field(key: "render_vars_snapshot") var renderVarsSnapshot: Data
    @Field(key: "snapshot_at") var snapshotAt: Date

    init() {}

    init(id: UUID? = nil, widgetId: UUID, version: Int, html: String, renderVarsSnapshot: Data) {
        self.id = id
        self.$widget.id = widgetId
        self.version = version
        self.html = html
        self.renderVarsSnapshot = renderVarsSnapshot
        self.snapshotAt = .now
    }
}
