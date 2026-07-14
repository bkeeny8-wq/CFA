import SwiftUI

enum LayoutMetrics {
    /// Comfortable line length for MC stems, essays, and study notes.
    static let readableMaxWidth: CGFloat = 720
    /// Fixed width for the LOS checklist pane beside notes on iPad.
    static let studyChecklistWidth: CGFloat = 380
    /// Minimum detail-pane width for side-by-side notes + checklist on iPad.
    static let studySideBySideMinWidth: CGFloat = 700
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
