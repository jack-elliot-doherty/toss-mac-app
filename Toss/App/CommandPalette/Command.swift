import Foundation

enum CommandCategory: String, CaseIterable {
    case navigation
    case actions
}

enum CommandAction {
    case navigate(SidebarItem)
    case execute(() -> Void)
}

struct Command: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String  // SF Symbol name
    let category: CommandCategory
    let keywords: [String]
    let action: CommandAction

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String,
        category: CommandCategory,
        keywords: [String] = [],
        action: CommandAction
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.category = category
        self.keywords = keywords
        self.action = action
    }
}
