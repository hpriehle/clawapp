import Vapor
import Fluent
import APNS
import APNSCore

struct PushNotificationService: Sendable {
    let sandboxClient: APNSClient<JSONDecoder, JSONEncoder>
    let productionClient: APNSClient<JSONDecoder, JSONEncoder>
    let topic: String
    let logger: Logger

    init(
        sandboxClient: APNSClient<JSONDecoder, JSONEncoder>,
        productionClient: APNSClient<JSONDecoder, JSONEncoder>,
        topic: String,
        logger: Logger
    ) {
        self.sandboxClient = sandboxClient
        self.productionClient = productionClient
        self.topic = topic
        self.logger = logger
    }

    func sendPush(title: String, body: String, sessionId: UUID, db: Database) async {
        do {
            let tokens = try await DeviceToken.query(on: db).all()
            guard !tokens.isEmpty else {
                logger.info("No device tokens registered, skipping push")
                return
            }

            let alert = APNSAlertNotification(
                alert: .init(title: .raw(title), body: .raw(body)),
                expiration: .immediately,
                priority: .immediately,
                topic: topic,
                payload: PushPayload(sessionId: sessionId.uuidString.lowercased()),
                sound: .default,
                threadID: sessionId.uuidString.lowercased()
            )

            for token in tokens {
                let client = token.environment == "sandbox" ? sandboxClient : productionClient
                do {
                    try await client.sendAlertNotification(
                        alert,
                        deviceToken: token.token
                    )
                    logger.info("Push sent to device \(token.token.prefix(8))... (env: \(token.environment))")
                } catch let error as APNSError {
                    logger.error("APNs error for token \(token.token.prefix(8))...: \(error)")
                    if let reason = error.reason?.reason,
                       reason == "BadDeviceToken" || reason == "Unregistered" {
                        try? await token.delete(on: db)
                        logger.info("Removed invalid device token \(token.token.prefix(8))...")
                    }
                } catch {
                    logger.error("Push failed for token \(token.token.prefix(8))...: \(error)")
                }
            }
        } catch {
            logger.error("Failed to query device tokens: \(error)")
        }
    }

    func shutdown() {
        try? sandboxClient.syncShutdown()
        try? productionClient.syncShutdown()
    }
}

struct PushPayload: Codable, Sendable {
    let sessionId: String
}
