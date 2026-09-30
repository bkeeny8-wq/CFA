import SwiftUI

/// Business cycle → capital market expectations → asset stances → the trade,
/// one phase at a time. Four layers down a single scrolling page.
///
/// Every string on screen comes from `cycle_map.json` apart from the layer
/// captions and section titles. The content was approved through the content
/// pipeline; corrections arrive as JSON replacements, never as edits here.
struct CycleMapView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(TabRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedPhase = 2          // Late expansion
    @State private var selectedAsset: Int?
    @State private var selectedFramework = 3      // DM equity
    @State private var openMove: Int?

    private var map: CycleMap? { content.cycleMap }

    var body: some View {
        Group {
            if let map, map.phases.indices.contains(selectedPhase) {
                page(map, phase: map.phases[selectedPhase])
            } else {
                ContentUnavailableView(
                    "Cycle Map unavailable",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("cycle_map.json is not in the app bundle.")
                )
                .accessibilityIdentifier("cyclemap.unavailable")
            }
        }
        .background(Theme.paper)
        .navigationTitle("Cycle Map")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func page(_ map: CycleMap, phase: CyclePhase) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                phaseSelector(map)
                layerOne(phase)
                layerTwo(map, phase: phase)
                layerThree(map, phase: phase)
                layerFour(map, phase: phase)
                practiceCTA(map, phase: phase)
            }
            .readableContentWidth(LayoutMetrics.studyReadingMaxWidth)
            .padding()
        }
        .accessibilityIdentifier("cyclemap.page")
    }

    // MARK: - Phase selector

    private func phaseSelector(_ map: CycleMap) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(map.phases.enumerated()), id: \.element.name) { index, phase in
                    Button {
                        withSittingAnimation(reduceMotion) {
                            selectedPhase = index
                            // The open panels belong to the phase you left.
                            selectedAsset = nil
                            openMove = nil
                        }
                    } label: {
                        CycleChip(text: phase.name, selected: index == selectedPhase)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cyclemap.phase.\(index)")
                    .accessibilityAddTraits(index == selectedPhase ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: - Layer 1

    private func layerOne(_ phase: CyclePhase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            layerCaption("LAYER 1 - BUSINESS CYCLE")
            Text(phase.name)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            Text(phase.description)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) { curveBox(phase); taylorBox(phase) }
                VStack(alignment: .leading, spacing: 14) { curveBox(phase); taylorBox(phase) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cfaCard()
    }

    private func curveBox(_ phase: CyclePhase) -> some View {
        VStack(spacing: 6) {
            YieldCurveShape(kind: phase.curveKind)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 150, height: 86)
                .animation(reduceMotion ? nil : .snappy, value: selectedPhase)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.subtleFill))
            Text(phase.curveLabel)
                .font(.caption)
                .foregroundStyle(Theme.dust)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Yield curve: \(phase.curveLabel)")
    }

    private func taylorBox(_ phase: CyclePhase) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("target = r* + πe + 0.5(πe − π*) + 0.5(gap)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.dust)
                .fixedSize(horizontal: false, vertical: true)
            Text(phase.taylor)
                .font(.callout)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.subtleFill))
    }

    // MARK: - Layer 2

    private func layerTwo(_ map: CycleMap, phase: CyclePhase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            layerCaption("LAYER 2 - CAPITAL MARKET EXPECTATIONS")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(map.frameworksStatic.enumerated()), id: \.element.id) { index, f in
                        Button {
                            withSittingAnimation(reduceMotion) { selectedFramework = index }
                        } label: {
                            CycleChip(text: f.label, selected: index == selectedFramework)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cyclemap.framework.\(f.id)")
                        .accessibilityAddTraits(index == selectedFramework ? [.isSelected] : [])
                    }
                }
            }

            if map.frameworksStatic.indices.contains(selectedFramework) {
                let f = map.frameworksStatic[selectedFramework]
                let bars = map.bars(frameworkIndex: selectedFramework, phase: phase)

                HStack(spacing: 8) {
                    Text(f.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    CapsuleBadge(text: "R2")
                }
                Text(f.formula)
                    .font(.caption)
                    .foregroundStyle(Theme.dust)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                        CycleBarRow(bar: bar)
                    }
                    CycleSumRow(bars: bars)
                }
                .padding(.top, 2)

                if let note = map.note(frameworkIndex: selectedFramework, phase: phase) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(f.glossary.enumerated()), id: \.offset) { _, term in
                        CycleGlossaryRow(term: term)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cfaCard()
    }

    // MARK: - Layer 3

    private func layerThree(_ map: CycleMap, phase: CyclePhase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            layerCaption("LAYER 3 - ASSET STANCES")

            FlowRow(spacing: 8) {
                ForEach(Array(map.assets.enumerated()), id: \.offset) { index, asset in
                    let stance = phase.stances.indices.contains(index) ? phase.stances[index] : "N"
                    Button {
                        withSittingAnimation(reduceMotion) {
                            selectedAsset = (selectedAsset == index) ? nil : index
                        }
                    } label: {
                        CycleChip(
                            text: asset,
                            tint: CycleStance.tint(stance),
                            selected: selectedAsset == index,
                            softFill: true
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cyclemap.asset.\(index)")
                    .accessibilityLabel("\(asset), \(CycleStance.label(stance))")
                }
            }

            legend

            if let index = selectedAsset, map.assets.indices.contains(index) {
                assetPanel(map, phase: phase, index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cfaCard()
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(["OW", "N", "UW"], id: \.self) { stance in
                HStack(spacing: 5) {
                    Circle().fill(CycleStance.tint(stance)).frame(width: 7, height: 7)
                    Text(CycleStance.label(stance))
                        .font(.caption2)
                        .foregroundStyle(Theme.dust)
                }
            }
        }
    }

    private func assetPanel(_ map: CycleMap, phase: CyclePhase, index: Int) -> some View {
        let stance = phase.stances.indices.contains(index) ? phase.stances[index] : "N"
        return VStack(alignment: .leading, spacing: 8) {
            if map.assetChains.indices.contains(index) {
                Text(map.assetChains[index])
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if phase.mechanisms.indices.contains(index) {
                Text("\(CycleStance.label(stance)). \(phase.mechanisms[index])")
                    .font(.callout)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if map.assetTraps.indices.contains(index) {
                HStack(alignment: .top, spacing: 4) {
                    Text("Trap:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.danger)
                    Text(map.assetTraps[index])
                        .font(.caption)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.subtleFill))
        .accessibilityIdentifier("cyclemap.assetpanel")
    }

    // MARK: - Layer 4

    private func layerFour(_ map: CycleMap, phase: CyclePhase) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            layerCaption("LAYER 4 - WHAT YOU DO ABOUT IT")
            Text("Each card: WHY the layers above imply it, WHAT the trade is, HOW to build it. Tap to expand.")
                .font(.caption)
                .foregroundStyle(Theme.dust)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(Array(phase.moves.enumerated()), id: \.offset) { index, move in
                moveCard(map, move: move, index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cfaCard()
    }

    private func moveCard(_ map: CycleMap, move: CyclePhaseMove, index: Int) -> some View {
        let isOpen = openMove == index
        let stat = map.movesStatic.indices.contains(index) ? map.movesStatic[index] : nil

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withDisclosureAnimation(reduceMotion) {
                    openMove = isOpen ? nil : index
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(move.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        readingBadge(map, tag: move.readingTag)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.dust)
                            .rotationEffect(.degrees(isOpen ? 0 : -90))
                    }
                    Text("What: \(move.what)")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cyclemap.move.\(index)")
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    labelled("Why (from the layers above)", move.why)
                    if let stat { labelled("In plain English", stat.plain) }
                    labelled("This phase", move.how)

                    if let stat {
                        Text(stat.worked)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.subtleFill))

                        ForEach(Array(stat.terms.enumerated()), id: \.offset) { _, term in
                            CycleGlossaryRow(term: term)
                        }

                        HStack(alignment: .top, spacing: 4) {
                            Text("Trap:")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.danger)
                            Text(stat.trap)
                                .font(.caption)
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text(stat.exam)
                            .font(.caption)
                            .italic()
                            .foregroundStyle(Theme.dust)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("cyclemap.move.\(index).body")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cardFill))
    }

    private func labelled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.accent)
            Text(text)
                .font(.callout)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The reading tag is a button when it resolves to a reading the app has,
    /// and plain text when it does not — rather than a control that looks
    /// tappable and does nothing.
    @ViewBuilder
    private func readingBadge(_ map: CycleMap, tag: String) -> some View {
        if let target = CycleMapLinks.reading(forTag: tag, map: map, content: content) {
            NavigationLink {
                StudyReadingDetailView(area: target.area, reading: target.reading)
            } label: {
                CapsuleBadge(text: tag)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cyclemap.reading.\(tag)")
            .accessibilityLabel("Open \(target.reading.name)")
        } else {
            CapsuleBadge(text: tag)
        }
    }

    // MARK: - Practice

    @ViewBuilder
    private func practiceCTA(_ map: CycleMap, phase: CyclePhase) -> some View {
        let ids = CycleMapLinks.practiceQuestionIDs(phase: phase, map: map, content: content)
        Button {
            guard !ids.isEmpty else { return }
            // Same wiring as CaseDetailView's "Sit this case as a mock":
            // mode .random over explicit ids, presented through the router's
            // full-window cover rather than a second push mechanism.
            sessionCoordinator.start(
                questionIDs: ids,
                mode: .random,
                filterDescription: "Cycle Map: \(phase.name)"
            )
            router.presentQuestionSitting()
        } label: {
            Text(ids.isEmpty ? "No matching questions" : "Practice this phase: \(phase.name)")
        }
        .buttonStyle(PrimaryCTA())
        .disabled(ids.isEmpty)
        .accessibilityIdentifier("cyclemap.practice")
        .accessibilityHint(ids.isEmpty ? "" : "\(ids.count) questions")
    }

    private func layerCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.accent)
    }
}
