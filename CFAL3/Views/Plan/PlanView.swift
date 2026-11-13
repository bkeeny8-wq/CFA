import SwiftUI
import SwiftData

struct PlanView: View {
    @Environment(ContentLoader.self) private var content
    @Environment(TabRouter.self) private var router
    @Environment(StudySessionCoordinator.self) private var sessionCoordinator
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var completions: [DayCompletion]
    @Query private var blockResults: [ScheduleBlockResult]

    @State private var visibleMonth: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedKey: String = StudySchedule.dateKey(for: .now)
    /// The dateKey travels with the block: a bare ScheduleBlock cannot say
    /// which day it belongs to, and its own `id` repeats across days.
    @State private var recording: RecordingTarget?
    @State private var showBaseline = false

    private struct RecordingTarget: Identifiable {
        let dateKey: String
        let block: ScheduleBlock
        var id: String { block.resultKey(on: dateKey) }
    }

    private var schedule: StudySchedule? { content.schedule }

    private var completionByDate: [String: DayCompletion] {
        Dictionary(uniqueKeysWithValues: completions.map { ($0.dateKey, $0) })
    }

    /// `uniquingKeysWith:` rather than `uniqueKeysWithValues:` as the line
    /// above uses. That one is safe only because DayCompletion.dateKey carries
    /// a unique constraint; a duplicate here would trap at runtime.
    private var resultByKey: [String: ScheduleBlockResult] {
        Dictionary(blockResults.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
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

    /// Title, month grid and legend — the left column at regular width, the
    /// top of the stack on a phone.
    private func calendarColumn(_ schedule: StudySchedule) -> some View {
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
    }

    @ViewBuilder
    private func planContent(_ schedule: StudySchedule) -> some View {
        let selected = schedule.day(forKey: selectedKey) ?? schedule.day(for: .now)
        Group {
            if horizontalSizeClass == .regular {
                HStack(alignment: .top, spacing: 24) {
                    calendarColumn(schedule)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let selected {
                        // Scrolls because it has to: six November days carry
                        // six blocks where the old plan's maximum was four,
                        // and each row is now taller. Unscrolled, the make-up
                        // line and the days-to-exam label fall off the bottom
                        // of a 280pt column.
                        ScrollView {
                            dayInspector(selected, schedule: schedule)
                        }
                        .frame(width: 280)
                    }
                }
            } else {
                // A phone cannot hold the two columns side by side. Split in
                // half, a 393pt screen gives the month grid under 190pt, which
                // wrapped the date numbers onto two lines - "1 3" for the 13th
                // - and broke the legend into "Co mpl ete d". The inspector
                // goes under the calendar instead, and the whole thing scrolls
                // as one rather than two columns scrolling separately.
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        calendarColumn(schedule)
                        if let selected {
                            dayInspector(selected, schedule: schedule)
                        }
                    }
                }
            }
        }
        .padding(horizontalSizeClass == .regular ? 24 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper)
        .sheet(item: $recording) { target in
            BlockResultSheet(
                dateKey: target.dateKey,
                block: target.block,
                existing: resultByKey[target.block.resultKey(on: target.dateKey)],
                onSave: saveResult,
                onDelete: deleteResult
            )
            .environment(content)
        }
        .sheet(isPresented: $showBaseline) {
            BaselineReadoutView(
                rows: BaselineReadout.rows(
                    schedule: schedule, results: blockResults, content: content
                )
            )
        }
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
                        // White on the selected-today circle, like the day
                        // number above it. Theme.dust on Theme.pine measures
                        // 1.34:1 against WCAG AA's 4.5 floor — the label was
                        // there but unreadable on exactly the day you look at
                        // most.
                        .foregroundStyle(isSelected && isToday ? .white : Theme.dust)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                // A rounded rect rather than a circle, because a circle
                // inscribed in a cell this shape only reaches the day number.
                // The reading label sits below it, outside the fill, and it is
                // drawn white to read against the fill — so on the selected
                // day the label was white on cream and all but invisible. The
                // shape now covers what it tints.
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected && isToday ? Theme.pine : (isSelected ? Theme.sage : Color.clear))
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibility(date, day: day, isDone: isDone, isRest: isRest))
    }

    private func isOwed(_ day: ScheduleDay?, key: String) -> Bool {
        guard let day, !day.isRestDay, key < todayKey else { return false }
        return completionByDate[key] == nil
    }

    /// The first block's title, left whole.
    ///
    /// This used to cut to `prefix(8)` with no ellipsis, which is not a
    /// shortening — it is a mid-word amputation. "Active Equity Port
    /// Construction" rendered as "Active E", and the neighbouring cells'
    /// "Overview" was really "Overview of Asset Allocation" cut at the same
    /// eight characters; it only looked deliberate because the cut happened to
    /// land on a word boundary. The Text already has `lineLimit(1)`, so
    /// SwiftUI truncates to the cell's real width and adds the ellipsis.
    private func shortBlockLabel(_ day: ScheduleDay?) -> String? {
        guard let day, let block = day.blocks.first else { return nil }
        let title = StudyDisplay.scheduleBlockTitle(block, content: content)
        // Six November days carry six blocks each, where the old plan's
        // maximum was four. Showing only the first silently hid five of them.
        return day.blocks.count > 1 ? "\(title) +\(day.blocks.count - 1)" : title
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
        VStack(alignment: .leading, spacing: 14) {
            Text(inspectorTitle(day))
                .font(Theme.serif(.title2, weight: .semibold))
                .foregroundStyle(Theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Formatting.hours(day.hours)) planned")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dust)
                if let summary = recordedSummary(day) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(Theme.dust)
                        .accessibilityIdentifier("plan.day.recorded.\(day.date)")
                }
            }

            ForEach(day.blocks) { block in
                blockRow(block, dateKey: day.date)
            }

            Button {
                showBaseline = true
            } label: {
                Label("November baseline", systemImage: "chart.bar.doc.horizontal")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.pine)
            .accessibilityIdentifier("plan.baseline.open")

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

            // The day-level "start that block's drills" button lived here and
            // has moved onto each block row, where it can tell which block you
            // meant and stay quiet on the Meldrum ones.
        }
    }

    /// How much of a day has been written down.
    ///
    /// Deliberately NOT wired into DayCompletion. Everything downstream — the
    /// grid checkmark, the owed dash, ScheduleProgress.delta — credits
    /// `day.hours` from that one row, and letting block results credit hours
    /// as well would count the same morning twice. This line just makes the
    /// relationship visible so a day with every block scored and no check mark
    /// looks like an oversight rather than a contradiction.
    private func recordedSummary(_ day: ScheduleDay) -> String? {
        let recordable = day.blocks.filter { $0.kind == .questions || $0.kind == .mock }
        guard !recordable.isEmpty else { return nil }
        let done = recordable.filter { resultByKey[$0.resultKey(on: day.date)]?.hasScore == true }
        return "\(done.count) of \(recordable.count) sittings recorded"
    }

    /// One block, tappable to record what it scored.
    ///
    /// Identifiers carry the dateKey because `block.id` is `start-label`,
    /// which repeats on 42 of the plan's blocks and on one across six days.
    private func blockRow(_ block: ScheduleBlock, dateKey: String) -> some View {
        let result = resultByKey[block.resultKey(on: dateKey)]
        let slot = "\(dateKey).\(block.start)"
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                recording = RecordingTarget(dateKey: dateKey, block: block)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(block.start)
                            .font(.caption)
                            .foregroundStyle(Theme.dust)
                        BlockSourceBadge(source: block.questionSource)
                            .accessibilityIdentifier("plan.block.source.\(slot)")
                        Spacer()
                        Text("\(block.minutes)m")
                            .font(.caption)
                            .foregroundStyle(Theme.dust)
                    }
                    Text(StudyDisplay.scheduleBlockTitle(block, content: content))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Image(systemName: result?.hasScore == true
                              ? "checkmark.circle.fill" : "square.and.pencil")
                            .font(.caption2)
                            .foregroundStyle(result?.hasScore == true ? Theme.pine : Theme.dust)
                        Text(result.flatMap { $0.hasScore ? scoreSummary($0) : nil }
                             ?? "Tap to record")
                            .font(.caption2)
                            .foregroundStyle(result?.hasScore == true ? Theme.ink : Theme.dust)
                    }
                    .accessibilityIdentifier("plan.block.score.\(slot)")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.cardFill)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.block.\(slot)")
            .accessibilityValue(result?.hasScore == true ? "Recorded" : "Not recorded")

            // Offered only where the questions actually live here. Most
            // blocks in the plan now point at Meldrum's app or CFA
            // Institute's bank, and the old day-level button sent you to
            // in-app drills for a reading the plan says to answer elsewhere.
            if let readingID = block.readingID,
               block.questionSource?.isAnsweredInThisApp == true,
               let bundle = content.drillBundle(forReading: readingID) {
                Button("Start these drills") {
                    router.startQuestions(
                        sessionCoordinator,
                        ids: bundle.drills.flatMap { $0.questions.map(\.id) }.shuffled(),
                        mode: .losDrill,
                        description: StudyDisplay.scheduleBlockTitle(block, content: content)
                    )
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.pine)
                .padding(.leading, 12)
                .accessibilityIdentifier("plan.block.drills.\(slot)")
            }
        }
    }

    private func scoreSummary(_ result: ScheduleBlockResult) -> String {
        var parts: [String] = []
        if let rate = result.correctRate {
            parts.append("\(result.questionsCorrect)/\(result.questionsAttempted)"
                         + " · \(Int((rate * 100).rounded()))%")
        }
        if let essay = result.essayRate {
            parts.append("essays \(Int((essay * 100).rounded()))%")
        }
        if result.ranOutOfTime { parts.append("ran out of time") }
        return parts.isEmpty ? "Recorded" : parts.joined(separator: " · ")
    }

    private func saveResult(_ row: ScheduleBlockResult) {
        // Inserting a row that is already registered is a no-op, so this one
        // call covers both create and edit.
        modelContext.insert(row)
        persist()
    }

    private func deleteResult(_ row: ScheduleBlockResult) {
        modelContext.delete(row)
        persist()
    }

    /// Not `try?`. A unique-constraint violation would otherwise look exactly
    /// like a row that was never created, and the view would keep showing the
    /// unsaved state until relaunch.
    private func persist() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
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
