import Fluent
import SQLKit

struct AddWidgetSize: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("dashboard_layout")
            .field("size", .string, .required, .sql(.default("small")))
            .update()

        // Migrate existing data: col_span 1 → small, col_span >= 2 → medium
        if let sql = database as? SQLDatabase {
            try await sql.raw("UPDATE dashboard_layout SET size = CASE WHEN col_span >= 2 THEN 'medium' ELSE 'small' END")
                .run()
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema("dashboard_layout")
            .deleteField("size")
            .update()
    }
}
