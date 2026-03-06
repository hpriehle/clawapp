import Vapor

/// Validates Bearer token against the server's configured API token.
/// No JWT, no signing — just a static token comparison.
struct BearerTokenMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard let auth = request.headers.bearerAuthorization else {
            throw Abort(.unauthorized, reason: "Missing authorization header")
        }
        guard auth.token == request.application.apiToken else {
            throw Abort(.unauthorized, reason: "Invalid token")
        }
        return try await next.respond(to: request)
    }
}
