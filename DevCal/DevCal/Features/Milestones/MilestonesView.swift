//
//  MilestonesView.swift
//  DevCal
//
//  Shows achieved milestones for a project and the next ones still locked.
//  Auto-detected milestones are computed at view time from current data, so the
//  list stays accurate without needing a background detector.
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct MilestonesView: View {
    @Environment(\.milestoneRepository) private var milestoneRepository
    @Environment(ExchangeRateService.self) private var fx
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"
    let project: Project

    @State private var showAddManual = false
    @State private var deleteError: String? = nil
    @State private var showDeleteErrorAlert = false

    var body: some View {
        List {
            if !achieved.isEmpty {
                Section("Achieved") {
                    ForEach(achieved) { item in
                        milestoneRow(item, locked: false)
                    }
                }
                .listRowBackground(Theme.listRowBackground)
            }
            if !upcoming.isEmpty {
                Section("Coming up") {
                    ForEach(upcoming) { item in
                        milestoneRow(item, locked: true)
                    }
                }
                .listRowBackground(Theme.listRowBackground)
            }
            if !manualMilestones.isEmpty {
                Section("Your milestones") {
                    ForEach(manualMilestones) { milestone in
                        manualMilestoneRow(milestone)
                    }
                    .onDelete(perform: deleteManual)
                }
                .listRowBackground(Theme.listRowBackground)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .navigationTitle("Milestones")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddManual = true
                } label: {
                    Image(ph: "plus")
                        .frame(width: 18, height: 18)
                }
            }
        }
        .sheet(isPresented: $showAddManual) {
            NavigationStack {
                AddManualMilestoneView(project: project)
            }
        }
        .systemAlert("Delete failed", isPresented: $showDeleteErrorAlert) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .overlay {
            if achieved.isEmpty && upcoming.isEmpty && manualMilestones.isEmpty {
                ContentUnavailableView {
                    Label("No milestones yet", phImage: "flag")
                } description: {
                    Text("Log entries to unlock your first milestone.")
                }
            }
        }
    }

    // MARK: - Milestone computation

    private struct Item: Identifiable {
        let id = UUID()
        let type: MilestoneType
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let achieved: Bool
    }

    private var achieved: [Item] { auto.filter(\.achieved) }
    private var upcoming: [Item] { auto.filter { !$0.achieved } }

    private var auto: [Item] {
        let txns = project.transactions ?? []
        let hasAnyTxn = !txns.isEmpty
        let hasIncome = txns.contains { $0.type == .income }
        let hasExpense = txns.contains { $0.type == .expense }
        let income = project.totalIncome(in: defaultCurrency, fx: fx)

        let cal = Calendar.current
        let monthlyIncome = Dictionary(grouping: txns.filter { $0.type == .income }) { txn in
            cal.date(from: cal.dateComponents([.year, .month], from: txn.date)) ?? txn.date
        }
        let monthlyExpense = Dictionary(grouping: txns.filter { $0.type == .expense }) { txn in
            cal.date(from: cal.dateComponents([.year, .month], from: txn.date)) ?? txn.date
        }
        let profitableMonth = monthlyIncome.contains { (month, list) in
            let inc = list.reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
            let exp = (monthlyExpense[month] ?? []).reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
            return inc > exp
        }

        let p = project.progress(in: defaultCurrency, fx: fx)
        return [
            Item(type: .firstTransaction, title: MilestoneType.firstTransaction.defaultTitle, subtitle: "Tap + to log income or expense.", achieved: hasAnyTxn),
            Item(type: .firstIncome, title: MilestoneType.firstIncome.defaultTitle, subtitle: "Your first dollar earned.", achieved: hasIncome),
            Item(type: .firstExpense, title: MilestoneType.firstExpense.defaultTitle, subtitle: "Costs make ROI honest.", achieved: hasExpense),
            Item(type: .firstProfitableMonth, title: MilestoneType.firstProfitableMonth.defaultTitle, subtitle: "Revenue > expenses in one month.", achieved: profitableMonth),
            Item(type: .breakEven25, title: MilestoneType.breakEven25.defaultTitle, subtitle: "First quarter to recover costs.", achieved: p >= 0.25),
            Item(type: .breakEven50, title: MilestoneType.breakEven50.defaultTitle, subtitle: "Halfway home.", achieved: p >= 0.50),
            Item(type: .breakEven75, title: MilestoneType.breakEven75.defaultTitle, subtitle: "Final stretch.", achieved: p >= 0.75),
            Item(type: .breakEvenReached, title: MilestoneType.breakEvenReached.defaultTitle, subtitle: "Project recovered its costs.", achieved: project.breakevenReachedAt != nil),
            Item(type: .firstThousandEarned, title: MilestoneType.firstThousandEarned.defaultTitle, subtitle: "$1,000 in total revenue.", achieved: income >= 1_000),
            Item(type: .firstTenThousandEarned, title: MilestoneType.firstTenThousandEarned.defaultTitle, subtitle: "$10,000 in total revenue.", achieved: income >= 10_000)
        ]
    }

    private var manualMilestones: [Milestone] {
        (project.milestones ?? []).filter { $0.type == .manual }.sorted { $0.date > $1.date }
    }

    // MARK: - Rows

    private func milestoneRow(_ item: Item, locked: Bool) -> some View {
        HStack(spacing: 12) {
            item.type.icon
                .frame(width: 20, height: 20)
                .foregroundStyle(locked ? Color.secondary : item.type.tint)
                .frame(width: 40, height: 40)
                .background((locked ? Color.secondary : item.type.tint).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(locked ? .secondary : .primary)
                Text(item.subtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !locked {
                Image(ph: "check-circle")
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.income)
            } else {
                Image(ph: "lock")
                    .frame(width: 14, height: 14)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func manualMilestoneRow(_ milestone: Milestone) -> some View {
        HStack(spacing: 12) {
            Image(ph: "flag")
                .frame(width: 20, height: 20)
                .foregroundStyle(.purple)
                .frame(width: 40, height: 40)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title)
                    .appFont(.subheadline, weight: .semibold)
                if !milestone.note.isEmpty {
                    Text(milestone.note).appFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(milestone.date, style: .date).appFont(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func deleteManual(at offsets: IndexSet) {
        guard let repo = milestoneRepository else { return }
        let snapshot = manualMilestones
        let targets = offsets.map { snapshot[$0] }
        Task { @MainActor in
            do {
                for milestone in targets {
                    try await repo.deleteMilestone(milestone)
                }
            } catch {
                deleteError = error.localizedDescription
                showDeleteErrorAlert = true
            }
        }
    }
}

// MARK: - Add manual milestone

struct AddManualMilestoneView: View {
    @Environment(\.milestoneRepository) private var milestoneRepository
    @Environment(\.dismiss) private var dismiss
    let project: Project

    @State private var title: String = ""
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var saveError: String? = nil
    @State private var showErrorAlert = false

    var body: some View {
        Form {
            Section("Milestone") {
                TextField("Title", text: $title)
                TextField("What happened? (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...4)
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .navigationTitle("Add milestone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await runSave() }
                }
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .systemAlert("Save failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    @MainActor
    private func runSave() async {
        guard let repo = milestoneRepository else { return }
        do {
            _ = try await repo.createManualMilestone(
                project: project,
                title: title,
                note: note,
                date: date
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
            showErrorAlert = true
        }
    }
}
