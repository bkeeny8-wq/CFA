import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(PracticeBuilderPreference.self) private var practicePref
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \ReviewCard.dueDate) private var reviewCards: [ReviewCard]
    @Query(sort: \Attempt.timestamp, order: .reverse) private var attempts: [Attempt]
    @Query private var losStatuses: [LOSStudyStatus]

    @State private var showSession = false

    private let reviewSessionCap = 60

    private var dueToday: Int {
        reviewCards.filter { $0.dueDate <= .now }.count
    }

    private var weakestTopics: [TopicProgress] {
        ProgressStats.weakestTopics(content: content, attempts: attempts)
    }

    var body: some View {
        List {
            if horizontalSizeClass == .regular {
                Section {
                    HStack(alignment: .top, spacing: 24) {
                        countdownCard
                        dueTodayCard
                    }
                }
            } else {
                Section {
                    countdownCard
                }
                Section {
                    dueTodayCard
                }
            }

            Section("Streak") {
                Text("\(ProgressStats.streakDays(attempts: attempts)) day streak")
                    .font(.title3)
            }

            if let master = content.losMaster {
                let losOverall = StudyPlannerStats.overall(master: master, statuses: losStatuses)
                Section("LOS Study Pal") {
                    NavigationLink {
                        StudyPlannerView()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(losOverall.mastered)/\(losOverall.total) statements mastered")
                            ProgressView(value: losOverall.total == 0 ? 0 : Double(losOverall.mastered) / Double(losOverall.total))
                                .tint(Theme.accent)
                        }
                    }
                }
            }

            if !weakestTopics.isEmpty {
                Section("Weakest topics") {
                    ForEach(weakestTopics, id: \.topicID) { topic in
                        NavigationLink {
                            CaseListView(topicID: topic.topicID)
                        } label: {
                            HStack {
                                Text(topic.name)
                                Spacer()
                                Text(Formatting.percent(topic.correctRate))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            #if DEBUG
            Section("Debug") {
                NavigationLink("Content stats") {
                    ContentStatsView()
                }
            }
            #endif

            Section {
                NavigationLink("Settings") {
                    SettingsView()
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: horizontalSizeClass == .regular ? 960 : .infinity)
        .frame(maxWidth: .infinity)
        .navigationTitle("Home")
        .navigationDestination(isPresented: $showSession) {
            SessionRunnerView()
        }
    }

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Days until exam")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(Formatting.daysUntilExam())")
                .font(.system(size: horizontalSizeClass == .regular ? 64 : 56, weight: .bold, design: .rounded))
            Text("Feb 20, 2027")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dueTodayCard: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Due today")
                    .font(.headline)
                Text(dueToday > reviewSessionCap
                     ? "\(dueToday) due - next session: \(reviewSessionCap)"
                     : "\(dueToday) cards")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Start review") {
                startReviewDue()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(dueToday == 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func applyTypeFilter(_ ids: [String]) -> [String] {
        ids.filter { qid in
            if let q = content.question(id: qid) {
                return practicePref.typeFilter.allows(q.type)
                    && (q.type != .mc || q.canGradeMC)
            }
            if let d = content.drillQuestion(id: qid) {
                return practicePref.typeFilter.allows(d.type) && d.correct != nil
            }
            return false
        }
    }

    private func startReviewDue() {
        let due = reviewCards.filter { $0.dueDate <= .now }.map(\.questionId)
        let filtered = Array(applyTypeFilter(due).prefix(reviewSessionCap))
        guard !filtered.isEmpty else { return }
        sessionCoordinator.start(
            questionIDs: filtered,
            mode: .reviewDue,
            filterDescription: "Due review"
        )
        showSession = true
    }
}
