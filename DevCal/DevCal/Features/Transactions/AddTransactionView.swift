//
//  AddTransactionView.swift
//  DevCal
//
//  唯一一個記支出 / 收入的入口。所有設定都在這頁完成：名稱、金額、
//  分類 + 圖標 + 顏色、單次 / 訂閱、日期、備註。
//
//  訂閱：按存的時候會自動建一個幕後 CategoryItem 給排程器用，使用者
//  看不到「子項目」這個概念。單次：只建 Transaction，沒有幕後物件。
//
//  Platform fee：儲存類型為 appSales / subscriptions 的 income 時，會
//  跳 systemAlert 詢問是否補一筆平台抽成（Apple / Google 自動偵測，無法
//  偵測時先問廠商）。
//
//  Phase 0: persistence + business rules moved to TransactionUseCase. This
//  file now owns form state, validation gating, the platform-fee alert flow,
//  and surfacing errors.
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct AddTransactionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.transactionUseCase) private var useCase
    @Environment(AppReviewPrompter.self) private var appReviewPrompter
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"
    @Environment(ExchangeRateService.self) private var fx

    let project: Project
    var editing: Transaction?

    @State private var type: TransactionType
    @State private var name: String = ""
    @State private var amount: Double = 0
    @State private var originalCurrencyCode: String = "TWD"
    @State private var category: TransactionCategory? = nil
    @State private var iconBrandKey: String? = nil
    @State private var iconFallbackName: String? = nil
    @State private var iconColorHex: String? = nil
    @State private var billingType: BillingType = .oneTime
    @State private var nextDueDate: Date = Date()
    @State private var note: String = ""
    @State private var date: Date = Date()
    @State private var showCategoryPicker = false

    // Platform-fee flow state. The view drives the alert; the use case
    // actually creates the fee Transaction.
    @State private var showVendorAlert = false
    @State private var showPercentAlert = false
    @State private var feeVendor: PlatformFeeVendor? = nil
    @State private var pendingReviewReachedBreakEven = false

    // Error surface. Repos throw `DataLayerError`; we show it via a single alert.
    @State private var saveError: String? = nil
    @State private var showErrorAlert = false

    init(project: Project, initialType: TransactionType = .expense, editing: Transaction? = nil) {
        self.project = project
        self.editing = editing
        self._type = State(initialValue: editing?.type ?? initialType)
    }

    var body: some View {
        Form {
            Section {
                TextField(namePlaceholder, text: $name)
            } header: {
                Text("Name").formSectionHeaderStyle()
            }

            Section {
                amountField
                if shouldShowConvertedPreview {
                    convertedPreviewRow
                }
            } header: {
                Text("Amount").formSectionHeaderStyle()
            }

            Section {
                categoryRow
            } header: {
                Text("Category").formSectionHeaderStyle()
            }

            // Subscription/billing section — only shown when creating a new
            // transaction. Editing an existing one shouldn't flip it between
            // one-time and recurring on the fly; that needs to be done from a
            // future "訂閱管理" page.
            if editing == nil {
                Section {
                    Picker("計費方式", selection: $billingType.animation()) {
                        Text("單次").tag(BillingType.oneTime)
                        Text("每月").tag(BillingType.monthly)
                        Text("每年").tag(BillingType.yearly)
                    }
                    if billingType.isRecurring {
                        DatePicker("開始日期", selection: $nextDueDate, displayedComponents: .date)
                    }
                } header: {
                    Text("Billing").formSectionHeaderStyle()
                } footer: {
                    if billingType.isRecurring, let hint = billingHint {
                        Text(hint)
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Note (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("Details").formSectionHeaderStyle()
            }

            if editing != nil {
                Section {
                    Button(role: .destructive) {
                        Task { await runDelete() }
                    } label: {
                        Label(deleteLabelKey, phImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.appBackground)
        .interactiveDismissDisabled()
        .navigationTitle(titleKey)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
                    .cancelActionStyle()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task { await runSave() }
                }
                    .confirmActionStyle()
                    .disabled(!canSave)
            }
        }
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPickerView(
                type: type,
                selectedCategory: $category,
                brandIconKey: $iconBrandKey,
                fallbackIconName: $iconFallbackName,
                iconColorHex: $iconColorHex
            )
        }
        .systemAlert("此筆收入來自？", isPresented: $showVendorAlert) {
            Button("Apple") {
                feeVendor = .apple
                queuePercentAlert()
            }
            Button("Google") {
                feeVendor = .google
                queuePercentAlert()
            }
            Button("跳過", role: .cancel) { finishAfterFeeFlow() }
        } message: {
            Text("會用來計算平台抽成。")
        }
        .systemAlert("同時記一筆平台抽成？", isPresented: $showPercentAlert) {
            Button("記 30%") { Task { await runCreatePlatformFee(percent: 0.30) } }
            Button("記 15%") { Task { await runCreatePlatformFee(percent: 0.15) } }
            Button("跳過", role: .cancel) { finishAfterFeeFlow() }
        } message: {
            Text("Apple/Google 通常會收取 30%(小型企業 15%)。會自動建立一筆對應的支出。")
        }
        .systemAlert("Save failed", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear(perform: loadIfEditing)
    }

    // MARK: - Amount field

    @ViewBuilder
    private var amountField: some View {
        HStack(spacing: 12) {
            CurrencyMenuButton(selection: $originalCurrencyCode)
            AmountFieldDivider()
            TextField("0", value: $amount, format: .number)
                .keyboardType(.decimalPad)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.leading)
        }
    }

    /// "≈ NT$640" preview that updates live while the user types — only shows
    /// when the user's input currency differs from their display currency.
    private var convertedPreviewRow: some View {
        HStack {
            Text("換算後")
                .appFont(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(convertedPreviewText)
                .appFont(.footnote, weight: .medium)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var shouldShowConvertedPreview: Bool {
        amount > 0 && originalCurrencyCode != defaultCurrency
    }

    private var convertedPreviewText: String {
        if let converted = fx.convert(amount, from: originalCurrencyCode, to: defaultCurrency) {
            return "≈ " + converted.asCurrency(defaultCurrency)
        }
        return "≈ —"
    }

    /// "之後每月 15 號扣款" / "之後每年 3 月 15 日扣款"。開始日期是過去
    /// 就會在排程器跑的時候從那天起補齊每一期的紀錄。
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

    // MARK: - Category disclosure row

    private var categoryRow: some View {
        Button {
            showCategoryPicker = true
        } label: {
            HStack(spacing: 12) {
                renderedIcon
                    .frame(width: 22, height: 22)
                    .foregroundStyle(BrandIconRegistry.renderColor(brandKey: iconBrandKey, iconColorHex: iconColorHex))
                if let category {
                    Text(category.displayName)
                        .appFont(.body, weight: .medium)
                        .foregroundStyle(Theme.primaryText)
                } else {
                    Text("選擇分類")
                        .appFont(.body, weight: .medium)
                        .foregroundStyle(Theme.primaryText.opacity(0.35))
                }
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
        if let key = iconBrandKey, BrandIconRegistry.hasAsset(for: key) {
            BrandIconRegistry.image(for: key)
        } else if let phName = iconFallbackName, !phName.isEmpty {
            Image(ph: phName)
                .resizable()
                .scaledToFit()
        } else if let category {
            category.icon
        } else {
            Image(ph: "folder")
                .resizable()
                .scaledToFit()
        }
    }

    // MARK: - Derived

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && amount > 0
            && category != nil
    }

    private var namePlaceholder: LocalizedStringKey {
        type == .income ? "收入名稱" : "支出名稱"
    }

    // MARK: - Loading

    private func loadIfEditing() {
        guard let editing else {
            originalCurrencyCode = defaultCurrency
            return
        }
        type = editing.type
        name = editing.name
        category = editing.category
        amount = editing.originalAmount
        originalCurrencyCode = editing.originalCurrencyCode
        iconBrandKey = editing.iconBrandKey
        iconFallbackName = editing.iconFallbackName
        iconColorHex = editing.iconColorHex
        note = editing.note
        date = editing.date
    }

    // MARK: - Save / Delete

    private func currentFormInput() -> TransactionUseCase.TransactionFormInput? {
        guard let category else { return nil }
        return TransactionUseCase.TransactionFormInput(
            project: project,
            type: type,
            category: category,
            name: name,
            iconBrandKey: iconBrandKey,
            iconFallbackName: iconFallbackName,
            iconColorHex: iconColorHex,
            originalAmount: amount,
            originalCurrencyCode: originalCurrencyCode,
            note: note,
            date: date,
            billingType: billingType,
            nextDueDate: nextDueDate
        )
    }

    private func runSave() async {
        guard let useCase, let input = currentFormInput() else { return }
        do {
            let outcome: TransactionUseCase.TransactionSaveOutcome
            if let editing {
                outcome = try await useCase.update(
                    editing,
                    with: input,
                    displayCurrency: defaultCurrency,
                    fx: fx
                )
            } else {
                outcome = try await useCase.save(
                    input,
                    displayCurrency: defaultCurrency,
                    fx: fx
                )
            }

            if outcome.shouldOfferPlatformFee {
                pendingReviewReachedBreakEven = outcome.reachedBreakEvenForThisWrite
                if let detected = detectVendor() {
                    feeVendor = detected
                    showPercentAlert = true
                } else {
                    showVendorAlert = true
                }
                return
            }

            recordSuccessfulTransaction(reachedBreakEven: outcome.reachedBreakEvenForThisWrite)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func runDelete() async {
        guard let useCase, let editing else { return }
        do {
            try await useCase.delete(editing)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func runCreatePlatformFee(percent: Double) async {
        guard let useCase, let vendor = feeVendor, let input = currentFormInput() else {
            finishAfterFeeFlow()
            return
        }
        do {
            let feeAlsoTippedBreakEven = try await useCase.createPlatformFee(
                for: input,
                vendor: vendor,
                percent: percent,
                displayCurrency: defaultCurrency,
                fx: fx
            )
            pendingReviewReachedBreakEven = pendingReviewReachedBreakEven || feeAlsoTippedBreakEven
            finishAfterFeeFlow()
        } catch {
            present(error)
        }
    }

    private func detectVendor() -> PlatformFeeVendor? {
        if iconBrandKey == "apple" { return .apple }
        if iconBrandKey == "google" { return .google }
        let lowered = name.lowercased()
        if lowered.contains("apple") || lowered.contains("app store") { return .apple }
        if lowered.contains("google") || lowered.contains("play store") { return .google }
        return nil
    }

    private func finishAfterFeeFlow() {
        recordSuccessfulTransaction(reachedBreakEven: pendingReviewReachedBreakEven)
        pendingReviewReachedBreakEven = false
        feeVendor = nil
        dismiss()
    }

    private func recordSuccessfulTransaction(reachedBreakEven: Bool) {
        appReviewPrompter.record(.transactionCreated)
        if reachedBreakEven {
            appReviewPrompter.record(.breakEvenReached)
        }
    }

    private func present(_ error: Error) {
        saveError = error.localizedDescription
        showErrorAlert = true
    }

    /// 連續觸發兩個 systemAlert 之間需要一個短延遲，避免第二個 alert 被
    /// 系統 race 掉直接 no-op。
    private func queuePercentAlert() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showPercentAlert = true
        }
    }

    private var titleKey: LocalizedStringKey {
        if editing == nil {
            return type == .income ? "Add income" : "Add expense"
        }
        return type == .income ? "Edit income" : "Edit expense"
    }

    private var deleteLabelKey: LocalizedStringKey {
        type == .income ? "Delete income" : "Delete expense"
    }
}
