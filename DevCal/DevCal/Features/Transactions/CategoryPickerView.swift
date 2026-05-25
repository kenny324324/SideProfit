//
//  CategoryPickerView.swift
//  DevCal
//
//  純分類選擇器。流程：
//    1. 顯示當前 type (支出/收入) 下的所有大分類，扁平列表。
//    2. 點一個分類 → push 到 IconPickerView 設定圖標 + 顏色。
//    3. IconPickerView 完成 → dismiss 整個 sheet，回到 AddTransactionView。
//
//  完全不碰子項目系統 (CategoryItem)。子項目只在訂閱排程 + 共用支出
//  系統內部使用，使用者不會在新增交易的流程中見到它。
//

import SwiftUI
import PhosphorSymbols

struct CategoryPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let type: TransactionType
    @Binding var selectedCategory: TransactionCategory?
    @Binding var brandIconKey: String?
    @Binding var fallbackIconName: String?
    @Binding var iconColorHex: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(categoriesForType.enumerated()), id: \.element) { index, cat in
                        NavigationLink {
                            IconPickerView(
                                category: cat,
                                brandIconKey: $brandIconKey,
                                fallbackIconName: $fallbackIconName,
                                iconColorHex: $iconColorHex,
                                onDone: {
                                    selectedCategory = cat
                                    dismiss()
                                }
                            )
                        } label: {
                            CategoryRow(category: cat, isSelected: selectedCategory == cat)
                        }
                        .buttonStyle(.plain)
                        if index < categoriesForType.count - 1 {
                            hairline
                        }
                    }
                }
            }
            .background(Theme.appBackground)
            .navigationTitle("選擇分類")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .cancelActionStyle()
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private var categoriesForType: [TransactionCategory] {
        TransactionCategory.categories(for: type)
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.07))
            .frame(height: 0.5)
            .padding(.leading, 56)
    }
}

private struct CategoryRow: View {
    let category: TransactionCategory
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            category.icon
                .frame(width: 20, height: 20)
                .foregroundStyle(Theme.primaryText)
                .frame(width: 36, height: 36)
            Text(category.displayName)
                .appFont(.body, weight: .medium)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(Theme.brand)
            }
            Image(systemName: "chevron.right")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(Theme.primaryText.opacity(0.3))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
