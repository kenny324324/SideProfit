//
//  AddProjectView.swift
//  DevCal
//
//  Create or edit a Project. Pass nil to create; pass an existing Project to edit.
//
//  Projects no longer carry a currency — every Transaction / Goal stores its
//  own original currency, and the app uses the user's display currency for
//  cross-project aggregation (see Multi_Currency_Plan.md v1.2).
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct AddProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.projectRepository) private var projectRepository
    @Environment(AppReviewPrompter.self) private var appReviewPrompter
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "USD"

    var editing: Project?

    @State private var saveError: String? = nil
    @State private var showErrorAlert = false

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var kind: ProjectKind = .app
    @State private var iconImageData: Data? = nil
    @State private var iconPhName: String? = nil
    @State private var iconColorHex: String? = nil
    @State private var showIconPicker: Bool = false
    @State private var status: ProjectStatus = .building
    @State private var hasLaunchDate: Bool = false
    @State private var launchDate: Date = Date()

    // Goal: default to "enter a number" UX. Toggle on = skip goal (just track
    // break-even). When skipped, goalAmount/goalDeadline save as nil.
    @State private var breakEvenOnly: Bool = false
    @State private var goalAmount: Double = 0
    @State private var goalCurrencyCode: String = "USD"
    @State private var hasGoalDeadline: Bool = false
    @State private var goalDeadline: Date = Date()

    var body: some View {
        Form {
            Section {
                TextField("Project name", text: $name)
                TextField("One-line description (optional)", text: $description, axis: .vertical)
                    .lineLimit(1...3)
                Picker("專案類型", selection: $kind) {
                    ForEach(ProjectKind.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Button { showIconPicker = true } label: {
                    HStack {
                        Text("圖示")
                            .foregroundStyle(Theme.primaryText)
                        Spacer()
                        ProjectIconView(
                            imageData: iconImageData,
                            phName: iconPhName,
                            kindFallback: kind,
                            size: 22,
                            colorHex: iconColorHex
                        )
                        Image(systemName: "chevron.right")
                            .appFont(.footnote, weight: .semibold)
                            .foregroundStyle(Theme.primaryText.opacity(0.3))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text("Basics").formSectionHeaderStyle()
            }

            Section {
                Toggle("Track break-even only", isOn: $breakEvenOnly.animation())
                if !breakEvenOnly {
                    HStack(spacing: 12) {
                        CurrencyMenuButton(selection: $goalCurrencyCode)
                        AmountFieldDivider()
                        TextField("0", value: $goalAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                    }
                    Toggle("Set a deadline", isOn: $hasGoalDeadline.animation())
                    if hasGoalDeadline {
                        DatePicker(
                            "Target date",
                            selection: $goalDeadline,
                            in: Date()...,
                            displayedComponents: .date
                        )
                    }
                }
            } header: {
                Text("Goal").formSectionHeaderStyle()
            } footer: {
                Group {
                    if breakEvenOnly {
                        Text("Just track until expenses are recovered. You can add a goal later.")
                    } else {
                        Text("After break-even, progress switches to goal tracking.")
                    }
                }
                .appFont(.footnote)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("Status", selection: $status) {
                    ForEach(ProjectStatus.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Toggle("Has launch date", isOn: $hasLaunchDate.animation())
                if hasLaunchDate {
                    DatePicker("Launch date", selection: $launchDate, displayedComponents: .date)
                }
            } header: {
                Text("Status").formSectionHeaderStyle()
            }

        }
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .interactiveDismissDisabled()
        .navigationTitle(editing == nil ? "New project" : "Edit project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .cancelActionStyle()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await runSave() } }
                    .confirmActionStyle()
                    .disabled(!canSave)
            }
        }
        .systemAlert("Save failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear(perform: loadIfEditing)
        .sheet(isPresented: $showIconPicker) {
            ProjectIconPickerView(
                iconImageData: $iconImageData,
                iconPhName: $iconPhName,
                iconColorHex: $iconColorHex,
                kindFallback: kind
            )
        }
    }

    // MARK: - Actions

    private var canSave: Bool {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        if !breakEvenOnly && goalAmount <= 0 { return false }
        return true
    }

    private func loadIfEditing() {
        guard let editing else {
            // Creation defaults: goal currency tracks the display currency.
            goalCurrencyCode = defaultCurrency
            return
        }
        name = editing.name
        description = editing.projectDescription
        kind = editing.kind
        iconImageData = editing.iconImageData
        iconPhName = editing.iconPhName
        iconColorHex = editing.iconColorHex
        status = editing.status
        if let d = editing.launchDate {
            hasLaunchDate = true
            launchDate = d
        }

        if let existingGoal = editing.goalAmount, existingGoal > 0 {
            breakEvenOnly = false
            goalAmount = existingGoal
            goalCurrencyCode = editing.goalCurrencyCode ?? defaultCurrency
            if let dl = editing.goalDeadline {
                hasGoalDeadline = true
                goalDeadline = dl
            }
        } else {
            breakEvenOnly = true
            goalCurrencyCode = defaultCurrency
        }
    }

    private func runSave() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, let repo = projectRepository else { return }

        let resolvedGoalAmount: Double? = breakEvenOnly ? nil : goalAmount
        let resolvedGoalCurrency: String? = breakEvenOnly ? nil : goalCurrencyCode
        let resolvedGoalDeadline: Date? = breakEvenOnly ? nil : (hasGoalDeadline ? goalDeadline : nil)

        let isCreating = editing == nil
        do {
            if let editing {
                try await repo.updateProject(editing) { project in
                    project.name = trimmedName
                    project.projectDescription = description
                    project.kind = kind
                    project.iconImageData = iconImageData
                    project.iconPhName = iconPhName
                    project.iconColorHex = iconColorHex
                    project.status = status
                    project.launchDate = hasLaunchDate ? launchDate : nil
                    project.goalAmount = resolvedGoalAmount
                    project.goalCurrencyCode = resolvedGoalCurrency
                    project.goalDeadline = resolvedGoalDeadline
                }
            } else {
                _ = try await repo.createProject(
                    name: trimmedName,
                    description: description,
                    status: status,
                    kind: kind,
                    iconImageData: iconImageData,
                    iconPhName: iconPhName,
                    iconColorHex: iconColorHex,
                    launchDate: hasLaunchDate ? launchDate : nil,
                    goalAmount: resolvedGoalAmount,
                    goalCurrencyCode: resolvedGoalCurrency,
                    goalDeadline: resolvedGoalDeadline
                )
            }
            if isCreating {
                appReviewPrompter.record(.projectCreated)
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
            showErrorAlert = true
        }
    }

}
