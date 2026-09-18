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

/// Study holds the reading notes and the flashcards, because they are the
/// same object — a reading — approached two ways, and five tab slots do not
/// stretch to seven sections.
///
/// The selector is a bar along the BOTTOM, directly above the real tab bar,
/// and it is attached to the container rather than to either navigation stack.
/// That is the whole point: a `.toolbar` belongs to whichever view sits on top
/// of the stack, so it evaporates the moment you push into a reading — which
/// is exactly how the old Practice switcher stranded you inside a case.
///
/// Only the selected half is mounted. Dual-mounting kept List rows from the
/// hidden half in the accessibility tree (`cards.today` readable from Notes)
/// because `List` hosts its own controller and ignores a parent
/// `.accessibilityHidden`. One tree means one half. Switching starts that
/// half fresh; an in-progress sitting hides this bar so it cannot dump the
/// sitting.
struct StudyRootView: View {
    @AppStorage("study.section", store: UITestMode.defaults)
    private var storedSection = StudySection.notes.rawValue
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var notesWantsHidden = false
    @State private var cardsWantsHidden = false

    private var section: StudySection {
        StudySection(rawValue: storedSection) ?? .notes
    }

    private var selectorHidden: Bool {
        section == .notes ? notesWantsHidden : cardsWantsHidden
    }

    var body: some View {
        Group {
            if section == .notes {
                notesRoot
                    .onPreferenceChange(StudySelectorHiddenKey.self) { notesWantsHidden = $0 }
            } else {
                NavigationStack {
                    FlashcardsHomeView()
                }
                .onPreferenceChange(StudySelectorHiddenKey.self) { cardsWantsHidden = $0 }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !selectorHidden {
                StudySectionBar(selection: $storedSection)
            }
        }
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

/// Two buttons across the bottom. Deliberately lighter than the real tab bar
/// sitting beneath it — smaller type, a tinted pill behind the selection
/// rather than a full bar — so the screen does not read as having two tab bars
/// stacked on each other.
struct StudySectionBar: View {
    @Binding var selection: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(StudySection.allCases) { section in
                let isSelected = selection == section.rawValue
                Button {
                    guard !isSelected else { return }
                    withSittingAnimation(reduceMotion) {
                        selection = section.rawValue
                    }
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
