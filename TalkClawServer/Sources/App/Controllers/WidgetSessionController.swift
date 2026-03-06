import Vapor
import Fluent
import Foundation
import Crypto

struct WidgetSessionController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let ws = routes.grouped("widget-session")
        ws.post(use: issue)
        ws.delete(use: revoke)
    }

    @Sendable
    func issue(req: Request) async throws -> Response {
        let jti = UUID().uuidString
        let issuedAt = Date.now
        let expiresAt = issuedAt.addingTimeInterval(30 * 24 * 60 * 60) // 30 days

        // Store in DB
        let session = WidgetSession(jti: jti, issuedAt: issuedAt, expiresAt: expiresAt)
        try await session.save(on: req.db)

        // Create signed token
        let token = WidgetTokenSigner.sign(
            jti: jti,
            issuedAt: issuedAt,
            expiresAt: expiresAt,
            secret: req.application.apiToken
        )

        // Build response with Set-Cookie
        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .setCookie, value:
            "tc_widget_session=\(token); Path=/w/; HttpOnly; SameSite=Strict; Secure; Max-Age=\(30 * 24 * 60 * 60)"
        )
        try response.content.encode(["expiresAt": ISO8601DateFormatter().string(from: expiresAt)])

        return response
    }

    @Sendable
    func revoke(req: Request) async throws -> HTTPStatus {
        // Find and revoke active sessions
        let activeSessions = try await WidgetSession.query(on: req.db)
            .filter(\.$revokedAt == nil)
            .all()

        for session in activeSessions {
            session.revokedAt = .now
            try await session.save(on: req.db)
        }

        // Clear cookie
        let response = Response(status: .noContent)
        response.headers.replaceOrAdd(name: .setCookie, value:
            "tc_widget_session=; Path=/w/; HttpOnly; SameSite=Strict; Secure; Max-Age=0"
        )
        return .noContent
    }
}

// MARK: - Token Signing (HMAC-SHA256)

enum WidgetTokenSigner {
    /// Create a signed token: base64(payload).base64(signature)
    static func sign(jti: String, issuedAt: Date, expiresAt: Date, secret: String) -> String {
        let payload: [String: Any] = [
            "jti": jti,
            "iat": Int(issuedAt.timeIntervalSince1970),
            "exp": Int(expiresAt.timeIntervalSince1970),
            "sub": "widget-session"
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) else {
            return ""
        }

        let payloadB64 = jsonData.base64EncodedString()
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(payloadB64.utf8), using: key)
        let signatureB64 = Data(signature).base64EncodedString()

        return "\(payloadB64).\(signatureB64)"
    }

    /// Verify and decode a signed token. Returns the jti if valid.
    static func verify(token: String, secret: String) -> String? {
        let parts = token.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let payloadB64 = String(parts[0])
        let signatureB64 = String(parts[1])

        // Verify signature
        let key = SymmetricKey(data: Data(secret.utf8))
        guard let signatureData = Data(base64Encoded: signatureB64) else { return nil }
        let expectedCode = HMAC<SHA256>.authenticationCode(for: Data(payloadB64.utf8), using: key)
        guard Data(expectedCode) == signatureData else { return nil }

        // Decode payload
        guard let payloadData = Data(base64Encoded: payloadB64),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let jti = payload["jti"] as? String,
              let exp = payload["exp"] as? Int else {
            return nil
        }

        // Check expiry
        guard Date(timeIntervalSince1970: TimeInterval(exp)) > .now else { return nil }

        return jti
    }
}

// MARK: - Widget Cookie Auth Middleware

struct WidgetCookieMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Extract cookie
        guard let cookieValue = request.cookies["tc_widget_session"]?.string else {
            throw Abort(.unauthorized, reason: "Missing widget session cookie")
        }

        // Verify token signature and expiry
        guard let jti = WidgetTokenSigner.verify(token: cookieValue, secret: request.application.apiToken) else {
            throw Abort(.unauthorized, reason: "Invalid or expired widget session")
        }

        // Check DB for revocation
        let session = try await WidgetSession.query(on: request.db)
            .filter(\.$jti == jti)
            .first()

        guard let session, session.isValid else {
            throw Abort(.unauthorized, reason: "Widget session revoked")
        }

        return try await next.respond(to: request)
    }
}
