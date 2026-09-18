import SwiftUI

struct EssayInput: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .frame(minHeight: 220)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.25))
                    )
                    .accessibilityLabel("Essay answer")
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write your answer")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            Text("\(Formatting.wordCount(text)) words")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(Formatting.wordCount(text)) words written")
        }
    }
}
