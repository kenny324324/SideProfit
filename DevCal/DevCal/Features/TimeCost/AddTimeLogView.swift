//
//  AddTimeLogView.swift
//  DevCal
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct AddTimeLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"

    let project: Project
    var editing: TimeLog?

    @State private var hours: Double = 1
    @State private var hourlyRate: Double = 0
    @State private var hourlyCurrencyCode: String = "TWD"
    @State private var note: String = ""
    @State private var date: Date = Date()

    @AppStorage("timeLog.lastHourlyRate") private var lastHourlyRate: Double = 400
    /// Empty on first use → fall back to the display currency so non-TWD
    /// users don't see "TWD" by default.
    @AppStorage("timeLog.lastHourlyCurrency") private var lastHourlyCurrency: String = ""

    var body: some View {
        Form {
            Section {
                Stepper(value: $hours, in: 0.25...24, step: 0.25) {
                    HStack {
                        Text("Hours")
                        Spacer()
                        Text(hours.formatted(.number.precision(.fractionLength(0...2))))
                            .monospacedDigit()
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
            } header: {
                Text("Time").formSectionHeaderStyle()
            }

            Section {
                HStack(spacing: 12) {
                    Text("Hourly rate")
                    Spacer()
                    CurrencyMenuButton(selection: $hourlyCurrencyCode)
                    AmountFieldDivider()
                    TextField("0", value: $hourlyRate, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: 120)
                }
                HStack {
                    Text("Labor cost")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text((hours * hourlyRate).asCurrency(hourlyCurrencyCode))
                        .appFont(.callout, weight: .semibold)
                        .monospacedDigit()
                }
            } header: {
                Text("Rate").formSectionHeaderStyle()
            }

            Section {
                TextField("What did you work on?", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Note").formSectionHeaderStyle()
            }

            if editing != nil {
                Section {
                    Button(role: .destructive) {
                        deleteLog()
                    } label: {
                        Label("Delete time log", phImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .navigationTitle(editing == nil ? "Log time" : "Edit time log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .cancelActionStyle()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .confirmActionStyle()
                    .disabled(hours <= 0)
            }
        }
        .onAppear(perform: loadIfEditing)
    }

    private func loadIfEditing() {
        if let editing {
            hours = editing.hours
            hourlyRate = editing.hourlyRate
            hourlyCurrencyCode = editing.hourlyCurrencyCode
            note = editing.note
            date = editing.date
        } else {
            if hourlyRate == 0 { hourlyRate = lastHourlyRate }
            hourlyCurrencyCode = lastHourlyCurrency.isEmpty ? defaultCurrency : lastHourlyCurrency
        }
    }

    private func save() {
        if let editing {
            editing.hours = hours
            editing.hourlyRate = hourlyRate
            editing.hourlyCurrencyCode = hourlyCurrencyCode
            editing.note = note
            editing.date = date
            editing.updatedAt = Date()
        } else {
            let log = TimeLog(
                hours: hours,
                hourlyRate: hourlyRate,
                hourlyCurrencyCode: hourlyCurrencyCode,
                note: note,
                date: date,
                project: project
            )
            context.insert(log)
        }
        lastHourlyRate = hourlyRate
        lastHourlyCurrency = hourlyCurrencyCode
        try? context.save()
        dismiss()
    }

    private func deleteLog() {
        guard let editing else { return }
        context.delete(editing)
        try? context.save()
        dismiss()
    }
}
