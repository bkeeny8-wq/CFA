import SwiftUI
import SwiftData

struct PlanView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
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
                    "No study schedule",
                    systemImage: "calendar.badge.exclamationmark",
                    description: Text("The bundled schedule could not be loaded.")
                )
            }
        }
        .navigationTitle("Plan")
        .frame(maxWidth: horizontalSizeClass == .regular ? 960 : .infinity)
        .frame(maxWidth: .infinity)
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
                .onAppear {
                    DispatchQueue.main.async {
                        withAnimation {
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

    private func blockLine(_ block: ScheduleBlock) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let book = block.book {
                Circle()
                    .fill(Theme.bookColor(book))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
            }
            Text("\(block.start) · \(block.minutes) min · \(block.label)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
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
