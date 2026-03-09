import Vapor
import Fluent
import SharedModels

struct DeviceTokenController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let tokens = routes.grouped("device-tokens")
        tokens.post(use: register)
        tokens.delete(use: unregister)
    }

    @Sendable
    func register(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(RegisterDeviceTokenRequest.self)

        // Upsert: delete any existing entry with the same token, then insert
        try await DeviceToken.query(on: req.db)
            .filter(\.$token == body.token)
            .delete()

        let deviceToken = DeviceToken(
            token: body.token,
            environment: body.environment
        )
        try await deviceToken.save(on: req.db)

        req.logger.info("Registered device token \(body.token.prefix(8))... (\(body.environment))")
        return .ok
    }

    @Sendable
    func unregister(req: Request) async throws -> HTTPStatus {
        let body = try req.content.decode(RegisterDeviceTokenRequest.self)

        try await DeviceToken.query(on: req.db)
            .filter(\.$token == body.token)
            .delete()

        req.logger.info("Unregistered device token \(body.token.prefix(8))...")
        return .ok
    }
}
