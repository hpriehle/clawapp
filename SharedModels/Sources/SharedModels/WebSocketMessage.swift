import Foundation

/// Messages sent over the WebSocket between iOS app and Vapor backend.
public enum WSMessage: Codable, Sendable {
    // Client -> Server
    case sendChat(SendChatPayload)
    case subscribe(sessionId: UUID)
    case unsubscribe(sessionId: UUID)
    case ping

    // Server -> Client
    case chatDelta(ChatDeltaPayload)
    case chatComplete(MessageDTO)
    case sessionUpdated(SessionDTO)
    case error(WSError)
    case pong
    case widgetInjected(WidgetPayload)
    case widgetUpdated(WidgetPayload)

    // MARK: - Payloads

    public struct SendChatPayload: Codable, Sendable {
        public let sessionId: UUID
        public let content: String
        public let stream: Bool

        public init(sessionId: UUID, content: String, stream: Bool = true) {
            self.sessionId = sessionId
            self.content = content
            self.stream = stream
        }
    }

    public struct ChatDeltaPayload: Codable, Sendable {
        public let sessionId: UUID
        public let delta: String
        public let messageId: UUID

        public init(sessionId: UUID, delta: String, messageId: UUID) {
            self.sessionId = sessionId
            self.delta = delta
            self.messageId = messageId
        }
    }

    public struct WSError: Codable, Sendable {
        public let code: Int
        public let message: String

        public init(code: Int, message: String) {
            self.code = code
            self.message = message
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "send_chat":
            self = .sendChat(try container.decode(SendChatPayload.self, forKey: .payload))
        case "subscribe":
            let payload = try container.decode([String: UUID].self, forKey: .payload)
            self = .subscribe(sessionId: payload["sessionId"]!)
        case "unsubscribe":
            let payload = try container.decode([String: UUID].self, forKey: .payload)
            self = .unsubscribe(sessionId: payload["sessionId"]!)
        case "ping":
            self = .ping
        case "chat_delta":
            self = .chatDelta(try container.decode(ChatDeltaPayload.self, forKey: .payload))
        case "chat_complete":
            self = .chatComplete(try container.decode(MessageDTO.self, forKey: .payload))
        case "session_updated":
            self = .sessionUpdated(try container.decode(SessionDTO.self, forKey: .payload))
        case "error":
            self = .error(try container.decode(WSError.self, forKey: .payload))
        case "pong":
            self = .pong
        case "widget_injected":
            self = .widgetInjected(try container.decode(WidgetPayload.self, forKey: .payload))
        case "widget_updated":
            self = .widgetUpdated(try container.decode(WidgetPayload.self, forKey: .payload))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown WS message type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sendChat(let payload):
            try container.encode("send_chat", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .subscribe(let sessionId):
            try container.encode("subscribe", forKey: .type)
            try container.encode(["sessionId": sessionId], forKey: .payload)
        case .unsubscribe(let sessionId):
            try container.encode("unsubscribe", forKey: .type)
            try container.encode(["sessionId": sessionId], forKey: .payload)
        case .ping:
            try container.encode("ping", forKey: .type)
        case .chatDelta(let payload):
            try container.encode("chat_delta", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .chatComplete(let message):
            try container.encode("chat_complete", forKey: .type)
            try container.encode(message, forKey: .payload)
        case .sessionUpdated(let session):
            try container.encode("session_updated", forKey: .type)
            try container.encode(session, forKey: .payload)
        case .error(let error):
            try container.encode("error", forKey: .type)
            try container.encode(error, forKey: .payload)
        case .pong:
            try container.encode("pong", forKey: .type)
        case .widgetInjected(let payload):
            try container.encode("widget_injected", forKey: .type)
            try container.encode(payload, forKey: .payload)
        case .widgetUpdated(let payload):
            try container.encode("widget_updated", forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}