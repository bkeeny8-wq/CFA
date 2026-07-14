import SwiftUI

struct VignetteView: View {
    let vignette: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(isExpanded ? "Hide vignette" : "Show vignette") {
                withAnimation { isExpanded.toggle() }
            }
            .font(.subheadline)

            if isExpanded {
                if let attributed = try? AttributedString(markdown: vignette) {
                    Text(attributed)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    Text(vignette)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
