import SwiftUI

/// The two ways to reach a question: assemble a scoped quiz, or pick a specific
/// case and work it as one item set. Both are practice, so they live behind one
/// tab rather than competing for a slot in the tab bar.
enum PracticeMode: String, CaseIterable, Identifiable {
    case build
    case cases

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .build: return "Build a quiz"
        case .cases: return "Browse cases"
        }
    }
}

/// Segmented switcher rendered in the navigation bar's principal slot, so it
/// replaces the title at the root and disappears once you push into a case.
struct PracticeModePicker: View {
    @Binding var mode: PracticeMode

    var body: some View {
        Picker("Practice mode", selection: $mode) {
            ForEach(PracticeMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 260)
    }
}

/// Root of the Practice tab. Owns the mode and hands each branch the binding so
/// the branch can render the picker in its own navigation bar — the split view
/// needs it inside its sidebar column, which an outer `.toolbar` cannot reach.
struct PracticeRootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var mode: PracticeMode = .build

    var body: some View {
        switch mode {
        case .build:
            NavigationStack {
                PracticeBuilderView(practiceMode: $mode)
            }
        case .cases:
            if horizontalSizeClass == .regular {
                BrowseSplitView(practiceMode: $mode)
            } else {
                NavigationStack {
                    TopicListView(practiceMode: $mode)
                }
            }
        }
    }
}
