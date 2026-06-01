//
//  TransactionsListView.swift
//  DevCal
//
//  Full list of a project's entries, grouped by month. Editorial flat layout —
//  hairline-separated month sections, same pattern as ProjectDashboardView /
//  TimeCostView (no List, no inset-grouped chrome).
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct TransactionsListView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "USD"
    @Environment(ExchangeRateService.self) private var fx
    let project: Project

    @State private var searchText = ""
    @State private var editingTransaction: Transaction?
    @State private var pendingNewType: TransactionType?
    @State private var showTypePicker = false
    @State private var pickedType: TransactionType?
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable, Identifiable {
        case all, income, expense
        var id: String { rawValue }
        var displayName: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .income: "Income"
            case .expense: "Expense"
            }
        }
    }

    var body: some View {
        Group {
            if grouped.isEmpty {
                ContentUnavailableView {
                    Label("No entries", phImage: "tray")
                } description: {
                    Text("Tap + to add an income or expense.")
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(grouped.indices, id: \.self) { idx in
                            if idx > 0 { sectionDivider }
                            monthSection(grouped[idx])
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Theme.appBackground)
        .navigationTitle("收支紀錄")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $searchText, prompt: Text("Search"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(Filter.allCases) { f in
                        Button {
                            filter = f
                        } label: {
                            Text(f.displayName)
                        }
                    }
                } label: {
                    Text(filter.displayName)
                        .foregroundStyle(Theme.primaryText)
                }
            }
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                addEntryButton
            }
        }
        .sheet(item: $pendingNewType) { type in
            NavigationStack {
                AddTransactionView(project: project, initialType: type)
            }
        }
        .sheet(isPresented: $showTypePicker, onDismiss: {
            if let type = pickedType {
                pickedType = nil
                pendingNewType = type
            }
        }) {
            TransactionTypePickerSheet { type in
                pickedType = type
            }
        }
        .sheet(item: $editingTransaction) { txn in
            NavigationStack {
                AddTransactionView(project: project, editing: txn)
            }
        }
    }

    // MARK: - Toolbar add button (matches ProjectDashboardView)

    @ViewBuilder
    private var addEntryButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                showTypePicker = true
            } label: {
                Image(ph: "plus")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Theme.onTint)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
        } else {
            Button {
                showTypePicker = true
            } label: {
                Image(ph: "plus")
                    .frame(width: 22, height: 22)
            }
        }
    }

    // MARK: - Editorial flat sections

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    private func monthSection(_ group: MonthGroup) -> some View {
        let net = group.net(in: defaultCurrency, fx: fx)
        return VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(group.month, format: .dateTime.year().month(.wide))
                    .appFont(.title3, weight: .semibold)
                Spacer()
                Text(net.asCompactCurrency(defaultCurrency))
                    .appFont(.caption, weight: .medium)
                    .foregroundStyle(net >= 0 ? Theme.income : Theme.expense)
                    .monospacedDigit()
            }

            VStack(spacing: 0) {
                ForEach(group.transactions) { txn in
                    Button {
                        editingTransaction = txn
                    } label: {
                        TransactionRow(transaction: txn)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if txn.id != group.transactions.last?.id {
                        Rectangle()
                            .fill(Theme.primaryText.opacity(0.06))
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    // MARK: - Aggregation

    private struct MonthGroup {
        let month: Date
        let transactions: [Transaction]
        func net(in displayCode: String, fx: ExchangeRateService) -> Double {
            transactions.reduce(0) { $0 + $1.signedConvertedAmount(to: displayCode, fx: fx) }
        }
    }

    private var filteredTransactions: [Transaction] {
        var result = project.transactions ?? []
        if filter != .all {
            let target: TransactionType = filter == .income ? .income : .expense
            result = result.filter { $0.type == target }
        }
        if !searchText.isEmpty {
            let lower = searchText.lowercased()
            result = result.filter {
                $0.note.lowercased().contains(lower)
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    private var grouped: [MonthGroup] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filteredTransactions) { txn -> Date in
            cal.date(from: cal.dateComponents([.year, .month], from: txn.date)) ?? txn.date
        }
        return dict
            .map { MonthGroup(month: $0.key, transactions: $0.value) }
            .sorted { $0.month > $1.month }
    }
}
