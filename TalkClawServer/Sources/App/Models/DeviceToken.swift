import Fluent
import Vapor

final class DeviceToken: Model, Content, @unchecked Sendable {
    static let schema = "device_tokens"

    @ID(key: .id) var id: UUID?
    @Field(key: "token") var token: String
    @Field(key: "environment") var environment: String
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    init() {}

    init(token: String, environment: String) {
        self.token = token
        self.environment = environment
    }
}
