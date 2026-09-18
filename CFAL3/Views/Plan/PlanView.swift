import SwiftUI
import SwiftData

struct PlanView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(TabRouter.self) private var router
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var completions: [DayCompletion]

    @State private var visibleMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedKey: String = StudySchedule.dateKey(for: .now)

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
        .background(Theme.paper)
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func planContent(_ schedule: StudySchedule) -> some View {
        let selected = schedule.day(forKey: selectedKey) ?? schedule.day(for: .now)
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Plan")
                        .font(Theme.serif(.largeTitle, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("\(schedule.days.filter { !$0.isRestDay }.count) study days · \(schedule.days.filter(\.isRestDay).count) rest · schedule adds time, it never slips.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dust)
                }
                monthGrid(schedule)
                legend
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let selected {
                dayInspector(selected, schedule: schedule)
                    .frame(width: horizontalSizeClass == .regular ? 280 : nil)
            }
        }
        .padding(24)
    }

    private func monthGrid(_ schedule: StudySchedule) -> some View {
        let cal = Calendar.current
        let month = cal.dateInterval(of: .month, for: visibleMonth)?.start ?? visibleMonth
        let days = daysInMonth(month)
        let weekdaySymbols = cal.veryShortWeekdaySymbols
        return VStack(spacing: 8) {
            HStack {
                Button {
                    visibleMonth = cal.date(byAdding: .month, value: -1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(monthTitle(month))
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Button {
                    visibleMonth = cal.date(byAdding: .month, value: 1, to: month) ?? month
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .foregroundStyle(Theme.pine)

            HStack {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.dust)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        let key = StudySchedule.dateKey(for: date)
                        dayCell(date, key: key, day: schedule.day(forKey: key))
                    } else {
                        Color.clear.frame(height: 54)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Theme.cardFill)
                .shadow(color: Color.black.opacity(0.05), radius: 12, y: 4)
        )
    }

    private func dayCell(_ date: Date, key: String, day: ScheduleDay?) -> some View {
        let cal = Calendar.current
        let isToday = key == todayKey
        let isSelected = key == selectedKey
        let isDone = completionByDate[key] != nil
        let isRest = day?.isRestDay == true
        let owed = isOwed(day, key: key)
        return Button {
            selectedKey = key
        } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: date))")
                    .font(.subheadline.weight(isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected && isToday ? .white : Theme.ink)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isSelected && isToday ? .white : Theme.pine)
                } else if isRest {
                    Image(systemName: "moon.zzz")
                        .font(.caption2)
                        .foregroundStyle(Theme.dust)
                } else if owed {
                    Capsule()
                        .fill(Theme.copper)
                        .frame(width: 16, height: 2)
                } else if let label = shortBlockLabel(day) {
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(Theme.dust)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                Circle()
                    .fill(isSelected && isToday ? Theme.pine : (isSelected ? Theme.sage : Color.clear))
                    .padding(6)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibility(date, day: day, isDone: isDone, isRest: isRest))
    }

    private func isOwed(_ day: ScheduleDay?, key: String) -> Bool {
        guard let day, !day.isRestDay, key < todayKey else { return false }
        return completionByDate[key] == nil
    }

    private func shortBlockLabel(_ day: ScheduleDay?) -> String? {
        guard let label = day?.blocks.first?.label else { return nil }
        if label.count <= 8 { return label }
        return String(label.prefix(6))
    }

    private func dayAccessibility(_ date: Date, day: ScheduleDay?, isDone: Bool, isRest: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        var parts = [formatter.string(from: date)]
        if isRest { parts.append("rest") }
        if isDone { parts.append("completed") }
        if let hours = day?.hours, hours > 0 { parts.append(Formatting.hours(hours)) }
        return parts.joined(separator: ", ")
    }

    private var legend: some View {
        HStack(spacing: 18) {
            Label("Completed", systemImage: "checkmark")
            Label("Rest", systemImage: "moon.zzz")
            Label("Hours owed", systemImage: "minus")
        }
        .font(.caption)
        .foregroundStyle(Theme.dust)
    }

    @ViewBuilder
    private func dayInspector(_ day: ScheduleDay, schedule: StudySchedule) -> some View {
        let isDone = completionByDate[day.date] != nil
        let isToday = day.date == todayKey
        VStack(alignment: .leading, spacing: 14) {
            Text(inspectorTitle(day))
                .font(Theme.serif(.title2, weight: .semibold))
                .foregroundStyle(Theme.ink)
            Text("\(Formatting.hours(day.hours)) planned")
                .font(.subheadline)
                .foregroundStyle(Theme.dust)

            ForEach(day.blocks) { block in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.start)
                            .font(.caption)
                            .foregroundStyle(Theme.dust)
                        Text(block.label)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Text("\(block.minutes)m")
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.cardFill)
                )
            }

            Button {
                router.selected = .notes
            } label: {
                Label("Open today's notes", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryCTA())

            if !day.isRestDay {
                Button {
                    toggleCompletion(for: day)
                } label: {
                    Label(isDone ? "Mark incomplete" : "Mark day complete", systemImage: isDone ? "checkmark.square.fill" : "square")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isDone ? "Mark incomplete" : "Mark done")
            }

            let delta = ScheduleProgress.delta(schedule: schedule, completions: completions)
            if delta < -2 {
                Text("\(Formatting.hours(abs(delta), precise: true)) to make up")
                    .font(.caption)
                    .foregroundStyle(Theme.copper)
            }

            Label("\(Formatting.daysUntilExam()) days to exam", systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(Theme.dust)

            if isToday, let readingID = day.blocks.compactMap(\.readingID).first,
               let bundle = content.drillBundle(forReading: readingID) {
                Button("Start that block's drills") {
                    router.startQuestions(
                        sessionCoordinator,
                        ids: bundle.drills.flatMap { $0.questions.map(\.id) }.shuffled(),
                        mode: .losDrill,
                        description: "Plan drills"
                    )
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.pine)
            }
        }
    }

    private func inspectorTitle(_ day: ScheduleDay) -> String {
        guard let date = day.parsedDate else { return day.date }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return formatter.string(from: date)
    }

    private func toggleCompletion(for day: ScheduleDay) {
        if let existing = completionByDate[day.date] {
            modelContext.delete(existing)
        } else {
            modelContext.insert(DayCompletion(dateKey: day.date, completedHours: day.hours))
        }
        try? modelContext.save()
    }

    private func daysInMonth(_ month: Date) -> [Date?] {
        let cal = Calendar.current
        guard let range = cal.range(of: .day, in: .month, for: month),
              let start = cal.date(from: cal.dateComponents([.year, .month], from: month)) else {
            return []
        }
        let weekday = cal.component(.weekday, from: start)
        let leading = weekday - cal.firstWeekday
        let pad = (leading + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: pad)
        for day in range {
            days.append(cal.date(byAdding: .day, value: day - 1, to: start))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private func monthTitle(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: month)
    }
}
