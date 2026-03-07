import Foundation

// MARK: - Session

public struct SessionDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var title: String?
    public var lastMessagePreview: String?
    public var lastMessageAt: Date?
    public var unreadCount: Int
    public var isPinned: Bool
    public var isArchived: Bool
    public let createdAt: Date

    public init(
        id: UUID,
        title: String? = nil,
        lastMessagePreview: String? = nil,
        lastMessageAt: Date? = nil,
        unreadCount: Int = 0,
        isPinned: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.lastMessagePreview = lastMessagePreview
        self.lastMessageAt = lastMessageAt
        self.unreadCount = unreadCount
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

// MARK: - Message

public struct MessageDTO: Codable, Sendable, Identifiable {
    public let id: UUID
    public let sessionId: UUID
    public let role: MessageRole
    public let content: MessageContent
    public let createdAt: Date

    public init(
        id: UUID,
        sessionId: UUID,
        role: MessageRole,
        content: MessageContent,
        createdAt: Date = .now
    ) {
        self.id = id
        self.sessionId = sessionId
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }

    /// Extracts searchable text from message content.
    public var searchableText: String {
        switch content {
        case .text(let text): return text
        case .code(_, let content): return content
        case .system(let text): return text
        case .error(let text): return text
        case .image(_, let caption): return caption ?? ""
        case .file(let name, _, _): return name
        case .widget(let payload): return payload.title
        }
    }
}

// MARK: - Search

public struct SearchResultDTO: Codable, Sendable {
    public let message: MessageDTO
    public let sessionTitle: String?

    public init(message: MessageDTO, sessionTitle: String?) {
        self.message = message
        self.sessionTitle = sessionTitle
    }
}

// MARK: - User

public struct UserDTO: Codable, Sendable, Identifiable {
    public let id: UUID
    public let email: String
    public var displayName: String?
    public var avatarURL: URL?

    public init(id: UUID, email: String, displayName: String? = nil, avatarURL: URL? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}

// MARK: - Auth

public struct LoginRequest: Codable, Sendable {
    public let email: String
    public let password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct AuthResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let user: UserDTO

    public init(accessToken: String, refreshToken: String? = nil, user: UserDTO) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.user = user
    }
}

// MARK: - Create/Update

public struct CreateSessionRequest: Codable, Sendable {
    public let title: String?

    public init(title: String? = nil) {
        self.title = title
    }
}

public struct UpdateSessionRequest: Codable, Sendable {
    public var title: String?
    public var isPinned: Bool?
    public var isArchived: Bool?

    public init(title: String? = nil, isPinned: Bool? = nil, isArchived: Bool? = nil) {
        self.title = title
        self.isPinned = isPinned
        self.isArchived = isArchived
    }
}

public struct SendMessageRequest: Codable, Sendable {
    public let content: String
    public let attachments: [AttachmentInfo]?
    public let role: String?

    public init(content: String, attachments: [AttachmentInfo]? = nil, role: String? = nil) {
        self.content = content
        self.attachments = attachments
        self.role = role
    }
}

public struct AttachmentInfo: Codable, Sendable {
    public let filename: String
    public let mimeType: String
    public let size: Int64
    public let serverPath: String

    public init(filename: String, mimeType: String, size: Int64, serverPath: String) {
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.serverPath = serverPath
    }
}

// MARK: - File System

public struct FileItem: Codable, Sendable, Identifiable {
    public let id: String // relative path
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    public let modifiedAt: Date?

    public init(id: String, name: String, isDirectory: Bool, size: Int64? = nil, modifiedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modifiedAt = modifiedAt
    }
}

// MARK: - Pagination

public struct PaginatedResponse<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let total: Int
    public let page: Int
    public let perPage: Int

    public init(items: [T], total: Int, page: Int, perPage: Int) {
        self.items = items
        self.total = total
        self.page = page
        self.perPage = perPage
    }
}

// MARK: - Health

public struct HealthResponse: Codable, Sendable {
    public let status: String
    public let version: String
    public let openclawConnected: Bool

    public init(status: String, version: String, openclawConnected: Bool) {
        self.status = status
        self.version = version
        self.openclawConnected = openclawConnected
    }
}

// MARK: - Widget

public enum WidgetSize: String, Codable, Sendable, Hashable, CaseIterable {
    case small   // 1×1 — one grid slot
    case medium  // 2×1 — full width, single row
    case large   // 2×2 — full width, double row

    public var colSpan: Int {
        switch self {
        case .small: return 1
        case .medium, .large: return 2
        }
    }

    public var rowSpan: Int {
        switch self {
        case .small, .medium: return 1
        case .large: return 2
        }
    }

    /// Next size in the cycle: small → medium → large → small
    public var next: WidgetSize {
        switch self {
        case .small: return .medium
        case .medium: return .large
        case .large: return .small
        }
    }
}

public enum WidgetSurface: String, Codable, Sendable, Hashable {
    case inline
    case dashboard
}

public struct WidgetPayload: Codable, Sendable, Hashable {
    public let slug: String
    public let title: String
    public let description: String
    public let surface: WidgetSurface
    public let version: Int

    public init(slug: String, title: String, description: String, surface: WidgetSurface, version: Int) {
        self.slug = slug
        self.title = title
        self.description = description
        self.surface = surface
        self.version = version
    }
}

public struct WidgetDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let slug: String
    public let title: String
    public let description: String
    public let surface: WidgetSurface
    public let html: String
    public let renderVars: [String: String]
    public let version: Int
    public let createdBySession: UUID?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID,
        slug: String,
        title: String,
        description: String,
        surface: WidgetSurface,
        html: String,
        renderVars: [String: String] = [:],
        version: Int = 1,
        createdBySession: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.slug = slug
        self.title = title
        self.description = description
        self.surface = surface
        self.html = html
        self.renderVars = renderVars
        self.version = version
        self.createdBySession = createdBySession
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WidgetListItemDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let slug: String
    public let title: String
    public let description: String
    public let surface: WidgetSurface
    public let version: Int
    public let createdAt: Date

    public init(id: UUID, slug: String, title: String, description: String, surface: WidgetSurface, version: Int, createdAt: Date) {
        self.id = id
        self.slug = slug
        self.title = title
        self.description = description
        self.surface = surface
        self.version = version
        self.createdAt = createdAt
    }
}

public struct DashboardItemDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let widgetId: UUID
    public let slug: String
    public let title: String
    public let size: WidgetSize
    public let position: Int

    public init(id: UUID, widgetId: UUID, slug: String, title: String, size: WidgetSize, position: Int) {
        self.id = id
        self.widgetId = widgetId
        self.slug = slug
        self.title = title
        self.size = size
        self.position = position
    }
}

public struct WidgetVersionDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let version: Int
    public let snapshotAt: Date

    public init(id: UUID, version: Int, snapshotAt: Date) {
        self.id = id
        self.version = version
        self.snapshotAt = snapshotAt
    }
}

// MARK: - Widget Requests

public struct CreateWidgetRequest: Codable, Sendable {
    public let slug: String
    public let title: String
    public let description: String
    public let surface: WidgetSurface
    public let html: String
    public let sessionId: UUID?

    public init(slug: String, title: String, description: String, surface: WidgetSurface, html: String, sessionId: UUID? = nil) {
        self.slug = slug
        self.title = title
        self.description = description
        self.surface = surface
        self.html = html
        self.sessionId = sessionId
    }
}

public struct UpdateWidgetSectionsRequest: Codable, Sendable {
    public let sections: [String: String]

    public init(sections: [String: String]) {
        self.sections = sections
    }
}

public struct UpdateRenderVarsRequest: Codable, Sendable {
    public let vars: [String: String]

    public init(vars: [String: String]) {
        self.vars = vars
    }
}

public struct PinWidgetRequest: Codable, Sendable {
    public let size: WidgetSize

    public init(size: WidgetSize = .small) {
        self.size = size
    }
}

public struct ReorderDashboardRequest: Codable, Sendable {
    public let items: [ReorderItem]

    public struct ReorderItem: Codable, Sendable {
        public let widgetId: UUID
        public let size: WidgetSize

        public init(widgetId: UUID, size: WidgetSize) {
            self.widgetId = widgetId
            self.size = size
        }
    }

    public init(items: [ReorderItem]) {
        self.items = items
    }
}

public struct UpdateDashboardItemRequest: Codable, Sendable {
    public let size: WidgetSize

    public init(size: WidgetSize) {
        self.size = size
    }
}

// MARK: - Widget Library

public enum WidgetCategory: String, Codable, Sendable, Hashable, CaseIterable {
    case productivity
    case monitoring
    case lifestyle
    case utility
}

public struct WidgetTemplateDTO: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let slug: String
    public let title: String
    public let description: String
    public let category: WidgetCategory
    public let icon: String
    public let supportedSizes: [WidgetSize]
    public let defaultSize: WidgetSize

    public init(id: String, slug: String, title: String, description: String, category: WidgetCategory, icon: String, supportedSizes: [WidgetSize], defaultSize: WidgetSize) {
        self.id = id
        self.slug = slug
        self.title = title
        self.description = description
        self.category = category
        self.icon = icon
        self.supportedSizes = supportedSizes
        self.defaultSize = defaultSize
    }
}

public struct InstantiateTemplateRequest: Codable, Sendable {
    public let size: WidgetSize

    public init(size: WidgetSize = .small) {
        self.size = size
    }
}
