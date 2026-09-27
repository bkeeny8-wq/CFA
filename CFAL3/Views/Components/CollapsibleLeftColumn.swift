import SwiftUI
import Observation

/// One collapsible left column: how it is remembered, and how it is spoken.
///
/// Every left column in the app — the Daybook sidebar and the Notes LOS rail —
/// is described by one of these, so the control that folds it away is the same
/// control everywhere instead of a per-screen toolbar glyph.
struct LeftColumnSpec: Identifiable, Equatable, Sendable {
    /// Persistence key and identifier suffix. Stable across releases.
    let key: String
    /// Spoken in "Hide the sidebar" / "Show the sidebar", so it is a noun
    /// phrase with no leading article.
    let name: String
    /// Hardware-keyboard shortcut, held with control-command.
    let shortcut: KeyEquivalent?

    var id: String { key }

    var toggleIdentifier: String { "leftcolumn.toggle.\(key)" }

    static let sidebar = LeftColumnSpec(key: "sidebar", name: "sidebar", shortcut: "s")
    static let notesLOSRail = LeftColumnSpec(key: "notes.rail", name: "LOS rail", shortcut: "l")
    static let commandWordList = LeftColumnSpec(key: "commandwords.list", name: "word list", shortcut: "w")
}

/// Which left columns the reader has folded away, remembered across launches,
/// plus which inner columns the screen on screen right now actually has.
///
/// Stored properties, and read through methods rather than computed
/// properties over `UserDefaults` — see `PracticeBuilderPreference` for why
/// the difference matters to `@Observable`.
@Observable
final class LeftColumnPreference {
    @ObservationIgnored private let defaults: UserDefaults

    private static let storageKey = "leftColumn.hidden"

    private var hiddenKeys: Set<String>

    /// Inner left columns belonging to the visible screen, in the order they
    /// appear on it. Screens register with `leftColumnControl(_:active:)`
    /// rather than drawing their own button.
    private(set) var innerColumns: [LeftColumnSpec] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenKeys = Set(defaults.stringArray(forKey: Self.storageKey) ?? [])
    }

    func isHidden(_ column: LeftColumnSpec) -> Bool {
        hiddenKeys.contains(column.key)
    }

    func setHidden(_ hidden: Bool, for column: LeftColumnSpec) {
        var next = hiddenKeys
        if hidden {
            next.insert(column.key)
        } else {
            next.remove(column.key)
        }
        guard next != hiddenKeys else { return }
        hiddenKeys = next
        defaults.set(next.sorted(), forKey: Self.storageKey)
    }

    func toggle(_ column: LeftColumnSpec) {
        setHidden(!isHidden(column), for: column)
    }

    func register(_ column: LeftColumnSpec) {
        guard !innerColumns.contains(column) else { return }
        innerColumns.append(column)
    }

    func unregister(_ column: LeftColumnSpec) {
        innerColumns.removeAll { $0 == column }
    }
}

/// The one control. Same glyph, same corner, same wording on every screen.
///
/// Icon-only, so the label carries the whole meaning: it names the column and
/// the direction of the action, and the selected background plus the value
/// make the current state visible as well as spoken.
struct LeftColumnToggle: View {
    @Environment(LeftColumnPreference.self) private var columns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let column: LeftColumnSpec

    var body: some View {
        let shown = !columns.isHidden(column)
        return Button {
            withSittingAnimation(reduceMotion) { columns.toggle(column) }
        } label: {
            Image(systemName: "sidebar.leading")
                .font(.body.weight(.medium))
                .foregroundStyle(shown ? Theme.pine : Theme.dust)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(shown ? Theme.sage : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .modifier(OptionalKeyboardShortcut(key: column.shortcut))
        // The frame and hit shape belong to the BUTTON, not to the label
        // inside it. Sized from within, the drawn control and the region that
        // actually takes a touch came apart: the reported frame was right, the
        // tappable area was not, and with two controls in the row the first
        // one simply did not respond.
        .frame(width: 44, height: 40)
        .contentShape(Rectangle())
        .accessibilityIdentifier(column.toggleIdentifier)
        .accessibilityLabel(shown ? "Hide the \(column.name)" : "Show the \(column.name)")
        .accessibilityValue(shown ? "Shown" : "Hidden")
        .accessibilityHint(
            shown
                ? "Folds the \(column.name) away and gives the page the full width"
                : "Brings the \(column.name) back"
        )
        .accessibilityAddTraits(shown ? [.isButton, .isSelected] : .isButton)
    }
}

/// The slim chrome row that holds every left-column toggle for the screen,
/// outermost column first. Nothing else lives here: one row, one job, so the
/// control never moves between screens.
struct LeftColumnBar: View {
    let columns: [LeftColumnSpec]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(columns) { column in
                LeftColumnToggle(column: column)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 40)
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Column controls")
    }
}

/// Publishes an inner left column to the shared bar for as long as the screen
/// showing it is on screen and the column applies.
///
/// `active` is false when the screen has no rail to fold — nine Ethics
/// readings have no LOS headings, and a compact width has no room for the rail
/// at all — so the bar must not offer a control for a column that is not there.
extension View {
    func leftColumnControl(_ column: LeftColumnSpec, active: Bool = true) -> some View {
        modifier(LeftColumnRegistration(column: column, active: active))
    }
}

private struct LeftColumnRegistration: ViewModifier {
    @Environment(LeftColumnPreference.self) private var columns

    let column: LeftColumnSpec
    let active: Bool

    func body(content: Content) -> some View {
        content
            .onAppear { sync(active) }
            .onDisappear { columns.unregister(column) }
            .onChange(of: active) { _, isActive in sync(isActive) }
    }

    private func sync(_ isActive: Bool) {
        if isActive {
            columns.register(column)
        } else {
            columns.unregister(column)
        }
    }
}

/// `keyboardShortcut` has no "no shortcut" value, so the absence has to be a
/// branch rather than a nil argument.
private struct OptionalKeyboardShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: [.control, .command])
        } else {
            content
        }
    }
}
