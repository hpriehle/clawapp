import Fluent

struct CreateMessage: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("messages")
            .id()
            .field("session_id", .uuid, .required, .references("sessions", "id", onDelete: .cascade))
            .field("role", .string, .required)
            .field("content_json", .data, .required)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("messages").delete()
    }
}