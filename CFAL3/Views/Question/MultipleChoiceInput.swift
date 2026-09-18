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
                        Image(systemName: selected == key ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected == key ? Theme.pine : Theme.dust)
                        Text("**\(key).** \(options[key] ?? "")")
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(Theme.ink)
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selected == key ? Theme.sage : Theme.cardFill)
                            .shadow(color: Color.black.opacity(selected == key ? 0 : 0.04), radius: 8, y: 2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected == key ? Theme.pine.opacity(0.35) : Theme.pine.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Option \(key). \(options[key] ?? "")")
                .accessibilityAddTraits(selected == key ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
