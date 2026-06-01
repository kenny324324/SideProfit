//
//  SharedExpensesView.swift
//  DevCal
//
//  Lists shared CategoryItems (subscriptions and one-time purchases that
//  span multiple projects, like ChatGPT or a paid Figma seat). Tapping a row
//  edits it; the "+" toolbar button creates a new one.
//
//  Shared items appear inside the AddTransactionView category picker for any
//  project they are allocated to, showing the split share — see
//  CategoryPickerView for the consumer side.
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct SharedExpensesView: View {
    @Environment(\.modelContext) private var context

    @Query private var allItemsRaw: [CategoryItem]

    private var items: [CategoryItem] {
        allItemsRaw
            .filter { $0.isShared }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @State private var showTypePicker = false
    @State private var pendingType: TransactionType = .expense
    @State private var showEditor = false
    @State private var editingItem: CategoryItem?

    var body: some View {
        Group {
            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(groupedItems.enumerated()), id: \.element.0) { idx, group in
                            sectionHeader(group.0)
                            ForEach(Array(group.1.enumerated()), id: \.element.id) { rowIdx, item in
                                Button {
                                    editingItem = item
                                } label: {
                                    SharedItemRow(item: item)
                                }
                                .buttonStyle(.plain)
                                if rowIdx < group.1.count - 1 { hairline }
                            }
                            if idx < groupedItems.count - 1 {
                                sectionDivider
                            }
                        }
                        Spacer(minLength: 48)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBackground.ignoresSafeArea())
        .navigationTitle("共用項目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if #available(iOS 26.0, *) {
                    Button {
                        showTypePicker = true
                    } label: {
                        Image(ph: "plus")
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Theme.onTint)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                } else {
                    Button {
                        showTypePicker = true
                    } label: {
                        Image(ph: "plus")
                            .frame(width: 18, height: 18)
                    }
                }
            }
        }
        .sheet(isPresented: $showTypePicker) {
            TransactionTypePickerSheet { picked in
                pendingType = picked
                // 等 type sheet 收完再開編輯器,避免兩個 sheet race。
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showEditor = true
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                SharedExpenseEditView(editing: nil, initialType: pendingType)
            }
            .interactiveDismissDisabled()
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                SharedExpenseEditView(editing: item)
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Grouping

    private var groupedItems: [(TransactionCategory, [CategoryItem])] {
        let dict = Dictionary(grouping: items, by: { $0.category })
        return TransactionCategory.allCases
            .compactMap { cat -> (TransactionCategory, [CategoryItem])? in
                guard let group = dict[cat], !group.isEmpty else { return nil }
                return (cat, group.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(ph: "share-network")
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.primaryText.opacity(0.4))
            Text("尚未設定共用項目")
                .appFont(.headline)
                .foregroundStyle(Theme.primaryText)
                .multilineTextAlignment(.center)
            Text("共用項目用來追蹤跨專案的訂閱或工具,例如 ChatGPT 或 Figma 訂閱。每個專案只會看到自己分攤的金額。")
                .appFont(.subheadline)
                .foregroundStyle(Theme.primaryText.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Section pieces

    private func sectionHeader(_ category: TransactionCategory) -> some View {
        HStack(spacing: 8) {
            category.icon
                .frame(width: 14, height: 14)
                .foregroundStyle(Theme.primaryText.opacity(0.5))
            Text(category.displayName)
                .formSectionHeaderStyle()
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
    }
}

// MARK: - Row

private struct SharedItemRow: View {
    let item: CategoryItem

    var body: some View {
        HStack(spacing: 14) {
            item.displayIcon
                .frame(width: 22, height: 22)
                .foregroundStyle(BrandIconRegistry.renderColor(brandKey: item.brandIconKey, iconColorHex: item.iconColorHex))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(Theme.primaryText)
                Text(subtitle)
                    .appFont(.footnote)
                    .foregroundStyle(Theme.primaryText.opacity(0.5))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formattedTotal)
                    .appFont(.subheadline, weight: .semibold)
                    .foregroundStyle(Theme.primaryText)
                Text(billingLabel)
                    .appFont(.caption)
                    .foregroundStyle(Theme.primaryText.opacity(0.5))
            }
            Image(systemName: "chevron.right")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(Theme.primaryText.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let projectCount = (item.projects ?? []).count
        let mode = item.splitMode == .equal
            ? String(localized: "平均分攤")
            : String(localized: "自訂比例")
        return String(localized: "\(projectCount) 個專案 · \(mode)")
    }

    private var formattedTotal: String {
        CurrencyFormatter.format(item.totalAmount, currencyCode: item.originalCurrencyCode)
    }

    private var billingLabel: String {
        switch item.billingType {
        case .oneTime: return String(localized: "單次")
        case .monthly: return String(localized: "每月")
        case .yearly: return String(localized: "每年")
        }
    }
}
