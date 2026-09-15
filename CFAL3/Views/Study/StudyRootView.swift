import SwiftUI

/// Which half of the Study tab is showing.
enum StudySection: String, CaseIterable, Identifiable {
    case notes
    case cards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .cards: return "Cards"
        }
    }

    var symbol: String {
        switch self {
        case .notes: return "doc.text"
        case .cards: return "rectangle.on.rectangle.angled"
        }
    }
}

/// Study holds both the reading notes and the flashcards, because they are the
/// same object — a reading — approached two ways, and five tab slots do not
/// stretch to seven sections. A menu in the navigation bar switches between
/// them.
///
/// Both halves stay MOUNTED. Switching with a `switch` would tear the other
/// one down, so flipping to Cards and back would dump you at the Study root
/// and discard an in-progress drill. Keeping both alive makes the menu behave
/// like a tab: you return exactly where you were, at whatever depth.
struct StudyRootView: View {
    @AppStorage("study.section") private var storedSection = StudySection.notes.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var section: StudySection {
        StudySection(rawValue: storedSection) ?? .notes
    }

    var body: some View {
        ZStack {
            branch(.notes) { notesRoot }
            branch(.cards) { NavigationStack { FlashcardsHomeView() } }
        }
    }

    /// The hidden half must be inert as well as invisible: left hit-testable
    /// it would swallow taps, and left visible to accessibility a screen
    /// reader (and XCUITest) would find two of everything.
    @ViewBuilder
    private func branch<Content: View>(
        _ which: StudySection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isActive = section == which
        content()
            .opacity(isActive ? 1 : 0)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
    }

    @ViewBuilder
    private var notesRoot: some View {
        if horizontalSizeClass == .regular {
            StudyPlannerSplitView()
        } else {
            NavigationStack {
                StudyPlannerView()
            }
        }
    }
}

/// The switcher itself, rendered by whichever Study screen is at the root of
/// its stack. Re-tapping the Study tab pops back here, so it is always two
/// taps away at most.
struct StudySectionMenu: View {
    @AppStorage("study.section") private var storedSection = StudySection.notes.rawValue

    var body: some View {
        Menu {
            Picker("Section", selection: $storedSection) {
                ForEach(StudySection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .tag(section.rawValue)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .accessibilityIdentifier("study.sectionMenu")
        .accessibilityLabel("Switch section")
        .accessibilityValue(StudySection(rawValue: storedSection)?.title ?? "Notes")
    }
}
