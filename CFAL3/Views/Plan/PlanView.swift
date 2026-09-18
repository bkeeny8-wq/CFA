import SwiftUI
import SwiftData

struct PlanView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var completions: [DayCompletion]

    private var schedule: StudySchedule? { content.schedule }

    private var completionByDate: [String: DayCompletion] {
        Dictionary(uniqueKeysWithValues: completions.map { ($0.dateKey, $0) })
    }

    private var todayKey: String { StudySchedule.dateKey(for: .now) }

    var body: some View {
        Group {
            if let schedule {
                planContent(schedule)
            } else {
                ContentUnavailableView(
                    "No study calendar",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("The study calendar isn't in this copy. Reinstall the app from the project.")
                )
            }
        }
        .navigationTitle("Plan")
        // Pushed from Home now, and it opens already scrolled to today — a
        // large title would collapse before it ever renders, leaving a bare bar.
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: horizontalSizeClass == .regular ? 960 : .infinity)
        .frame(maxWidth: .infinity)
        // Paint the grouped colour across the FULL window, not just the capped
        // content. Measured on a 1032pt iPad before this: white (255,255,255)
        // outside, grouped grey (242,242,247) inside, meeting as two hard
        // vertical seams at x=36 and x=996 — the same defect Practice had. The
        // other half of the fix is on the List itself, which otherwise keeps
        // painting its own background inside the 960pt frame.
        .background(Color(.systemGroupedBackground))
    }

    @ViewBuilder
    private func planContent(_ schedule: StudySchedule) -> some View {
        let plannedToDate = ScheduleProgress.plannedToDate(schedule: schedule)
        let completed = ScheduleProgress.completedHours(completions: completions)
        let delta = ScheduleProgress.delta(schedule: schedule, completions: completions)
        let sections = ScheduleProgress.weekSections(for: schedule.days)

        VStack(spacing: 0) {
            header(
                schedule: schedule,
                plannedToDate: plannedToDate,
                completed: completed,
                delta: delta
            )
            .padding()

            ScrollViewReader { proxy in
                List {
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.days) { day in
                                dayRow(day, schedule: schedule)
                                    .id(day.date)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                // Let the window behind it supply the grouped colour; drawing
                // its own only inside the 960pt cap is what produced the seams.
                .scrollContentBackground(.hidden)
                .onAppear {
                    DispatchQueue.main.async {
                        withSittingAnimation(reduceMotion) {
                            proxy.scrollTo(todayKey, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func header(
        schedule: StudySchedule,
        plannedToDate: Double,
        completed: Double,
        delta: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatCard(
                    value: Formatting.hours(plannedToDate),
                    label: "Planned"
                )
                StatCard(
                    value: Formatting.hours(completed),
                    label: "Completed"
                )
                StatCard(
                    value: deltaLabel(delta),
                    label: "Delta",
                    tint: deltaTint(delta)
                )
            }

            Text("\(Formatting.hours(schedule.totalPlannedHours, precise: true)) plan · \(Formatting.daysUntilExam()) days to exam")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dayRow(_ day: ScheduleDay, schedule: StudySchedule) -> some View {
        let isToday = day.date == todayKey
        let isDone = completionByDate[day.date] != nil

        if day.isRestDay {
            HStack {
                dayTitle(day)
                Spacer()
                Text(day.note ?? "Rest")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(isToday ? todayBackground : nil)
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        dayTitle(day)
                        Spacer()
                        Text(Formatting.hours(day.hours))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let note = day.note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(day.blocks) { block in
                        blockLine(block)
                    }
                }

                Button {
                    toggleCompletion(for: day)
                } label: {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isDone ? Theme.success : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDone ? "Mark incomplete" : "Mark done")
            }
            .listRowBackground(isToday ? todayBackground : nil)
        }
    }

    private var todayBackground: some View {
        Theme.accent.opacity(0.08)
    }

    private func dayTitle(_ day: ScheduleDay) -> some View {
        let label: String
        if let date = day.parsedDate {
            label = "\(weekdayFormatter.string(from: date)) · \(shortDateFormatter.string(from: date))"
        } else {
            label = day.date
        }
        return Text(label)
            .font(.subheadline.weight(.medium))
    }

    @ViewBuilder
    private func blockLine(_ block: ScheduleBlock) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let book = block.book {
                Circle()
                    .fill(Theme.bookColor(book))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
            }
            if let match = content.reading(id: block.readingID) {
                NavigationLink {
                    StudyReadingDetailView(area: match.area, reading: match.reading)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(block.start) · \(block.minutes) min · \(block.label)")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("\(block.start) · \(block.minutes) min · \(block.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private func toggleCompletion(for day: ScheduleDay) {
        if let existing = completionByDate[day.date] {
            modelContext.delete(existing)
        } else {
            modelContext.insert(DayCompletion(dateKey: day.date, completedHours: day.hours))
        }
        try? modelContext.save()
    }

    private func deltaLabel(_ delta: Double) -> String {
        if abs(delta) < 0.5 { return "On schedule" }
        if delta > 0 { return "+\(Formatting.hours(delta, precise: true)) ahead" }
        return "\(Formatting.hours(abs(delta), precise: true)) behind"
    }

    private func deltaTint(_ delta: Double) -> Color? {
        if abs(delta) < 0.5 { return nil }
        return delta > 0 ? Theme.success : Theme.warning
    }

    private var weekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }

    private var shortDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }
}
