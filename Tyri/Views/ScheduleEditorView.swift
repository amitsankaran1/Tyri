import SwiftUI

struct ScheduleEditorView: View {
    @Binding var schedule: BlockingSchedule?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var hasLoaded = false
    @State private var startDate = Calendar.current.date(from: DateComponents(hour: 9)) ?? Date()
    @State private var endDate = Calendar.current.date(from: DateComponents(hour: 17)) ?? Date()
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    var body: some View {
        Form {
            Section {
                DatePicker("Block from", selection: $startDate, displayedComponents: .hourAndMinute)
                DatePicker("Until", selection: $endDate, displayedComponents: .hourAndMinute)
            } header: {
                Text("Time")
            } footer: {
                if currentSchedule.crossesMidnight {
                    Label("Ends the next day. Choose the days this block starts.", systemImage: "moon")
                }
            }

            Section {
                ViewThatFits(in: .horizontal) {
                    HStack { presets }
                    VStack(alignment: .leading) { presets }
                }
                .buttonStyle(.bordered)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                         count: dynamicTypeSize.isAccessibilitySize ? 2 : 7), spacing: 8) {
                    ForEach(orderedDays, id: \.self) { day in
                        Button {
                            if weekdays.contains(day) { weekdays.remove(day) }
                            else { weekdays.insert(day) }
                        } label: {
                            Text(dynamicTypeSize.isAccessibilitySize
                                 ? Calendar.current.shortStandaloneWeekdaySymbols[day - 1]
                                 : Calendar.current.veryShortStandaloneWeekdaySymbols[day - 1])
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(weekdays.contains(day) ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(weekdays.contains(day) ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Calendar.current.standaloneWeekdaySymbols[day - 1])
                        .accessibilityValue(weekdays.contains(day) ? "Selected" : "Not selected")
                        .accessibilityAddTraits(weekdays.contains(day) ? .isSelected : [])
                        .accessibilityIdentifier("schedule-day-\(day)")
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Repeat")
            } footer: {
                Text(weekdays.isEmpty ? "Choose at least one day." : "Tap a day to include or exclude it.")
            }

            if !weekdays.isEmpty {
                Section {
                    Label {
                        Text("\(currentSchedule.weekdaySummary), \(startDate.formatted(date: .omitted, time: .shortened))–\(endDate.formatted(date: .omitted, time: .shortened))\(currentSchedule.crossesMidnight ? " the next day" : "")")
                    } icon: { Image(systemName: "clock") }
                    .accessibilityIdentifier("schedule-summary")
                } header: { Text("Your schedule") }
            }
            if schedule != nil {
                Section {
                    Button("Remove schedule", role: .destructive) {
                        schedule = nil
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    schedule = currentSchedule
                    dismiss()
                }
                .disabled(weekdays.isEmpty)
            }
        }
        .onAppear { hydrate() }
    }

    @ViewBuilder private var presets: some View {
        preset("Every day", days: Set(1...7))
        preset("Weekdays", days: [2, 3, 4, 5, 6])
        preset("Weekends", days: [1, 7])
    }

    private func preset(_ title: String, days: Set<Int>) -> some View {
        Button(title) { weekdays = days }
            .tint(weekdays == days ? .accentColor : .secondary)
            .accessibilityAddTraits(weekdays == days ? .isSelected : [])
    }

    private var orderedDays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func hydrate() {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let s = schedule {
            startDate = Calendar.current.date(from: DateComponents(hour: s.startHour, minute: s.startMinute)) ?? startDate
            endDate = Calendar.current.date(from: DateComponents(hour: s.endHour, minute: s.endMinute)) ?? endDate
            weekdays = s.weekdays
        }
    }

    private var currentSchedule: BlockingSchedule {
        let start = Calendar.current.dateComponents([.hour, .minute], from: startDate)
        let end = Calendar.current.dateComponents([.hour, .minute], from: endDate)
        return BlockingSchedule(startHour: start.hour ?? 9, startMinute: start.minute ?? 0,
                                endHour: end.hour ?? 17, endMinute: end.minute ?? 0, weekdays: weekdays)
    }
}
