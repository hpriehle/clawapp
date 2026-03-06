import Fluent

struct CreateWidgetTables: AsyncMigration {
    func prepare(on database: Database) async throws {
        // 1. widgets
        try await database.schema("widgets")
            .id()
            .field("slug", .string, .required)
            .field("title", .string, .required)
            .field("description", .string, .required)
            .field("surface", .string, .required)
            .field("html", .custom("TEXT"), .required)
            .field("render_vars", .data, .required)
            .field("version", .int, .required, .custom("DEFAULT 1"))
            .field("created_by_session", .uuid, .references("sessions", "id", onDelete: .setNull))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .unique(on: "slug")
            .create()

        // 2. widget_routes
        try await database.schema("widget_routes")
            .id()
            .field("widget_id", .uuid, .required, .references("widgets", "id", onDelete: .cascade))
            .field("method", .string, .required)
            .field("path", .string, .required)
            .field("handler_js", .custom("TEXT"), .required)
            .field("description", .string, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        // 3. widget_kv
        try await database.schema("widget_kv")
            .id()
            .field("widget_id", .uuid, .required, .references("widgets", "id", onDelete: .cascade))
            .field("key", .string, .required)
            .field("value", .data, .required)
            .field("updated_at", .datetime)
            .unique(on: "widget_id", "key")
            .create()

        // 4. dashboard_layout
        try await database.schema("dashboard_layout")
            .id()
            .field("widget_id", .uuid, .required, .references("widgets", "id", onDelete: .cascade))
            .field("position", .int, .required)
            .field("col_span", .int, .required, .custom("DEFAULT 1"))
            .field("pinned_at", .datetime, .required)
            .unique(on: "widget_id")
            .create()

        // 5. widget_versions
        try await database.schema("widget_versions")
            .id()
            .field("widget_id", .uuid, .required, .references("widgets", "id", onDelete: .cascade))
            .field("version", .int, .required)
            .field("html", .custom("TEXT"), .required)
            .field("render_vars_snapshot", .data, .required)
            .field("snapshot_at", .datetime, .required)
            .create()

        // 6. widget_error_log
        try await database.schema("widget_error_log")
            .id()
            .field("widget_id", .uuid, .required, .references("widgets", "id", onDelete: .cascade))
            .field("route_id", .uuid, .required, .references("widget_routes", "id", onDelete: .cascade))
            .field("error_message", .custom("TEXT"), .required)
            .field("stack_trace", .custom("TEXT"))
            .field("request_path", .string, .required)
            .field("notified_session", .uuid, .references("sessions", "id", onDelete: .setNull))
            .field("resolved_at", .datetime)
            .field("created_at", .datetime)
            .create()

        // 7. widget_sessions
        try await database.schema("widget_sessions")
            .id()
            .field("jti", .string, .required)
            .field("issued_at", .datetime, .required)
            .field("expires_at", .datetime, .required)
            .field("revoked_at", .datetime)
            .unique(on: "jti")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("widget_sessions").delete()
        try await database.schema("widget_error_log").delete()
        try await database.schema("widget_versions").delete()
        try await database.schema("dashboard_layout").delete()
        try await database.schema("widget_kv").delete()
        try await database.schema("widget_routes").delete()
        try await database.schema("widgets").delete()
    }
}
