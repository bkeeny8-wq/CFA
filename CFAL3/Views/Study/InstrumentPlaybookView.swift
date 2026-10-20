import SwiftUI

/// Every instrument the curriculum covers: what it is good for, what it costs
/// you, when to recommend it, when not to, and what a vignette is signalling
/// when it plants a constraint.
///
/// Laid out like Command words, which is the pattern this app already uses for
/// "a list of things, one open at a time": a permanent left column of
/// instruments grouped by family, and the page beside it. No fold control, for
/// the same reason as there: the list IS the navigation.
struct InstrumentPlaybookView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedKey: String?
    /// Keys pinned into the comparison, in the order they were added. Empty
    /// means the normal single-instrument page.
    @State private var comparing: [String] = []

    private var playbook: InstrumentPlaybook? { content.playbook }

    /// The list is a column only where there is room for one beside the page.
    private var listIsColumn: Bool { horizontalSizeClass == .regular }

    private var selected: PlaybookInstrument? {
        guard let playbook, let key = selectedKey else { return nil }
        return playbook.instrument(key)
    }

    var body: some View {
        Group {
            if let playbook, !playbook.instruments.isEmpty {
                if listIsColumn { splitLayout(playbook) } else { stackLayout(playbook) }
            } else {
                ContentUnavailableView(
                    "Playbook unavailable",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text(
                        content.loadError
                            ?? "instrument_playbook.json is not in the app bundle."
                    )
                )
                .accessibilityIdentifier("playbook.unavailable")
            }
        }
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle("Instruments")
        .onAppear {
            if selectedKey == nil { selectedKey = playbook?.instruments.first?.key }
        }
    }

    // MARK: - Layout

    private func splitLayout(_ playbook: InstrumentPlaybook) -> some View {
        HStack(spacing: 0) {
            instrumentList(playbook)
                .frame(width: 250)
            Rectangle()
                .fill(Theme.pine.opacity(0.1))
                .frame(width: 1)
                .ignoresSafeArea()
            page(playbook)
        }
    }

    private func stackLayout(_ playbook: InstrumentPlaybook) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                generatedNotice
                instrumentChips(playbook)
                if !comparing.isEmpty {
                    comparison(playbook)
                } else if let selected {
                    detail(selected, playbook: playbook)
                }
            }
            .readableContentWidth(LayoutMetrics.studyReadingMaxWidth)
            .padding()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Instruments")
                .font(Theme.serif(.largeTitle, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityIdentifier("playbook.library")
            Text("What each one buys you, what it costs, and when to recommend it.")
                .font(.subheadline)
                .foregroundStyle(Theme.dust)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The list

    private func instrumentList(_ playbook: InstrumentPlaybook) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header.padding(.horizontal, 4)

                ForEach(playbook.populatedFamilies, id: \.self) { family in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(family.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 4)

                        ForEach(playbook.instruments(inFamily: family)) { instrument in
                            listRow(instrument)
                        }
                    }
                }
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("playbook.list")
    }

    private func listRow(_ instrument: PlaybookInstrument) -> some View {
        let isSelected = selectedKey == instrument.key && comparing.isEmpty
        let isPinned = comparing.contains(instrument.key)
        return Button {
            withSittingAnimation(reduceMotion) {
                if comparing.isEmpty {
                    selectedKey = instrument.key
                } else {
                    toggleComparison(instrument.key)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(instrument.name)
                    .font(.subheadline.weight(isSelected || isPinned ? .semibold : .regular))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if isPinned {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected || isPinned ? Theme.sage : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("playbook.item.\(instrument.key)")
        .accessibilityAddTraits(isSelected || isPinned ? [.isSelected] : [])
    }

    /// Compact width has no column, so the list collapses to a chip row.
    private func instrumentChips(_ playbook: InstrumentPlaybook) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(playbook.instruments) { instrument in
                    Button {
                        withSittingAnimation(reduceMotion) { selectedKey = instrument.key }
                    } label: {
                        CycleChip(text: instrument.name, selected: selectedKey == instrument.key)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("playbook.chip.\(instrument.key)")
                }
            }
        }
    }

    // MARK: - The page

    @ViewBuilder
    private func page(_ playbook: InstrumentPlaybook) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                generatedNotice
                if !comparing.isEmpty {
                    comparison(playbook)
                } else if let selected {
                    detail(selected, playbook: playbook)
                }
            }
            .readableContentWidth(LayoutMetrics.studyReadingMaxWidth)
            .padding(24)
        }
        .accessibilityIdentifier("playbook.page")
    }

    /// Stated once per page, not buried in a per entry badge.
    ///
    /// Every other tab's content was supplied: the notes are the reader's own,
    /// the Meldrum PDFs are purchased coursework, the cycle map was authored to
    /// a brief. This section is the only GENERATED content in the app, and the
    /// fact check pass that produced it found real errors in the first draft of
    /// every entry it examined. Saying so is not a disclaimer for its own sake:
    /// it is the difference between a page the reader checks and a page the
    /// reader memorises.
    private var generatedNotice: some View {
        Label(
            "Generated from your notes and standard curriculum, then fact checked. "
                + "Not curriculum text. Check anything that decides an answer.",
            systemImage: "wand.and.stars"
        )
        .font(.caption2)
        .foregroundStyle(Theme.dust)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("playbook.generated")
    }

    private func detail(_ instrument: PlaybookInstrument, playbook: InstrumentPlaybook) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(instrument.name)
                    .font(Theme.serif(.largeTitle, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(instrument.summary)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                provenance(instrument)
            }
            .accessibilityIdentifier("playbook.page.\(instrument.key)")

            compareBar(instrument, playbook: playbook)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    pointCard("Pros", instrument.pros, tint: Theme.success)
                    pointCard("Cons", instrument.cons, tint: Theme.danger)
                }
                VStack(spacing: 12) {
                    pointCard("Pros", instrument.pros, tint: Theme.success)
                    pointCard("Cons", instrument.cons, tint: Theme.danger)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    listCard("Recommend it when", instrument.whenToRecommend, tint: Theme.success)
                    listCard("Do not, when", instrument.whenNotTo, tint: Theme.danger)
                }
                VStack(spacing: 12) {
                    listCard("Recommend it when", instrument.whenToRecommend, tint: Theme.success)
                    listCard("Do not, when", instrument.whenNotTo, tint: Theme.danger)
                }
            }

            if !instrument.cues.isEmpty { cueCard(instrument.cues) }
            if !instrument.pitfalls.isEmpty {
                listCard("Pitfalls and tricks", instrument.pitfalls, tint: Theme.warning)
            }
        }
    }

    /// How much of the entry came from the reader's own notes.
    ///
    /// Shown because this section is generated rather than supplied, and a
    /// reader is entitled to know which claims their notes already made.
    @ViewBuilder
    private func provenance(_ instrument: PlaybookInstrument) -> some View {
        HStack(spacing: 8) {
            CapsuleBadge(text: "\(instrument.pointsFromNotes) of \(instrument.totalPoints) from your notes")
            if !instrument.isHighConfidence {
                Text("Check this one against the curriculum")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.warning)
            }
        }
        .accessibilityIdentifier("playbook.provenance.\(instrument.key)")
    }

    // MARK: - Compare

    private func compareBar(_ instrument: PlaybookInstrument, playbook: InstrumentPlaybook) -> some View {
        let siblings = instrument.comparesWith.compactMap { playbook.instrument($0) }
        return VStack(alignment: .leading, spacing: 8) {
            if !siblings.isEmpty {
                Text("Compare with")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                FlowRow(spacing: 8) {
                    ForEach(siblings) { sibling in
                        Button {
                            withSittingAnimation(reduceMotion) {
                                comparing = [instrument.key, sibling.key]
                            }
                        } label: {
                            CycleChip(text: sibling.name, selected: false)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("playbook.compare.\(sibling.key)")
                        .accessibilityLabel("Compare with \(sibling.name)")
                    }
                }
            }
        }
    }

    private func comparison(_ playbook: InstrumentPlaybook) -> some View {
        let picked = comparing.compactMap { playbook.instrument($0) }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Comparing")
                    .font(Theme.serif(.title2, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    withSittingAnimation(reduceMotion) { comparing = [] }
                } label: {
                    Text("Done")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playbook.compare.done")
            }

            Text("Tap any instrument on the left to add or remove it.")
                .font(.caption)
                .foregroundStyle(Theme.dust)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(picked) { instrument in
                        comparisonColumn(instrument)
                    }
                }
            }
            .accessibilityIdentifier("playbook.comparison")
        }
    }

    private func comparisonColumn(_ instrument: PlaybookInstrument) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(instrument.name)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(instrument.summary)
                .font(.caption)
                .foregroundStyle(Theme.dust)
                .fixedSize(horizontal: false, vertical: true)

            comparisonSection("Pros", instrument.pros.map(\.text), tint: Theme.success)
            comparisonSection("Cons", instrument.cons.map(\.text), tint: Theme.danger)
            comparisonSection("Recommend when", instrument.whenToRecommend, tint: Theme.accent)
            comparisonSection("Not when", instrument.whenNotTo, tint: Theme.danger)
        }
        .frame(width: 300, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.cardFill))
        .accessibilityIdentifier("playbook.comparison.\(instrument.key)")
    }

    private func comparisonSection(_ title: String, _ items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(tint).frame(width: 4, height: 4).padding(.top, 6)
                    Text(item)
                        .font(.caption)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func toggleComparison(_ key: String) {
        if let index = comparing.firstIndex(of: key) {
            comparing.remove(at: index)
            if comparing.count < 2 { comparing = [] }
        } else {
            comparing.append(key)
        }
    }

    // MARK: - Cards

    private func pointCard(_ title: String, _ points: [PlaybookPoint], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(tint).frame(width: 5, height: 5).padding(.top, 7)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.text)
                            .font(.callout)
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !point.isFromNotes {
                            Text("curriculum")
                                .font(.caption2)
                                .foregroundStyle(Theme.dust)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cfaCard()
    }

    private func listCard(_ title: String, _ items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(tint).frame(width: 5, height: 5).padding(.top, 7)
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cfaCard()
    }

    /// Signal on the left, what it rules in or out on the right.
    private func cueCard(_ cues: [PlaybookCue]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("If the vignette says this")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.accent)
            ForEach(Array(cues.enumerated()), id: \.offset) { _, cue in
                VStack(alignment: .leading, spacing: 3) {
                    Text(cue.signal)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 2)
                        Text(cue.implication)
                            .font(.callout)
                            .foregroundStyle(Theme.dust)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cfaCard()
    }
}
