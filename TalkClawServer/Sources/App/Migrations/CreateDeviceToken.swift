import Fluent

struct CreateDeviceToken: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("device_tokens")
            .id()
            .field("token", .string, .required)
            .field("environment", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "token")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("device_tokens").delete()
    }
}
