import Fluent
import Vapor
import SharedModels

final class Session: Model, Content, @unchecked Sendable {
    static let schema = "sessions"

    @ID(key: .id) var id: UUID?
    @OptionalField(key: "user_id") var userId: UUID?
    @Field(key: "openclaw_session_id") var openclawSessionId: String?
    @Field(key: "title") var title: String?
    @Field(key: "is_pinned") var isPinned: Bool
    @Field(key: "is_archived") var isArchived: Bool
    @OptionalField(key: "last_message_at") var lastMessageAt: Date?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    @Children(for: \.$session) var messages: [Message]

    init() {}

    init(id: UUID? = nil, title: String? = nil) {
        self.id = id
        self.title = title
        self.isPinned = false
        self.isArchived = false
    }

    func toDTO(unreadCount: Int = 0, lastMessagePreview: String? = nil) -> SessionDTO {
        SessionDTO(
            id: id!,
            title: title,
            lastMessagePreview: lastMessagePreview,
            lastMessageAt: lastMessageAt,
            unreadCount: unreadCount,
            isPinned: isPinned,
            isArchived: isArchived,
            createdAt: createdAt ?? .now
        )
    }
}
