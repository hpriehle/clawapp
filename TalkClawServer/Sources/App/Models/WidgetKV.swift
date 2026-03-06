import Fluent
import Vapor

final class WidgetKV: Model, Content, @unchecked Sendable {
    static let schema = "widget_kv"

    @ID(key: .id) var id: UUID?
    @Field(key: "widget_id") var widgetId: UUID
    @Field(key: "key") var key: String
    @Field(key: "value") var valueJSON: Data
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(id: UUID? = nil, widgetId: UUID, key: String, valueJSON: Data) {
        self.id = id
        self.widgetId = widgetId
        self.key = key
        self.valueJSON = valueJSON
    }
}
