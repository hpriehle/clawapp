import Vapor
import Fluent
import FluentSQLiteDriver
import FluentPostgresDriver
import Foundation

func configure(_ app: Application) throws {
    // MARK: - Database

    if let dbURL = Environment.get("DATABASE_URL") {
        try app.databases.use(DatabaseConfigurationFactory.postgres(url: dbURL), as: .psql)
    } else {
        app.databases.use(.sqlite(.file("talkclaw.sqlite")), as: .sqlite)
    }

    // MARK: - Migrations

    app.migrations.add(CreateUser())
    app.migrations.add(CreateSession())
    app.migrations.add(CreateMessage())
    app.migrations.add(SimplifyAuth())
    app.migrations.add(CreateWidgetTables())
    app.migrations.add(AddWidgetSize())
    try app.autoMigrate().wait()

    // MARK: - API Token

    let apiToken: String
    if let envToken = Environment.get("API_TOKEN"), !envToken.isEmpty {
        apiToken = envToken
    } else {
        let dataDir = Environment.get("DATA_DIR") ?? "."
        let tokenPath = dataDir + "/.talkclaw-token"
        if let saved = try? String(contentsOfFile: tokenPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !saved.isEmpty {
            apiToken = saved
        } else {
            let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
            apiToken = "clw_" + bytes.map { String(format: "%02x", $0) }.joined()
            try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
            try? apiToken.write(toFile: tokenPath, atomically: true, encoding: .utf8)
            app.logger.notice("=== Generated API token: \(apiToken) ===")
            app.logger.notice("Save this token — enter it in the TalkClaw iOS app to connect.")
        }
    }
    app.storage[APITokenKey.self] = apiToken

    // MARK: - Middleware

    // Static file serving (/static/talkclaw.css, /static/talkclaw-bridge.js)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    app.middleware.use(CORSMiddleware(configuration: .init(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .PATCH, .DELETE, .OPTIONS],
        allowedHeaders: [.authorization, .contentType, .accept]
    )))

    // MARK: - Services

    let channelClient = OpenClawChannelClient(
        baseURL: Environment.get("OPENCLAW_URL") ?? "",
        token: Environment.get("OPENCLAW_TOKEN") ?? "",
        logger: app.logger,
        httpClient: app.http.client.shared
    )
    app.storage[AIClientKey.self] = channelClient

    let clientManager = ClientWSManager()
    app.storage[ClientWSManagerKey.self] = clientManager

    // Sandbox client (Unix socket to isolated-vm sidecar)
    let sandboxSocket = Environment.get("SANDBOX_SOCKET") ?? "/sandbox/talkclaw-sandbox.sock"
    app.sandboxClient = SandboxClient(socketPath: sandboxSocket)

    // MARK: - Config

    let filesRoot = Environment.get("FILES_ROOT") ?? FileManager.default.currentDirectoryPath
    app.storage[FilesRootKey.self] = filesRoot

    // MARK: - Routes

    try routes(app)
}

// MARK: - Storage Keys

struct AIClientKey: StorageKey {
    typealias Value = OpenClawChannelClient
}

struct ClientWSManagerKey: StorageKey {
    typealias Value = ClientWSManager
}

struct FilesRootKey: StorageKey {
    typealias Value = String
}

struct APITokenKey: StorageKey {
    typealias Value = String
}

extension Application {
    var channelClient: OpenClawChannelClient {
        storage[AIClientKey.self]!
    }

    var clientWSManager: ClientWSManager {
        storage[ClientWSManagerKey.self]!
    }

    var filesRoot: String {
        storage[FilesRootKey.self]!
    }

    var apiToken: String {
        storage[APITokenKey.self]!
    }
}
