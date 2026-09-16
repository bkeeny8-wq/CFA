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

/// Screens that want the Study selector out of the way — a running session is
/// the one place where leaving is not the goal, and a card session already
/// owns the bottom of the screen with its rating bar.
struct StudySelectorHiddenKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func hidesStudySelector(_ hidden: Bool = true) -> some View {
        preference(key: StudySelectorHiddenKey.self, value: hidden)
    }
}

/// Study holds both the reading notes and the flashcards, because they are the
/// same object — a reading — approached two ways, and five tab slots do not
/// stretch to seven sections.
///
/// The selector is a bar along the BOTTOM, directly above the real tab bar,
/// and it is attached to the container rather than to either navigation stack.
/// That is the whole point: a `.toolbar` belongs to whichever view sits on top
/// of the stack, so it evaporates the moment you push into a reading — which
/// is exactly how the old Practice switcher stranded you inside a case.
///
/// Both halves stay MOUNTED. Switching with a `switch` would tear the other
/// one down, so flipping to Cards and back would dump you at the Study root
/// and discard an in-progress drill. Keeping both alive makes the bar behave
/// like a tab: you return exactly where you were, at whatever depth.
struct StudyRootView: View {
    @AppStorage("study.section", store: UITestMode.defaults)
    private var storedSection = StudySection.notes.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Tracked per branch, because both are mounted: a single flag would let
    /// the hidden half's preference hide the bar for the visible one.
    @State private var notesWantsHidden = false
    @State private var cardsWantsHidden = false

    private var section: StudySection {
        StudySection(rawValue: storedSection) ?? .notes
    }

    private var selectorHidden: Bool {
        section == .notes ? notesWantsHidden : cardsWantsHidden
    }

    var body: some View {
        ZStack {
            branch(.notes) { notesRoot(active: section == .notes) }
                .onPreferenceChange(StudySelectorHiddenKey.self) { notesWantsHidden = $0 }
            branch(.cards) {
                NavigationStack {
                    FlashcardsHomeView()
                        .accessibilityHidden(section != .cards)
                }
            }
            .onPreferenceChange(StudySelectorHiddenKey.self) { cardsWantsHidden = $0 }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectorHidden {
                StudySectionBar(selection: $storedSection)
            }
        }
    }

    /// The hidden half must be inert as well as invisible: left hit-testable
    /// it would swallow taps, and left readable a screen reader would find two
    /// of everything.
    ///
    /// Opacity and hit-testing are honoured from out here. Accessibility is
    /// not: a11y modifiers do not cross a hosting-controller boundary, and
    /// each branch roots a navigation container that creates one. So the same
    /// hiding is pushed down INSIDE each branch as well (see `notesRoot` and
    /// the Cards stack below) — that, not the modifier here, is what stops the
    /// planner being readable from the Cards screen.
    ///
    /// That is still not airtight: `List` hosts its own rows, so rows inside
    /// one — `cards.today`, for instance — remain enumerable from the other
    /// half. The honest fix would be to mount one branch at a time, and that
    /// is precisely what this screen must not do: a `switch` here changes view
    /// identity, so toggling would dump an in-progress drill and return you to
    /// the Study root. A residual VoiceOver leak is the cheaper defect.
    ///
    /// Tests must therefore assert on which branch is SELECTED, never on
    /// whether the other branch's elements exist — they do.
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
    private func notesRoot(active: Bool) -> some View {
        if horizontalSizeClass == .regular {
            StudyPlannerSplitView(accessibilityHidden: !active)
        } else {
            NavigationStack {
                StudyPlannerView()
                    .accessibilityHidden(!active)
            }
        }
    }
}

/// Two buttons across the bottom. Deliberately lighter than the real tab bar
/// sitting beneath it — smaller type, a tinted pill behind the selection
/// rather than a full bar — so the screen does not read as having two tab bars
/// stacked on each other.
struct StudySectionBar: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(StudySection.allCases) { section in
                let isSelected = selection == section.rawValue
                Button {
                    guard !isSelected else { return }
                    withAnimation(.snappy(duration: 0.2)) { selection = section.rawValue }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: section.symbol)
                            .font(.footnote)
                        Text(section.title)
                            .font(.footnote.weight(isSelected ? .semibold : .regular))
                    }
                    .frame(maxWidth: .infinity)
                    // 44pt minimum target, and it keeps the bar readable at
                    // accessibility text sizes.
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Theme.accent.opacity(0.15) : .clear)
                    )
                    // A clear background contributes no hit region, so without
                    // this the UNSELECTED half's tappable area collapsed to its
                    // text: measured at 59.8 × 16 pt against the selected
                    // half's 500 × 44. The button you need to press is always
                    // the unselected one.
                    .contentShape(Rectangle())
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("study.section.\(section.rawValue)")
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
