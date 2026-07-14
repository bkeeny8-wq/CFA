import SwiftUI

struct LOSDrillReadingView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator

    let reading: Reading
    let bundle: LOSDrillBundle

    @State private var showSession = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(bundle.totalQuestions) drill questions")
                        .font(.headline)
                    Text("Curriculum-grounded MC drills — one set per LOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)

                Button {
                    let ids = bundle.drills.flatMap { $0.questions.map(\.id) }.shuffled()
                    sessionCoordinator.start(
                        questionIDs: ids,
                        mode: .losDrill,
                        filterDescription: "LOS drills — \(reading.name)"
                    )
                    showSession = true
                } label: {
                    Label("Drill all \(bundle.totalQuestions) (shuffled)", systemImage: "shuffle")
                }
            }

            ForEach(bundle.drills) { group in
                Section("LOS \(group.losLetter.uppercased())") {
                    Text(group.losText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        let ids = group.questions.map(\.id)
                        sessionCoordinator.start(
                            questionIDs: ids,
                            mode: .losDrill,
                            filterDescription: "LOS \(group.losLetter.uppercased()) drill"
                        )
                        showSession = true
                    } label: {
                        Label("Run all \(group.questions.count)", systemImage: "play.fill")
                    }

                    ForEach(group.questions) { drill in
                        NavigationLink {
                            LOSDrillAttemptView(drill: drill)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Q\(drill.number)")
                                    .font(.headline)
                                Text(Formatting.truncatedStem(drill.stem, limit: 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle("LOS Drills")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showSession) {
            DrillSessionRunnerView()
        }
    }
}

struct DrillSessionRunnerView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.dismiss) private var dismiss
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator

    @State private var showSummary = false

    var body: some View {
        Group {
            if showSummary {
                List {
                    Section("Drill session") {
                        Text("\(sessionCoordinator.completedAttemptIDs.count) attempts")
                    }
                    Section {
                        Button("Done") {
                            sessionCoordinator.finish()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                }
            } else if let questionID = sessionCoordinator.currentQuestionID,
                      let drill = content.drillQuestion(id: questionID) {
                LOSDrillAttemptView(
                    drill: drill,
                    standalone: false,
                    sessionProgress: (
                        current: sessionCoordinator.currentIndex + 1,
                        total: sessionCoordinator.questionIDs.count
                    )
                )
                .id(questionID)
            } else {
                ContentUnavailableView("Drill not found", systemImage: "questionmark")
            }
        }
        .navigationTitle(sessionCoordinator.filterDescription)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: sessionCoordinator.currentIndex) { _, newValue in
            if newValue >= sessionCoordinator.questionIDs.count, !sessionCoordinator.questionIDs.isEmpty {
                showSummary = true
            }
        }
    }
}
