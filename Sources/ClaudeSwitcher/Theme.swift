import ClaudeSwitcherCore
import SwiftUI

/// The few tokens the panel uses. Account colours are identity; usage colours are meaning.
enum Theme {
    static let panelWidth: CGFloat = 332
    static let cardRadius: CGFloat = 14
    static let avatarSize: CGFloat = 34
    static let barHeight: CGFloat = 5

    static func tint(_ account: Account) -> Color {
        switch account {
        case .a: Color(red: 0.85, green: 0.47, blue: 0.34)   // Claude clay
        case .b: Color(red: 0.24, green: 0.56, blue: 0.50)   // deep sage
        }
    }

    /// Usage bars are coloured by how much is used, not by account: green → yellow → orange → red.
    static let cautionPercent = 50
    static let warnPercent = 70
    static func usageColor(_ percent: Int) -> Color {
        switch percent {
        case AccountStore.limitPercent...: .red
        case warnPercent...: .orange
        case cautionPercent...: .yellow
        default: .green
        }
    }

    /// Codex gets a neutral graphite identity so it never reads as a third Claude account.
    static let codexTint = Color.primary.opacity(0.72)
}
