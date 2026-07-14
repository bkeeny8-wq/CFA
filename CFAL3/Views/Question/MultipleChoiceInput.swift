import SwiftUI

struct MultipleChoiceInput: View {
    let options: [String: String]
    let sortedKeys: [String]
    @Binding var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sortedKeys, id: \.self) { key in
                Button {
                    selected = key
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selected == key ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Theme.accent)
                        Text("**\(key).** \(options[key] ?? "")")
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(selected == key ? Theme.accent.opacity(0.12) : Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
