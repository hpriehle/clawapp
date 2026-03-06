import Vapor
import SharedModels

struct HealthController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("health", use: health)
    }

    @Sendable
    func health(req: Request) async throws -> HealthResponse {
        return HealthResponse(
            status: "ok",
            version: "0.1.0",
            openclawConnected: true
        )
    }
}