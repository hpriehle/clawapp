import Foundation

/// The content of a chat message, polymorphic by type.
public enum MessageContent: Codable, Sendable, Hashable {
    case text(String)
    case code(language: String, content: String)
    case image(url: URL, caption: String?)
    case file(name: String, url: URL, size: Int64)
    case system(String)
    case error(String)
    case widget(WidgetPayload)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case type, text, language, content, url, caption, name, size
        case slug, title, description, surface, version
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text)
        case "code":
            let language = try container.decode(String.self, forKey: .language)
            let content = try container.decode(String.self, forKey: .content)
            self = .code(language: language, content: content)
        case "image":
            let url = try container.decode(URL.self, forKey: .url)
            let caption = try container.decodeIfPresent(String.self, forKey: .caption)
            self = .image(url: url, caption: caption)
        case "file":
            let name = try container.decode(String.self, forKey: .name)
            let url = try container.decode(URL.self, forKey: .url)
            let size = try container.decode(Int64.self, forKey: .size)
            self = .file(name: name, url: url, size: size)
        case "system":
            let text = try container.decode(String.self, forKey: .text)
            self = .system(text)
        case "error":
            let text = try container.decode(String.self, forKey: .text)
            self = .error(text)
        case "widget":
            let payload = WidgetPayload(
                slug: try container.decode(String.self, forKey: .slug),
                title: try container.decode(String.self, forKey: .title),
                description: try container.decode(String.self, forKey: .description),
                surface: try container.decode(WidgetSurface.self, forKey: .surface),
                version: try container.decode(Int.self, forKey: .version)
            )
            self = .widget(payload)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown message type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .code(let language, let content):
            try container.encode("code", forKey: .type)
            try container.encode(language, forKey: .language)
            try container.encode(content, forKey: .content)
        case .image(let url, let caption):
            try container.encode("image", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(caption, forKey: .caption)
        case .file(let name, let url, let size):
            try container.encode("file", forKey: .type)
            try container.encode(name, forKey: .name)
            try container.encode(url, forKey: .url)
            try container.encode(size, forKey: .size)
        case .system(let text):
            try container.encode("system", forKey: .type)
            try container.encode(text, forKey: .text)
        case .error(let text):
            try container.encode("error", forKey: .type)
            try container.encode(text, forKey: .text)
        case .widget(let payload):
            try container.encode("widget", forKey: .type)
            try container.encode(payload.slug, forKey: .slug)
            try container.encode(payload.title, forKey: .title)
            try container.encode(payload.description, forKey: .description)
            try container.encode(payload.surface, forKey: .surface)
            try container.encode(payload.version, forKey: .version)
        }
    }

    /// Short preview text for notification/list display.
    public var previewText: String {
        switch self {
        case .text(let t): return t
        case .code(let lang, _): return "[\(lang) code]"
        case .image(_, let caption): return caption ?? "[Image]"
        case .file(let name, _, _): return "[\(name)]"
        case .system(let t): return t
        case .error(let t): return "Error: \(t)"
        case .widget(let p): return "[Widget: \(p.title)]"
        }
    }
}

/// Role of a message sender.
public enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
    case tool
}
