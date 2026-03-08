import Vapor

func routes(_ app: Application) throws {
    let api = app.grouped("api", "v1")

    // Health (public)
    try api.register(collection: HealthController())

    // Protected routes (bearer token)
    let protected = api.grouped(BearerTokenMiddleware())
    try protected.register(collection: SessionController())
    try protected.register(collection: MessageController())
    try protected.register(collection: FileController())
    try protected.register(collection: WidgetController())
    try protected.register(collection: RenderVarsController())
    try protected.register(collection: DashboardController())
    try protected.register(collection: WidgetLibraryController())
    try protected.register(collection: WidgetSessionController())

    // Widget serving (token query param auth)
    try app.register(collection: WidgetServeController())

    // Setup page (public) — visit /setup on your phone to connect the app
    app.get("setup") { req -> Response in
        let token = req.application.apiToken
        let host = req.headers.first(name: .host) ?? "localhost:8080"
        let scheme = req.headers.first(name: "X-Forwarded-Proto") ?? (host.contains("localhost") ? "http" : "https")
        let serverURL = "\(scheme)://\(host)"

        let configJSON = "{\"server\":\"\(serverURL)\",\"token\":\"\(token)\"}"
        let configB64 = Data(configJSON.utf8).base64EncodedString()
        let deepLink = "talkclaw://setup?config=\(configB64)"

        let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>TalkClaw Setup</title>
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            background: #0A0A0A; color: #fff;
            display: flex; justify-content: center; align-items: center;
            min-height: 100vh; padding: 24px;
          }
          .card {
            background: #161616; border: 1px solid rgba(255,255,255,0.1);
            border-radius: 22px; padding: 40px 32px; text-align: center;
            max-width: 380px; width: 100%;
          }
          h1 { font-size: 28px; font-weight: 700; margin-bottom: 8px; }
          p { color: rgba(255,255,255,0.5); font-size: 15px; margin-bottom: 32px; }
          .btn {
            display: block; width: 100%; padding: 16px;
            background: #5B9EF5; color: #fff; font-size: 17px; font-weight: 600;
            border: none; border-radius: 12px; cursor: pointer;
            text-decoration: none; margin-bottom: 16px;
          }
          .btn:active { opacity: 0.8; }
          .details {
            background: #0E0E0E; border-radius: 12px; padding: 16px;
            text-align: left; font-size: 13px; margin-top: 24px;
          }
          .details dt { color: rgba(255,255,255,0.3); font-size: 11px; text-transform: uppercase; letter-spacing: 1.2px; margin-bottom: 4px; }
          .details dd { color: rgba(255,255,255,0.9); word-break: break-all; margin-bottom: 12px; font-family: monospace; }
          .details dd:last-child { margin-bottom: 0; }
        </style>
        </head>
        <body>
        <div class="card">
          <h1>TalkClaw</h1>
          <p>Connect your app to this server</p>
          <a class="btn" href="\(deepLink)">Open in TalkClaw</a>
          <div class="details">
            <dl>
              <dt>Server</dt>
              <dd>\(serverURL)</dd>
              <dt>API Key</dt>
              <dd>\(token)</dd>
            </dl>
          </div>
        </div>
        </body>
        </html>
        """

        return Response(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: .init(string: html)
        )
    }

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
