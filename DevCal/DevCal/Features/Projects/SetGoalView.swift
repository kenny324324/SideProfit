//
//  SetGoalView.swift
//  DevCal
//
//  Sheet for setting the Stage-2 lifetime revenue goal on a project that has
//  already reached break-even. Optional deadline enables ahead/behind projection.
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct SetGoalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.projectRepository) private var projectRepository
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"
    @Bindable var project: Project

    @State private var goalAmount: Double = 0
    @State private var goalCurrencyCode: String = "TWD"
    @State private var hasDeadline: Bool = false
    @State private var deadline: Date = Date()

    @State private var saveError: String? = nil
    @State private var showErrorAlert = false

    private var isEditing: Bool { project.goalAmount != nil }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    CurrencyMenuButton(selection: $goalCurrencyCode)
                    AmountFieldDivider()
                    TextField("0", value: $goalAmount, format: .number)
                        .keyboardType(.decimalPad)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.leading)
                }
            } header: {
                Text("Goal amount").formSectionHeaderStyle()
            } footer: {
                Text("設定一個專案的營收目標。回到進度後會從回本切換成目標追蹤。")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Set a deadline", isOn: $hasDeadline.animation())
                if hasDeadline {
                    DatePicker(
                        "Target date",
                        selection: $deadline,
                        in: Date()...,
                        displayedComponents: .date
                    )
                }
            } header: {
                Text("Deadline (optional)").formSectionHeaderStyle()
            } footer: {
                if hasDeadline {
                    Text("依近期營收推估完成日,並顯示領先或落後幅度。")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if isEditing {
                Section {
                    Button(role: .destructive) {
                        Task { await runClearGoal() }
                    } label: {
                        Label("Clear goal", phImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .navigationTitle(isEditing ? "Edit goal" : "Set goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .cancelActionStyle()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await runSave() } }
                    .confirmActionStyle()
                    .disabled(goalAmount <= 0)
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
        if let existing = project.goalAmount, existing > 0 {
            goalAmount = existing
            goalCurrencyCode = project.goalCurrencyCode ?? defaultCurrency
        } else {
            goalCurrencyCode = defaultCurrency
        }
        if let dl = project.goalDeadline {
            hasDeadline = true
            deadline = dl
        }
    }

    private func runSave() async {
        guard let repo = projectRepository else { return }
        do {
            try await repo.setGoal(
                on: project,
                amount: goalAmount,
                currencyCode: goalCurrencyCode,
                deadline: hasDeadline ? deadline : nil
            )
            dismiss()
        } catch {
            present(error)
        }
    }

    private func runClearGoal() async {
        guard let repo = projectRepository else { return }
        do {
            try await repo.setGoal(on: project, amount: nil, currencyCode: nil, deadline: nil)
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
