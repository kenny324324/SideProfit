//
//  SharedExpenseEditView.swift
//  DevCal
//
//  Create or edit a shared CategoryItem — an expense (or income) that spans
//  multiple projects with an allocation policy. Generates Transactions for
//  every allocated project when its `nextDueDate` fires (handled by
//  SubscriptionScheduler).
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct SharedExpenseEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ExchangeRateService.self) private var fx
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"

    var editing: CategoryItem?
    /// 由父頁透過 TransactionTypePickerSheet 預先決定的類型。新建時必傳;
    /// 編輯模式下會被 loadIfEditing 蓋掉成現有的 type。
    var initialType: TransactionType = .expense

    @Query private var allProjectsRaw: [Project]

    private var allProjects: [Project] {
        allProjectsRaw
            .filter { $0.archivedAt == nil }
            .sorted {
                if $0.sortIndex != $1.sortIndex { return $0.sortIndex < $1.sortIndex }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    @State private var name: String = ""
    @State private var type: TransactionType = .expense
    @State private var category: TransactionCategory = .aiTools
    @State private var totalAmount: Double = 0
    @State private var originalCurrencyCode: String = "TWD"
    @State private var billingType: BillingType = .monthly
    @State private var nextDueDate: Date = Date()
    @State private var brandIconKey: String? = nil
    @State private var fallbackIconName: String? = nil
    @State private var iconColorHex: String? = nil
    @State private var splitMode: SplitMode = .equal
    @State private var selectedProjectIDs: Set<UUID> = []
    @State private var weights: [UUID: Double] = [:]
    @State private var showCategoryPicker = false

    var body: some View {
        Form {
            basicsSection
            amountSection
            projectsSection
            splitSection
            deleteSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .interactiveDismissDisabled()
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showCategoryPicker) { categoryPickerSheet }
        .onAppear(perform: loadIfEditing)
    }

    // MARK: - Sections

    @ViewBuilder
    private var basicsSection: some View {
        Section {
            TextField("共用項目", text: $name)
            categoryRow
        } header: {
            Text("基本資料").formSectionHeaderStyle()
        }
    }

    @ViewBuilder
    private var amountSection: some View {
        Section {
            amountField
            billingPicker
            if billingType.isRecurring {
                DatePicker(
                    "開始日期",
                    selection: $nextDueDate,
                    displayedComponents: .date
                )
            }
        } header: {
            Text("金額").formSectionHeaderStyle()
        } footer: {
            if billingType.isRecurring, let hint = billingHint {
                Text(hint)
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "之後每月 15 號扣款" / "之後每年 3 月 15 日扣款"。開始日期是過去就會
    /// 在排程器跑的時候從那天起補齊每一期的紀錄。
    private var billingHint: String? {
        guard billingType.isRecurring else { return nil }
        let cal = Calendar.current
        let day = cal.component(.day, from: nextDueDate)
        switch billingType {
        case .monthly:
            return "之後每月 \(day) 號扣款。開始日期若早於今天,會自動補齊每一期的紀錄。"
        case .yearly:
            let month = cal.component(.month, from: nextDueDate)
            return "之後每年 \(month) 月 \(day) 日扣款。開始日期若早於今天,會自動補齊每一年的紀錄。"
        case .oneTime:
            return nil
        }
    }

    @ViewBuilder
    private var projectsSection: some View {
        Section {
            ForEach(allProjects, id: \.id) { proj in
                projectRow(proj)
            }
        } header: {
            Text("適用專案").formSectionHeaderStyle()
        } footer: {
            if selectedProjectIDs.count < 2 {
                Text("選 2 個以上專案才會分攤;只選 1 個就只算在那一個專案上。")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var splitSection: some View {
        if selectedProjectIDs.count >= 2 {
            Section {
                splitModePicker
                if splitMode == .weighted {
                    ForEach(orderedSelectedProjects, id: \.id) { proj in
                        weightRow(proj)
                    }
                }
                splitPreview
            } header: {
                Text("分攤方式").formSectionHeaderStyle()
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        if editing != nil {
            Section {
                Button(role: .destructive, action: deleteItem) {
                    Label("刪除共用項目", phImage: "trash")
                }
            }
        }
    }

    // MARK: - Pickers

    private var billingPicker: some View {
        Picker("計費方式", selection: $billingType.animation()) {
            Text("單次").tag(BillingType.oneTime)
            Text("每月").tag(BillingType.monthly)
            Text("每年").tag(BillingType.yearly)
        }
    }

    private var splitModePicker: some View {
        Picker("分攤", selection: $splitMode.animation()) {
            Text("平均").tag(SplitMode.equal)
            Text("自訂").tag(SplitMode.weighted)
        }
        .pickerStyle(.segmented)
    }

    private var amountField: some View {
        HStack(spacing: 12) {
            CurrencyMenuButton(selection: $originalCurrencyCode)
            AmountFieldDivider()
            TextField("0", value: $totalAmount, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
        }
    }

    /// 仿照 AddTransactionView 的分類列 — 一行顯示圖標 + 分類名稱,
    /// 點下去打開組合式 CategoryPickerView (內含 IconPickerView)。
    private var categoryRow: some View {
        Button {
            showCategoryPicker = true
        } label: {
            HStack(spacing: 12) {
                renderedIcon
                    .frame(width: 22, height: 22)
                    .foregroundStyle(BrandIconRegistry.renderColor(brandKey: brandIconKey, iconColorHex: iconColorHex))
                Text(category.displayName)
                    .appFont(.body, weight: .medium)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Image(systemName: "chevron.right")
                    .appFont(.footnote, weight: .semibold)
                    .foregroundStyle(Theme.primaryText.opacity(0.3))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var renderedIcon: some View {
        if let key = brandIconKey, BrandIconRegistry.hasAsset(for: key) {
            BrandIconRegistry.image(for: key)
        } else if let phName = fallbackIconName, !phName.isEmpty {
            Image(ph: phName)
                .resizable()
                .scaledToFit()
        } else {
            category.icon
        }
    }

    // MARK: - Toolbar + sheets

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .cancelActionStyle()
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("儲存") { save() }
                .confirmActionStyle()
                .disabled(!canSave)
        }
    }

    /// 用跟 AddTransactionView 同一個 CategoryPickerView,內部會 push 到
    /// IconPickerView。CategoryPickerView 期望 `selectedCategory` 是
    /// Optional,所以用 Binding wrapper 把 non-optional 包起來。
    private var categoryPickerSheet: some View {
        CategoryPickerView(
            type: type,
            selectedCategory: Binding<TransactionCategory?>(
                get: { category },
                set: { if let new = $0 { category = new } }
            ),
            brandIconKey: $brandIconKey,
            fallbackIconName: $fallbackIconName,
            iconColorHex: $iconColorHex
        )
    }

    private var navTitle: String {
        editing == nil ? "新增共用項目" : "編輯共用項目"
    }

    // MARK: - Sub-views

    private func projectRow(_ project: Project) -> some View {
        Button {
            toggle(project)
        } label: {
            HStack {
                Text(project.name)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                if selectedProjectIDs.contains(project.id) {
                    Image(systemName: "checkmark")
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(Theme.brand)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func weightRow(_ project: Project) -> some View {
        HStack {
            Text(project.name)
                .foregroundStyle(Theme.primaryText)
            Spacer()
            TextField("0", value: weightBinding(for: project.id), format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
        }
    }

    private var splitPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(splitMode == .equal ? "平均分攤預覽" : "自訂比例預覽")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(Theme.primaryText.opacity(0.6))
            ForEach(orderedSelectedProjects, id: \.id) { proj in
                HStack {
                    Text(proj.name)
                        .appFont(.footnote)
                        .foregroundStyle(Theme.primaryText.opacity(0.7))
                    Spacer()
                    Text(splitShareLabel(for: proj))
                        .appFont(.footnote, weight: .semibold)
                        .foregroundStyle(Theme.primaryText)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Derived

    private var orderedSelectedProjects: [Project] {
        allProjects.filter { selectedProjectIDs.contains($0.id) }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && totalAmount > 0
            && !selectedProjectIDs.isEmpty
    }

    private func splitShareLabel(for project: Project) -> String {
        let share = computedShare(for: project)
        return CurrencyFormatter.format(share, currencyCode: originalCurrencyCode)
    }

    private func computedShare(for project: Project) -> Double {
        let projects = orderedSelectedProjects
        guard !projects.isEmpty else { return 0 }
        if projects.count == 1 { return totalAmount }
        switch splitMode {
        case .equal:
            return totalAmount / Double(projects.count)
        case .weighted:
            let weightValues = projects.map { weights[$0.id] ?? 0 }
            let total = weightValues.reduce(0, +)
            guard total > 0 else { return 0 }
            guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return 0 }
            return totalAmount * (weightValues[idx] / total)
        }
    }

    // MARK: - Binding helpers

    private func toggle(_ project: Project) {
        if selectedProjectIDs.contains(project.id) {
            selectedProjectIDs.remove(project.id)
            weights.removeValue(forKey: project.id)
        } else {
            selectedProjectIDs.insert(project.id)
            if weights[project.id] == nil { weights[project.id] = 1 }
        }
    }

    private func weightBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { weights[id] ?? 0 },
            set: { weights[id] = $0 }
        )
    }

    // MARK: - Persistence

    private func loadIfEditing() {
        guard let editing else {
            originalCurrencyCode = defaultCurrency
            // 新增情境:用父頁帶進來的 initialType,並把分類也對應到該 type
            // 第一個分類,避免 expense 分類被存進 income 項目這種錯。
            type = initialType
            category = TransactionCategory.categories(for: initialType).first ?? category
            return
        }
        name = editing.name
        type = editing.transactionType
        category = editing.category
        totalAmount = editing.totalAmount
        originalCurrencyCode = editing.originalCurrencyCode
        billingType = editing.billingType
        if let due = editing.nextDueDate { nextDueDate = due }
        brandIconKey = editing.brandIconKey
        fallbackIconName = editing.fallbackIconName
        iconColorHex = editing.iconColorHex
        splitMode = editing.splitMode
        let projects = editing.projects ?? []
        selectedProjectIDs = Set(projects.map(\.id))
        if let weights = editing.weights, weights.count == projects.count {
            for (idx, proj) in projects.enumerated() {
                self.weights[proj.id] = weights[idx]
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard canSave else { return }
        let projects = orderedSelectedProjects
        let weightArray: [Double]? = splitMode == .weighted
            ? projects.map { weights[$0.id] ?? 0 }
            : nil

        // 在共用項目頁建的東西一律 isShared = true,即使只挑一個專案也是。
        // 這樣 SharedExpensesView 的 filter (isShared == true) 才會顯示;
        // AddTransactionView 訂閱流程建的 CategoryItem 才會被排除在外。
        if let editing {
            editing.name = trimmed
            editing.category = category
            editing.totalAmount = totalAmount
            editing.originalCurrencyCode = originalCurrencyCode
            editing.billingType = billingType
            editing.nextDueDate = billingType.isRecurring ? nextDueDate : nil
            editing.brandIconKey = brandIconKey
            editing.fallbackIconName = fallbackIconName
            editing.iconColorHex = iconColorHex
            editing.splitMode = splitMode
            editing.isShared = true
            editing.projects = projects
            editing.weights = weightArray
            editing.updatedAt = Date()
        } else {
            let item = CategoryItem(
                name: trimmed,
                category: category,
                totalAmount: totalAmount,
                originalCurrencyCode: originalCurrencyCode,
                billingType: billingType,
                brandIconKey: brandIconKey,
                fallbackIconName: fallbackIconName,
                iconColorHex: iconColorHex,
                nextDueDate: billingType.isRecurring ? nextDueDate : nil,
                isActive: true,
                isShared: true,
                splitMode: splitMode,
                weights: weightArray,
                projects: projects
            )
            context.insert(item)
        }
        try? context.save()
        // 立刻跑排程器:讓 startDate 為今天 / 過去日期的訂閱馬上產生交易,
        // 使用者按存的當下就能在專案內看到。預設只在 app 啟動 / scenePhase
        // .active 跑,這邊主動補一次。
        SubscriptionScheduler.runDueCheck(
            context: context,
            displayCurrency: defaultCurrency,
            fx: fx
        )
        dismiss()
    }

    private func deleteItem() {
        guard let editing else { return }
        context.delete(editing)
        try? context.save()
        dismiss()
    }
}

