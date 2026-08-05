import SwiftUI

enum LayoutMetrics {
    /// Comfortable line length for MC stems, essays, and study notes.
    static let readableMaxWidth: CGFloat = 720
    /// Centered reading column cap in full-screen study detail on iPad.
    static let studyReadingMaxWidth: CGFloat = 760
}

struct ReadableContentWidthModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var maxWidth: CGFloat = LayoutMetrics.readableMaxWidth

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
        } else {
            content
        }
    }
}

extension View {
    func readableContentWidth(_ maxWidth: CGFloat = LayoutMetrics.readableMaxWidth) -> some View {
        modifier(ReadableContentWidthModifier(maxWidth: maxWidth))
    }
}

extension EnvironmentValues {
    var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }
}
