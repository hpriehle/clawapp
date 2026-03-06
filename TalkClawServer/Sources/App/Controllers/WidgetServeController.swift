import Vapor
import Fluent
import SharedModels

struct WidgetServeController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let w = routes.grouped("w")
        let protected = w.grouped(WidgetCookieMiddleware())
        protected.get(":slug", use: serve)
        protected.on(.GET, ":slug", "**", use: proxyRoute)
        protected.on(.POST, ":slug", "**", use: proxyRoute)
        protected.on(.PUT, ":slug", "**", use: proxyRoute)
        protected.on(.DELETE, ":slug", "**", use: proxyRoute)
        protected.on(.PATCH, ":slug", "**", use: proxyRoute)
    }

    @Sendable
    func serve(req: Request) async throws -> Response {
        guard let slug = req.parameters.get("slug") else { throw Abort(.badRequest) }
        guard let widget = try await Widget.query(on: req.db)
            .filter(\.$slug == slug)
            .first() else {
            throw Abort(.notFound, reason: "Widget '\(slug)' not found")
        }

        // Parse TC:VARS defaults from HTML
        let defaults = WidgetSectionParser.parseVarsDefaults(from: widget.html)

        // Strip TC:ROUTES (not for the browser)
        var html = WidgetSectionParser.stripRoutes(from: widget.html)

        // Inject render vars (live overrides defaults)
        html = WidgetSectionParser.injectVars(defaults: defaults, live: widget.renderVars, into: html)

        let response = Response(status: .ok, body: .init(string: html))
        response.headers.contentType = .html
        response.headers.replaceOrAdd(name: "Cache-Control", value: "no-cache")
        return response
    }

    @Sendable
    func proxyRoute(req: Request) async throws -> Response {
        guard let slug = req.parameters.get("slug") else { throw Abort(.badRequest) }

        guard let widget = try await Widget.query(on: req.db)
            .filter(\.$slug == slug)
            .first(),
            let widgetId = widget.id else {
            throw Abort(.notFound, reason: "Widget '\(slug)' not found")
        }

        // Extract sub-path after /w/:slug
        let fullPath = req.url.path
        let prefix = "/w/\(slug)"
        let routePath = String(fullPath.dropFirst(prefix.count))

        // Parse request body
        var body: Any?
        if let bodyData = req.body.data {
            var buf = bodyData
            if let bytes = buf.readBytes(length: buf.readableBytes) {
                body = try? JSONSerialization.jsonObject(with: Data(bytes))
            }
        }

        // Parse query params
        var query: [String: String]?
        if let urlQuery = req.url.query, !urlQuery.isEmpty {
            var q = [String: String]()
            for pair in urlQuery.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
                    let val = String(parts[1]).removingPercentEncoding ?? String(parts[1])
                    q[key] = val
                }
            }
            if !q.isEmpty { query = q }
        }

        // Forward subset of headers
        var headers = [String: String]()
        for name in ["content-type", "accept", "authorization", "x-widget-token"] {
            if let val = req.headers.first(name: name) {
                headers[name] = val
            }
        }

        // Execute in sandbox
        let (status, json) = try await req.sandboxClient.execute(
            widgetId: widgetId.uuidString,
            method: req.method.string,
            path: routePath.isEmpty ? "/" : routePath,
            body: body,
            query: query,
            headers: headers.isEmpty ? nil : headers
        )

        let responseData = try JSONSerialization.data(withJSONObject: json)
        let response = Response(
            status: HTTPResponseStatus(statusCode: status),
            body: .init(data: responseData)
        )
        response.headers.contentType = .json
        return response
    }
}
