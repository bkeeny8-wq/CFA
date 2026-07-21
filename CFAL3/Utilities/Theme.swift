import SwiftUI

enum Theme {
    /// CFA L3 brand blue (matches app icon)
    static var accent: Color { Color(red: 0.29, green: 0.56, blue: 0.89) }

    static let cardRadius: CGFloat = 12
    static let hairline: Color = Color(.separator)
    static var cardFill: Color { Color(.secondarySystemGroupedBackground) }
    static var subtleFill: Color { Color(.tertiarySystemFill) }

    static var success: Color { .green }
    static var warning: Color { .orange }
    static var danger: Color { .red }

    static func bookColor(_ book: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.35, green: 0.55, blue: 0.82),
            Color(red: 0.28, green: 0.62, blue: 0.55),
            Color(red: 0.72, green: 0.52, blue: 0.34),
            Color(red: 0.58, green: 0.42, blue: 0.72),
            Color(red: 0.78, green: 0.45, blue: 0.48),
            Color(red: 0.45, green: 0.50, blue: 0.58),
        ]
        guard book >= 1, book <= palette.count else { return .secondary }
        return palette[book - 1]
    }
}
