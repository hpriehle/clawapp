import SharedModels

struct WidgetTemplate {
    let slug: String
    let title: String
    let description: String
    let category: WidgetCategory
    let icon: String
    let supportedSizes: [WidgetSize]
    let defaultSize: WidgetSize
    let html: String

    var dto: WidgetTemplateDTO {
        WidgetTemplateDTO(
            id: slug,
            slug: slug,
            title: title,
            description: description,
            category: category,
            icon: icon,
            supportedSizes: supportedSizes,
            defaultSize: defaultSize
        )
    }
}

enum WidgetTemplateCatalog {
    static let templates: [WidgetTemplate] = [
        WidgetTemplate(
            slug: "clock",
            title: "Clock",
            description: "Digital clock with date display",
            category: .utility,
            icon: "clock.fill",
            supportedSizes: [.small, .medium],
            defaultSize: .small,
            html: WidgetTemplateHTML.clock
        ),
        WidgetTemplate(
            slug: "quick-notes",
            title: "Quick Notes",
            description: "Persistent sticky note pad",
            category: .productivity,
            icon: "note.text",
            supportedSizes: [.small, .medium, .large],
            defaultSize: .medium,
            html: WidgetTemplateHTML.quickNotes
        ),
        WidgetTemplate(
            slug: "countdown",
            title: "Countdown",
            description: "Countdown timer to a target date",
            category: .utility,
            icon: "timer",
            supportedSizes: [.small, .medium],
            defaultSize: .small,
            html: WidgetTemplateHTML.countdown
        ),
        WidgetTemplate(
            slug: "quote-of-the-day",
            title: "Quote of the Day",
            description: "Rotating inspirational quotes",
            category: .lifestyle,
            icon: "quote.opening",
            supportedSizes: [.small, .medium],
            defaultSize: .medium,
            html: WidgetTemplateHTML.quoteOfTheDay
        ),
        WidgetTemplate(
            slug: "todo-list",
            title: "Todo List",
            description: "Simple checklist with persistence",
            category: .productivity,
            icon: "checklist",
            supportedSizes: [.medium, .large],
            defaultSize: .medium,
            html: WidgetTemplateHTML.todoList
        ),
        WidgetTemplate(
            slug: "system-status",
            title: "System Status",
            description: "Server health and uptime monitor",
            category: .monitoring,
            icon: "server.rack",
            supportedSizes: [.medium, .large],
            defaultSize: .large,
            html: WidgetTemplateHTML.systemStatus
        ),
    ]

    static func find(slug: String) -> WidgetTemplate? {
        templates.first { $0.slug == slug }
    }
}
