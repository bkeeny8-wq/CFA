import SwiftUI

struct CFACard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.hairline, lineWidth: 0.5)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.cardRadius)
                            .fill(Theme.cardFill)
                    )
            )
    }
}

extension View {
    func cfaCard() -> some View {
        modifier(CFACard())
    }
}

struct StatCard: View {
    let value: String
    let label: String
    var tint: Color? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint ?? .primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(tint ?? .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill((tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.12))
        )
    }
}

struct CapsuleBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(.systemGray5)))
            .foregroundStyle(.secondary)
    }
}

struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(Theme.accent, style: .init(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded()))%")
                // Scales with Dynamic Type instead of being pinned to the
                // ring's diameter, which locked it at ~9pt.
                .font(.system(size: size * 0.28, weight: .medium))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent attempted")
    }
}

/// The app's one progress-bar style: a 7-pt capsule with a visible track,
/// a rounded fill that never renders as a sliver (minimum dot width), a
/// green tint at completion, and animated changes. Replaces the stock
/// 4-pt ProgressView hairline everywhere a mastery/attempt fraction is
/// shown.
struct MasteryBar: View {
    let value: Double            // 0...1
    var height: CGFloat = 7

    private var fraction: Double { max(0, min(1, value)) }
    private var complete: Bool { fraction >= 0.999 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray5))
                if fraction > 0 {
                    Capsule()
                        .fill(complete ? Theme.success : Theme.accent)
                        .frame(width: max(height, geo.size.width * fraction))
                }
            }
        }
        .frame(height: height)
        .modifier(ReduceMotionAnimation(value: value))
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

struct PrimaryCTA: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .foregroundStyle(.white)
    }
}

/// Shared 90s/point clock. Bank essays, drills, and the full-case booklet
/// all read the same target so a sitting cannot disagree with the debrief.
struct PacingTimer: View {
    let startedAt: Date
    let targetSeconds: Int

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startedAt))
            let over = elapsed > targetSeconds
            Label(
                "\(format(elapsed)) / \(format(targetSeconds)) target",
                systemImage: "timer"
            )
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(over ? .orange : .secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pacing")
            .accessibilityValue("\(format(elapsed)) elapsed of \(format(targetSeconds)) target")
            .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func format(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Sitting/study motion: skip the snappy animation when Reduce Motion is on.
func withSittingAnimation(_ reduceMotion: Bool, _ body: () -> Void) {
    if reduceMotion {
        body()
    } else {
        withAnimation(.snappy, body)
    }
}

/// Honors Reduce Motion: mastery bars still move, they just don't animate.
private struct ReduceMotionAnimation<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: V

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.animation(.snappy, value: value)
        }
    }
}
