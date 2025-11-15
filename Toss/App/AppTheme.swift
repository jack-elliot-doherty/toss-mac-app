import SwiftUI

enum AppTheme {
    static let windowBackground = Color(red: 12 / 255, green: 13 / 255, blue: 16 / 255)
    static let sidebarBackground = Color(red: 20 / 255, green: 21 / 255, blue: 25 / 255)
    static let cardBackground = Color(red: 26 / 255, green: 27 / 255, blue: 32 / 255)
    static let elevatedBackground = Color(red: 31 / 255, green: 32 / 255, blue: 38 / 255)
    static let subtleStroke = Color.white.opacity(0.08)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.65)
    static let accent = Color(red: 96 / 255, green: 120 / 255, blue: 255 / 255)
    static let destructive = Color(red: 255 / 255, green: 87 / 255, blue: 114 / 255)

    static func pillBackground(highlighted: Bool = false) -> Color {
        highlighted ? AppTheme.accent.opacity(0.18) : Color.white.opacity(0.08)
    }
}
