//
//  CategoryItemEditView.swift
//  DevCal
//
//  專案內子項目的建立/編輯表單。可以以兩種方式呈現：
//    - Push（`isPresentedInSheet = false`）：CategoryPickerView 在分類為空時直接
//      推進這個畫面。導覽列原本的返回箭頭就是離開機制，不需要 X。
//    - Sheet（`isPresentedInSheet = true`）：從項目列表的「新增項目」打開。
//      左上有 X 取消、且 sheet 禁止下滑關閉。
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct CategoryItemEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"

    let project: Project
    let category: TransactionCategory
    var editing: CategoryItem?
    var isPresentedInSheet: Bool = false
    var onSaved: ((CategoryItem) -> Void)? = nil

    @State private var name: String = ""
    @State private var defaultAmount: Double = 0
    @State private var originalCurrencyCode: String = "TWD"
    @State private var billingType: BillingType = .oneTime
    @State private var nextDueDate: Date = Date()
    @State private var brandIconKey: String? = nil
    @State private var fallbackIconName: String? = nil
    @State private var iconColorHex: String? = nil
    @State private var showIconPicker = false

    var body: some View {
        Form {
            Section {
                TextField("項目名稱", text: $name)
                HStack(spacing: 12) {
                    CurrencyMenuButton(selection: $originalCurrencyCode)
                    AmountFieldDivider()
                    TextField("0", value: $defaultAmount, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.leading)
                }
            } header: {
                Text("基本資料").formSectionHeaderStyle()
            } footer: {
                Text("之後記帳會自動帶入這個金額,但仍可依當次手動調整。")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("計費方式", selection: $billingType.animation()) {
                    Text("單次").tag(BillingType.oneTime)
                    Text("每月").tag(BillingType.monthly)
                    Text("每年").tag(BillingType.yearly)
                }
                if billingType.isRecurring {
                    DatePicker(
                        "下次扣款日",
                        selection: $nextDueDate,
                        displayedComponents: .date
                    )
                }
            } header: {
                Text("計費方式").formSectionHeaderStyle()
            } footer: {
                if billingType.isRecurring {
                    Text("每到扣款日會自動產生一筆紀錄。")
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                iconButton
            } header: {
                Text("圖標").formSectionHeaderStyle()
            }

            if editing != nil {
                Section {
                    Button(role: .destructive) {
                        deleteItem()
                    } label: {
                        Label("刪除項目", phImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .interactiveDismissDisabled(isPresentedInSheet)
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showIconPicker) {
            NavigationStack {
                IconPickerView(
                    category: category,
                    brandIconKey: $brandIconKey,
                    fallbackIconName: $fallbackIconName,
                    iconColorHex: $iconColorHex
                )
            }
            .interactiveDismissDisabled()
        }
        .onAppear(perform: loadIfEditing)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isPresentedInSheet {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .cancelActionStyle()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("儲存") { save() }
                .confirmActionStyle()
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Icon button

    private var iconButton: some View {
        Button {
            showIconPicker = true
        } label: {
            HStack(spacing: 12) {
                previewIcon
                    .frame(width: 22, height: 22)
                    .foregroundStyle(BrandIconRegistry.renderColor(brandKey: brandIconKey, iconColorHex: iconColorHex))
                Text("圖標")
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Text(iconSubtitle)
                    .appFont(.subheadline)
                    .foregroundStyle(Theme.primaryText.opacity(0.5))
                Image(systemName: "chevron.right")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(Theme.primaryText.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var previewIcon: some View {
        if BrandIconRegistry.hasAsset(for: brandIconKey) {
            BrandIconRegistry.image(for: brandIconKey)
        } else if let phName = fallbackIconName, !phName.isEmpty {
            Image(ph: phName)
                .resizable()
                .scaledToFit()
        } else {
            category.icon
        }
    }

    private var iconSubtitle: String {
        if let key = brandIconKey, BrandIconRegistry.hasAsset(for: key) {
            return BrandIconRegistry.displayName(for: key)
        }
        if let phName = fallbackIconName, !phName.isEmpty {
            return phName
        }
        return "預設"
    }

    private var navTitle: String {
        editing == nil ? "新增項目" : "編輯項目"
    }

    // MARK: - Persistence

    private func loadIfEditing() {
        guard let editing else {
            originalCurrencyCode = defaultCurrency
            return
        }
        name = editing.name
        defaultAmount = editing.totalAmount
        originalCurrencyCode = editing.originalCurrencyCode
        billingType = editing.billingType
        if let due = editing.nextDueDate { nextDueDate = due }
        brandIconKey = editing.brandIconKey
        fallbackIconName = editing.fallbackIconName
        iconColorHex = editing.iconColorHex
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let editing {
            editing.name = trimmed
            editing.totalAmount = defaultAmount
            editing.originalCurrencyCode = originalCurrencyCode
            editing.billingType = billingType
            editing.nextDueDate = billingType.isRecurring ? nextDueDate : nil
            editing.brandIconKey = brandIconKey
            editing.fallbackIconName = fallbackIconName
            editing.iconColorHex = iconColorHex
            editing.updatedAt = Date()
            try? context.save()
            onSaved?(editing)
            dismiss()
            return
        }

        let item = CategoryItem(
            name: trimmed,
            category: category,
            totalAmount: defaultAmount,
            originalCurrencyCode: originalCurrencyCode,
            billingType: billingType,
            brandIconKey: brandIconKey,
            fallbackIconName: fallbackIconName,
            iconColorHex: iconColorHex,
            nextDueDate: billingType.isRecurring ? nextDueDate : nil,
            isActive: true,
            isShared: false,
            projects: [project]
        )
        context.insert(item)
        try? context.save()
        onSaved?(item)
        dismiss()
    }

    private func deleteItem() {
        guard let editing else { return }
        context.delete(editing)
        try? context.save()
        dismiss()
    }
}
