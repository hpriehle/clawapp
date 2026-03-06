import Fluent
import Vapor

final class WidgetErrorLog: Model, Content, @unchecked Sendable {
    static let schema = "widget_error_log"

    @ID(key: .id) var id: UUID?
    @Parent(key: "widget_id") var widget: Widget
    @Parent(key: "route_id") var route: WidgetRoute
    @Field(key: "error_message") var errorMessage: String
    @OptionalField(key: "stack_trace") var stackTrace: String?
    @Field(key: "request_path") var requestPath: String
    @OptionalField(key: "notified_session") var notifiedSession: UUID?
    @OptionalField(key: "resolved_at") var resolvedAt: Date?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}
}
