import SwiftUI
import SwiftData

/// Sitting-cover booklet: pinned vignette, Check answer / Skip & flag, named
/// ratings. The case sitting is started by the presenter before this appears.
struct CaseAnswerSheetView: View {
    let caseStudy: CaseStudy

    var body: some View {
        SessionRunnerView()
            .accessibilityLabel("Booklet sitting for \(caseStudy.title)")
    }
}
