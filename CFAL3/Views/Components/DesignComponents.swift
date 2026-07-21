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
                .font(.system(size: size * 0.28, weight: .medium))
        }
        .frame(width: size, height: size)
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
        .animation(.snappy, value: value)
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
