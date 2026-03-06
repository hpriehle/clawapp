import Fluent
import Vapor

final class WidgetSession: Model, Content, @unchecked Sendable {
    static let schema = "widget_sessions"

    @ID(key: .id) var id: UUID?
    @Field(key: "jti") var jti: String
    @Field(key: "issued_at") var issuedAt: Date
    @Field(key: "expires_at") var expiresAt: Date
    @OptionalField(key: "revoked_at") var revokedAt: Date?

    init() {}

    init(id: UUID? = nil, jti: String, issuedAt: Date = .now, expiresAt: Date) {
        self.id = id
        self.jti = jti
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    var isValid: Bool {
        revokedAt == nil && expiresAt > .now
    }
}
