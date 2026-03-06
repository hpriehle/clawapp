import Fluent
import SQLKit

/// Removes the user_id foreign key constraint and makes it nullable.
/// Sessions are no longer scoped to users — the server is single-owner.
struct SimplifyAuth: AsyncMigration {
    func prepare(on database: Database) async throws {
        if let sql = database as? SQLDatabase {
            // Postgres: drop FK and make nullable
            try await sql.raw("""
                ALTER TABLE sessions
                DROP CONSTRAINT IF EXISTS "fk:sessions.user_id+users.id",
                ALTER COLUMN user_id DROP NOT NULL
                """).run()
        } else {
            // SQLite: no ALTER COLUMN support, but SQLite doesn't enforce FKs by default
            // The @OptionalParent change in the model is sufficient
        }
    }

    func revert(on database: Database) async throws {
        if let sql = database as? SQLDatabase {
            try await sql.raw("""
                ALTER TABLE sessions
                ALTER COLUMN user_id SET NOT NULL
                """).run()
        }
    }
}
