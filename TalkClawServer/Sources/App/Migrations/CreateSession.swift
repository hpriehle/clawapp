import Fluent

struct CreateSession: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("sessions")
            .id()
            .field("user_id", .uuid, .required, .references("users", "id", onDelete: .cascade))
            .field("openclaw_session_id", .string)
            .field("title", .string)
            .field("is_pinned", .bool, .required, .custom("DEFAULT FALSE"))
            .field("is_archived", .bool, .required, .custom("DEFAULT FALSE"))
            .field("last_message_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("sessions").delete()
    }
}