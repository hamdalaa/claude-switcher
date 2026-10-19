import ClaudeSwitcherCore
import SwiftUI

/* Direction: native macOS menu (Control Center language) · system material ground · flat rows,
   hairline separators, no inner cards · color only for identity (avatars) and warnings ·
   SF at menu sizes 13/11 with tabular digits · 6pt hover highlight · no motion except hover.
   Derived from DESIGN.md. Do not add values here without updating DESIGN.md. */
enum Theme {
    // Layout
    static let panelWidth: CGFloat = 300
    static let panelInset: CGFloat = 5          // menu content inset from the popover edge
    static let rowPaddingH: CGFloat = 8
    static let rowPaddingV: CGFloat = 5
    static let rowSpacing: CGFloat = 8
    static let headerPaddingTop: CGFloat = 8
    static let textGap: CGFloat = 2              // title ↔ subtitle
    static let meterGap: CGFloat = 5             // between meters, and above them
    static let stackGap: CGFloat = 6             // stacked text + buttons in a prompt

    // Welcome window
    static let welcomeWidth: CGFloat = 440
    static let welcomePadding: CGFloat = 22
    static let welcomeSectionGap: CGFloat = 18
    static let welcomeStepGap: CGFloat = 14
    static let welcomeBadge: CGFloat = 22
    static let highlightRadius: CGFloat = 6
    static let separatorInsetH: CGFloat = 8
    static let separatorGap: CGFloat = 5
    static let checkColumn: CGFloat = 12
    static let avatarSize: CGFloat = 26
    static let meterHeight: CGFloat = 4
    static let meterLabelWidth: CGFloat = 44
    static let meterValueWidth: CGFloat = 34
    static let meterResetWidth: CGFloat = 50

    // Type (macOS menu sizes)
    static let body = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let title = Font.system(size: 13, weight: .bold)
    static let detail = Font.system(size: 11)
    static let detailDigits = Font.system(size: 11).monospacedDigit()
    static let bodyDigits = Font.system(size: 13).monospacedDigit()
    static let avatarLetter = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let welcomeTitle = Font.system(size: 17, weight: .semibold)

    // Surfaces
    static let hover = Color.primary.opacity(0.09)
    static let meterTrack = Color.primary.opacity(0.10)
    static let meterFill = Color.primary.opacity(0.45)
    static let separator = Color.primary.opacity(0.10)
    static let neutralAvatar = Color.secondary.opacity(0.45)
    static let codexAvatar = Color.primary.opacity(0.75)

    // Identity — avatars only
    static func tint(_ account: Account) -> Color {
        switch account {
        case .a: Color(red: 0.80, green: 0.45, blue: 0.33)   // clay
        case .b: Color(red: 0.25, green: 0.52, blue: 0.47)   // sage
        case .c: Color(red: 0.69, green: 0.55, blue: 0.24)   // ochre
        case .d: Color(red: 0.38, green: 0.47, blue: 0.58)   // slate
        }
    }

    // Meaning — usage warnings only
    static let warnPercent = 70
    static func warning(for percent: Int) -> Color? {
        if percent >= AccountStore.limitPercent { return .red }
        if percent >= warnPercent { return .orange }
        return nil
    }
}
