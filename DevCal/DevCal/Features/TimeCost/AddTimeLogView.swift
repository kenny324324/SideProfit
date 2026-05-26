//
//  AddTimeLogView.swift
//  DevCal
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct AddTimeLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.timeLogRepository) private var timeLogRepository
    @Environment(AppReviewPrompter.self) private var appReviewPrompter
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"

    let project: Project
    var editing: TimeLog?

    @State private var hours: Double = 1
    @State private var hourlyRate: Double = 0
    @State private var hourlyCurrencyCode: String = "TWD"
    @State private var note: String = ""
    @State private var date: Date = Date()

    @State private var saveError: String? = nil
    @State private var showErrorAlert = false

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
                        Task { await runDelete() }
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
                Button("Save") { Task { await runSave() } }
                    .confirmActionStyle()
                    .disabled(hours <= 0)
            }
        }
        .systemAlert("Save failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
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

    private func runSave() async {
        guard let repo = timeLogRepository else { return }
        let isCreating = editing == nil
        do {
            if let editing {
                try await repo.updateTimeLog(
                    editing,
                    hours: hours,
                    hourlyRate: hourlyRate,
                    hourlyCurrencyCode: hourlyCurrencyCode,
                    note: note,
                    date: date
                )
            } else {
                _ = try await repo.createTimeLog(
                    project: project,
                    hours: hours,
                    hourlyRate: hourlyRate,
                    hourlyCurrencyCode: hourlyCurrencyCode,
                    note: note,
                    date: date
                )
            }
            lastHourlyRate = hourlyRate
            lastHourlyCurrency = hourlyCurrencyCode
            if isCreating {
                appReviewPrompter.record(.timeLogCreated)
            }
            dismiss()
        } catch {
            present(error)
        }
    }

    private func runDelete() async {
        guard let repo = timeLogRepository, let editing else { return }
        do {
            try await repo.deleteTimeLog(editing)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        saveError = error.localizedDescription
        showErrorAlert = true
    }
}
