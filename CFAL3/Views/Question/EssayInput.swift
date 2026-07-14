import SwiftUI

struct EssayInput: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                .frame(minHeight: 220)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.25))
                )
            Text("\(Formatting.wordCount(text)) words")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
