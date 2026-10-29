//
//  ScheduleEditorView.swift
//  Tyri
//

import SwiftUI

struct ScheduleEditorView: View {
    @Binding var schedule: BlockingSchedule?
    @Environment(\.dismiss) private var dismiss

    @State private var hasLoaded = false
    @State private var enabled: Bool = false
    @State private var startDate: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    @State private var endDate: Date = Calendar.current.date(from: DateComponents(hour: 17, minute: 0)) ?? Date()
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]

    init(schedule: Binding<BlockingSchedule?>) {
        self._schedule = schedule
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Schedule", isOn: $enabled)
                    .tint(Color.accentColor)
            }

            if enabled {
                Section("Time") {
                    DatePicker("Start", selection: $startDate, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endDate, displayedComponents: .hourAndMinute)

                    if currentSchedule.crossesMidnight {
                        Label("This block continues past midnight.", systemImage: "moon.stars")
                            .font(.system(.caption, design: .default))
                            .foregroundColor(Color.secondary)
                    }
                }

                Section("Days") {

                    ForEach(orderedDays, id: \.self) { day in
                        Toggle(Calendar.current.standaloneWeekdaySymbols[day - 1], isOn: Binding(
                            get: { weekdays.contains(day) },
                            set: { selected in
                                if selected { weekdays.insert(day) } else { weekdays.remove(day) }
                            }
                        ))
                    }

                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    commit()
                    dismiss()
                }
                .disabled(enabled && weekdays.isEmpty)
            }
        }
        .onAppear { hydrate() }
    }

    private var orderedDays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    private func hydrate() {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let s = schedule {
            enabled = true
            startDate = Calendar.current.date(from: DateComponents(hour: s.startHour, minute: s.startMinute)) ?? startDate
            endDate = Calendar.current.date(from: DateComponents(hour: s.endHour, minute: s.endMinute)) ?? endDate
            weekdays = s.weekdays
        } else {
            enabled = false
        }
    }

    private var currentSchedule: BlockingSchedule {
        let startComps = Calendar.current.dateComponents([.hour, .minute], from: startDate)
        let endComps = Calendar.current.dateComponents([.hour, .minute], from: endDate)
        return BlockingSchedule(
            startHour: startComps.hour ?? 9,
            startMinute: startComps.minute ?? 0,
            endHour: endComps.hour ?? 17,
            endMinute: endComps.minute ?? 0,
            weekdays: weekdays
        )
    }

    private func commit() {
        if enabled && !weekdays.isEmpty {
            schedule = currentSchedule
        } else {
            schedule = nil
        }
    }
}
