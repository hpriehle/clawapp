import Vapor

func routes(_ app: Application) throws {
    let api = app.grouped("api", "v1")

    // Health (public)
    try api.register(collection: HealthController())

    // OpenClaw webhook (authenticated by webhook secret, not API token)
    try api.register(collection: OpenClawWebhookController())

    // Protected routes (bearer token)
    let protected = api.grouped(BearerTokenMiddleware())
    try protected.register(collection: SessionController())
    try protected.register(collection: MessageController())
    try protected.register(collection: FileController())
    try protected.register(collection: WidgetController())
    try protected.register(collection: RenderVarsController())
    try protected.register(collection: DashboardController())
    try protected.register(collection: WidgetSessionController())

    // Widget serving (token query param auth)
    try app.register(collection: WidgetServeController())

    // WebSocket (bearer token via query param)
    app.webSocket("api", "v1", "ws") { req, ws in
        guard let token = try? req.query.get(String.self, at: "token"),
              token == req.application.apiToken else {
            try? await ws.close(code: .policyViolation)
            return
        }

        let manager = req.application.clientWSManager
        let handler = ClientWSHandler(
            ws: ws,
            manager: manager,
            channelClient: req.application.channelClient,
            db: req.db,
            logger: req.logger
        )
        handler.start()
    }
}
