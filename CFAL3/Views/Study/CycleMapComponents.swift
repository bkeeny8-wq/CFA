import SwiftUI

/// The yield curve sketch in Layer 1.
///
/// Five fixed shapes, one per `curve_kind`, traced from the approved mockup's
/// SVG paths in its own 150x86 box and scaled to whatever the view gives them.
/// Deliberately not derived from any data: this is an icon of the curve's
/// shape, not a plot of it.
struct YieldCurveShape: Shape {
    let kind: String

    /// Control points in the mockup's 150x86 coordinate space:
    /// start, control 1, control 2, end.
    private static let designSize = CGSize(width: 150, height: 86)

    private static let paths: [String: (CGPoint, CGPoint, CGPoint, CGPoint)] = [
        "steep":    (CGPoint(x: 14, y: 66), CGPoint(x: 50, y: 58), CGPoint(x: 90, y: 34), CGPoint(x: 144, y: 16)),
        "flatten":  (CGPoint(x: 14, y: 58), CGPoint(x: 50, y: 46), CGPoint(x: 95, y: 34), CGPoint(x: 144, y: 26)),
        "flat":     (CGPoint(x: 14, y: 42), CGPoint(x: 55, y: 39), CGPoint(x: 100, y: 37), CGPoint(x: 144, y: 36)),
        "inverted": (CGPoint(x: 14, y: 28), CGPoint(x: 55, y: 36), CGPoint(x: 100, y: 44), CGPoint(x: 144, y: 48)),
        "resteep":  (CGPoint(x: 14, y: 44), CGPoint(x: 48, y: 48), CGPoint(x: 92, y: 34), CGPoint(x: 144, y: 18)),
    ]

    /// Animating a Shape means animating its data; without this the curve
    /// would cut between phases instead of bending.
    var animatableData: AnimatablePair<
        AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>,
        AnimatablePair<CGPoint.AnimatableData, CGPoint.AnimatableData>
    > {
        get {
            let p = Self.points(for: kind)
            return AnimatablePair(
                AnimatablePair(p.0.animatableData, p.1.animatableData),
                AnimatablePair(p.2.animatableData, p.3.animatableData)
            )
        }
        set { /* driven by `kind`; the setter exists to satisfy the protocol */ }
    }

    private static func points(for kind: String) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
        paths[kind] ?? paths["flat"]!
    }

    func path(in rect: CGRect) -> Path {
        let p = Self.points(for: kind)
        let sx = rect.width / Self.designSize.width
        let sy = rect.height / Self.designSize.height
        func scale(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * sx, y: rect.minY + point.y * sy)
        }
        var path = Path()
        path.move(to: scale(p.0))
        path.addCurve(to: scale(p.3), control1: scale(p.1), control2: scale(p.2))
        return path
    }
}

/// One signed bar in a framework's build-up.
///
/// Width is proportional to magnitude and capped, so a single outsized
/// component cannot push the row off the card. Negative components — a
/// repricing drag, a falling cap rate — carry real meaning here, so they get
/// their own tint rather than being drawn as if they added.
struct CycleBarRow: View {
    let bar: CycleBar
    /// Points per unit, from the mockup.
    static let pointsPerUnit: CGFloat = 22
    static let maxWidth: CGFloat = 120

    private var width: CGFloat {
        min(Self.maxWidth, max(2, abs(bar.value) * Self.pointsPerUnit))
    }

    private var tint: Color { bar.value < 0 ? Theme.danger : Theme.accent }

    var body: some View {
        HStack(spacing: 10) {
            Text(bar.label)
                .font(.caption)
                .foregroundStyle(Theme.dust)
                .frame(width: 120, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Capsule()
                .fill(tint.opacity(bar.value < 0 ? 0.45 : 0.85))
                .frame(width: width, height: 10)

            Spacer(minLength: 4)

            Text(Self.signed(bar.value))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bar.label), \(Self.signed(bar.value))")
    }

    static func signed(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        let magnitude = String(format: "%.1f", abs(rounded))
        // A minus sign, not a hyphen, to match the approved content.
        return rounded < 0 ? "−\(magnitude)%" : "+\(magnitude)%"
    }
}

/// The total under the bars, above a hairline.
struct CycleSumRow: View {
    let bars: [CycleBar]

    private var total: Double { bars.reduce(0) { $0 + $1.value } }

    var body: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(Theme.ink.opacity(0.12))
                .frame(height: 0.5)
            HStack {
                Text("Expected return")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(CycleBarRow.signed(total))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Expected return \(CycleBarRow.signed(total))")
    }
}

/// Term on the left, definition on the right.
struct CycleGlossaryRow: View {
    let term: CycleGlossaryTerm

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(term.term)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.dust)
                .frame(width: 130, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(term.definition)
                .font(.caption)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// OW / N / UW, with the tints the legend explains.
enum CycleStance {
    static func tint(_ stance: String) -> Color {
        switch stance {
        case "OW": return Theme.success
        case "UW": return Theme.danger
        default: return Theme.dust
        }
    }

    static func label(_ stance: String) -> String {
        switch stance {
        case "OW": return "Overweight"
        case "UW": return "Underweight"
        default: return "Neutral"
        }
    }
}

/// A selectable capsule: the phase chips, the framework chips, the asset chips.
struct CycleChip: View {
    let text: String
    var tint: Color = Theme.accent
    var selected: Bool
    /// Asset chips carry a soft stance tint even when unselected; the phase
    /// and framework chips do not.
    var softFill: Bool = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(selected ? .white : tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            // 44pt targets: these sit in rows of eight or nine.
            .frame(minHeight: 44)
            .background(
                Capsule().fill(
                    selected ? tint : (softFill ? tint.opacity(0.12) : Theme.subtleFill)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    selected ? tint : Color.clear,
                    lineWidth: selected ? 0 : 1
                )
            )
            .contentShape(Capsule())
    }
}

/// Wrapping row of chips.
///
/// Layer 3 shows nine asset chips whose widths depend on their labels and on
/// Dynamic Type, so neither a fixed grid nor a horizontal ScrollView is right:
/// a grid leaves ragged gaps and a scroller hides half the assets behind a
/// gesture with nothing to suggest it. This wraps to as many lines as it needs.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
