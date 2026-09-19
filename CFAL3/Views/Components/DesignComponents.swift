import SwiftUI
import SwiftData

struct CFACard: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.cardFill)
                    .shadow(color: Color.black.opacity(0.06), radius: 18, y: 6)
            )
    }
}

extension View {
    func cfaCard(radius: CGFloat = Theme.cardRadius, padding: CGFloat = 18) -> some View {
        modifier(CFACard(radius: radius, padding: padding))
    }

    func daybookPaper() -> some View {
        background(Theme.paper.ignoresSafeArea())
    }
}

struct StatCard: View {
    let value: String
    let label: String
    var tint: Color? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.serif(.title3, weight: .semibold))
                .foregroundStyle(tint ?? Theme.ink)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(tint ?? Theme.dust)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardFill)
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 3)
        )
    }
}

struct CapsuleBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.sage))
            .foregroundStyle(Theme.pine)
    }
}

struct ProgressRing: View {
    let fraction: Double
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.pine.opacity(0.15), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(Theme.pine, style: .init(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: size * 0.28, weight: .medium))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent attempted")
    }
}

struct MasteryBar: View {
    let value: Double
    var height: CGFloat = 7

    private var fraction: Double { max(0, min(1, value)) }
    private var complete: Bool { fraction >= 0.999 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.pine.opacity(0.12))
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
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.pine.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .foregroundStyle(.white)
    }
}

struct CompactCTA: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(Theme.pine.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .foregroundStyle(.white)
    }
}

struct PacingTimer: View {
    let startedAt: Date
    let targetSeconds: Int
    var compact: Bool = false

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startedAt))
            let over = elapsed > targetSeconds
            let label = compact
                ? "\(format(elapsed)) / \(format(targetSeconds))"
                : "\(format(elapsed)) / \(format(targetSeconds)) target"
            Text(label)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(over ? Theme.copper : Theme.dust)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pacing")
                .accessibilityValue("\(spoken(elapsed)) elapsed of \(spoken(targetSeconds)) target")
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private func format(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    private func spoken(_ s: Int) -> String {
        let minutes = s / 60
        let seconds = s % 60
        if minutes == 0 { return "\(seconds) seconds" }
        if seconds == 0 {
            return minutes == 1 ? "1 minute" : "\(minutes) minutes"
        }
        let minuteWord = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        return "\(minuteWord) \(seconds) seconds"
    }
}

func withSittingAnimation(_ reduceMotion: Bool, _ body: () -> Void) {
    if reduceMotion {
        body()
    } else {
        withAnimation(.snappy, body)
    }
}

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

// MARK: - Sitting chrome

struct SittingDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<max(total, 0), id: \.self) { index in
                let isCurrent = index == current - 1
                let isFilled = index < current
                Circle()
                    .fill(isFilled ? Theme.pine : Color.clear)
                    .overlay(
                        Circle().stroke(Theme.pine.opacity(isCurrent || isFilled ? 1 : 0.28), lineWidth: 2)
                    )
                    .frame(width: isCurrent ? 12 : 10, height: isCurrent ? 12 : 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(current) of \(total)")
    }
}

struct SittingTopBar: View {
    let title: String
    var progressCurrent: Int
    var progressTotal: Int
    var showDots: Bool
    var hideStem: Binding<Bool>?
    var flagged: Bool
    var onFlag: (() -> Void)?
    var onEnd: () -> Void
    var clock: (startedAt: Date, targetSeconds: Int)?
    var status: String? = nil
    var showsMeter: Bool = true
    var progressAccessibilityIdentifier: String? = nil
    var progressAccessibilityLabel: String? = nil
    var flagIdentifier: String = "attempt.flag"
    var onSkip: (() -> Void)? = nil
    var skipIdentifier: String = "attempt.skip"

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: onEnd) {
                    Label("End sitting", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.pine)
                }
                .accessibilityIdentifier("sitting.end")

                Spacer(minLength: 8)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .accessibilityIdentifier(progressAccessibilityIdentifier ?? "sitting.title")
                        .accessibilityLabel(progressAccessibilityLabel ?? title)
                    if !showDots && showsMeter {
                        Text("\(progressCurrent) of \(progressTotal)")
                            .font(.caption)
                            .foregroundStyle(Theme.dust)
                            .accessibilityLabel("Question \(progressCurrent) of \(progressTotal)")
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    if let status {
                        Text(status)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.dust)
                            .lineLimit(1)
                    }
                    if let clock {
                        PacingTimer(
                            startedAt: clock.startedAt,
                            targetSeconds: clock.targetSeconds,
                            compact: true
                        )
                    }
                    if let onSkip {
                        Button(AttemptHost.skipTitle, action: onSkip)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.copper)
                            .accessibilityIdentifier(skipIdentifier)
                    }
                    if let onFlag {
                        Button(action: onFlag) {
                            Image(systemName: flagged ? "flag.fill" : "flag")
                                .foregroundStyle(Theme.pine)
                        }
                        .accessibilityLabel(flagged ? "Remove review flag" : "Flag for review")
                        .accessibilityIdentifier(flagIdentifier)
                    }
                }
            }

            if showsMeter {
                HStack {
                    if showDots {
                        SittingDots(current: progressCurrent, total: progressTotal)
                        Spacer()
                    } else {
                        MasteryBar(
                            value: progressTotal == 0 ? 0 : Double(progressCurrent) / Double(progressTotal)
                        )
                        .frame(maxWidth: 280)
                        Spacer()
                    }
                    if let hideStem {
                        Toggle("Hide stem", isOn: hideStem)
                            .labelsHidden()
                            .tint(Theme.pine)
                            .accessibilityLabel("Hide stem")
                        Text("Hide stem")
                            .font(.caption)
                            .foregroundStyle(Theme.dust)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.cardFill.opacity(0.92))
                .shadow(color: Color.black.opacity(0.06), radius: 16, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// Same four named ratings as flashcards (Again / Hard / Good / Easy).
enum ReviewRating: Int, CaseIterable {
    case again = 1
    case hard = 3
    case good = 4
    case easy = 5

    var label: String {
        switch self {
        case .again: return "Again"
        case .hard: return "Hard"
        case .good: return "Good"
        case .easy: return "Easy"
        }
    }

    var tint: Color {
        switch self {
        case .again: return Theme.copper
        case .hard: return Theme.dust
        case .good: return Theme.pine
        case .easy: return Theme.pine
        }
    }

    static func nearest(_ quality: Int) -> ReviewRating {
        switch quality {
        case ...2: return .again
        case 3: return .hard
        case 5: return .easy
        default: return .good
        }
    }
}

struct NamedQualitySelector: View {
    @Binding var selected: Int
    var card: ReviewCard?
    var enabled: Bool = true
    var accessibilityPrefix: String = "result"

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ReviewRating.allCases, id: \.rawValue) { rating in
                Button {
                    selected = rating.rawValue
                } label: {
                    VStack(spacing: 2) {
                        Text(rating.label)
                            .font(.footnote.weight(.semibold))
                        Text(intervalLabel(for: rating))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.dust)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(rating.tint.opacity(selected == rating.rawValue ? 1 : 0.35), lineWidth: 1.5)
                    )
                    .foregroundStyle(rating.tint)
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.45)
                .frame(minHeight: 44)
                .accessibilityLabel("\(rating.label), \(intervalLabel(for: rating))")
                .accessibilityIdentifier("\(accessibilityPrefix).rate.\(rating.label.lowercased())")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(enabled ? "Rate this question" : "Rate after you check")
    }

    private func intervalLabel(for rating: ReviewRating) -> String {
        guard let card else { return rating == .again ? "10m" : "1d" }
        let days = ReviewScheduler.previewInterval(item: card, quality: rating.rawValue)
        if rating == .again, days <= 1 { return "10m" }
        return "\(days)d"
    }
}

struct DaybookLoadErrorPanel: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Content couldn’t load")
                .font(Theme.serif(.title2, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Theme.dust)
            Button("Retry", action: retry)
                .buttonStyle(CompactCTA())
        }
        .frame(maxWidth: 520, alignment: .leading)
        .cfaCard()
        .padding()
    }
}
