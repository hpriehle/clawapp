import Fluent
import Vapor
import SharedModels
import Foundation

final class Message: Model, Content, @unchecked Sendable {
    static let schema = "messages"

    @ID(key: .id) var id: UUID?
    @Parent(key: "session_id") var session: Session
    @Field(key: "role") var role: String
    @Field(key: "content_json") var contentJSON: Data
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(id: UUID? = nil, sessionId: UUID, role: MessageRole, content: MessageContent) throws {
        self.id = id
        self.$session.id = sessionId
        self.role = role.rawValue
        self.contentJSON = try JSONEncoder().encode(content)
    }

    /// Extract the plain text from this message's content, if it's a `.text` variant.
    var textContent: String? {
        guard let content = try? JSONDecoder().decode(MessageContent.self, from: contentJSON),
              case .text(let text) = content else { return nil }
        return text
    }

    func toDTO() throws -> MessageDTO {
        let content = try JSONDecoder().decode(MessageContent.self, from: contentJSON)
        return MessageDTO(
            id: id!,
            sessionId: $session.id,
            role: MessageRole(rawValue: role) ?? .system,
            content: content,
            createdAt: createdAt ?? .now
        )
    }
}