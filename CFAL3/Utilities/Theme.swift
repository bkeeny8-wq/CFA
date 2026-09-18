import SwiftUI

enum Theme {
    /// Daybook parchment. Not Institute navy/gold.
    static let paper = Color(red: 243 / 255, green: 238 / 255, blue: 230 / 255)
    static let ink = Color(red: 26 / 255, green: 22 / 255, blue: 20 / 255)
    static let dust = Color(red: 107 / 255, green: 100 / 255, blue: 92 / 255)
    static let pine = Color(red: 44 / 255, green: 90 / 255, blue: 79 / 255)
    static let copper = Color(red: 196 / 255, green: 122 / 255, blue: 74 / 255)
    static let cardSurface = Color(red: 252 / 255, green: 249 / 255, blue: 244 / 255)

    static var accent: Color { pine }
    static var sage: Color { pine.opacity(0.12) }

    static let cardRadius: CGFloat = 22
    static let sittingCardRadius: CGFloat = 28
    /// Hairlines are gone; the token remains so older call sites still compile.
    static let hairline = Color.clear
    static var cardFill: Color { cardSurface }
    static var subtleFill: Color { pine.opacity(0.08) }

    static var success: Color { pine }
    static var warning: Color { copper }
    static var danger: Color { Color(red: 0.55, green: 0.27, blue: 0.22) }

    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }

    static func bookColor(_ book: Int) -> Color {
        let palette: [Color] = [
            pine,
            Color(red: 0.35, green: 0.48, blue: 0.42),
            copper,
            Color(red: 0.48, green: 0.40, blue: 0.32),
            Color(red: 0.42, green: 0.50, blue: 0.46),
            dust,
        ]
        guard book >= 1, book <= palette.count else { return dust }
        return palette[book - 1]
    }
}

private struct StoreUnavailableKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var storeUnavailable: Bool {
        get { self[StoreUnavailableKey.self] }
        set { self[StoreUnavailableKey.self] = newValue }
    }
}
