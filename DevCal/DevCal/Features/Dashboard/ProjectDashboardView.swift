//
//  ProjectDashboardView.swift
//  DevCal
//
//  The core "is my project becoming real?" screen. Hero is a two-stage progress
//  banner pinned to the top (Liquid Glass on iOS 26+). Below: a 4-tile metrics
//  card grid, then flat editorial sections (Monthly trend / Recent entries /
//  Time Log) separated by hairlines — matching ProjectListView + Settings.
//
//  Multi-currency: every number is converted to the user's display currency
//  via the shared ExchangeRateService. When the cached rate table is stale
//  (>24h), a banner sits below the hero to nudge the user toward Settings →
//  匯率 → 立即更新.
//

import SwiftUI
import SwiftData
import Charts
import PhosphorSymbols

struct ProjectDashboardView: View {
    @Environment(\.projectRepository) private var projectRepository
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements
    @Environment(ExchangeRateService.self) private var fx
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"
    @Bindable var project: Project

    @State private var pendingNewType: TransactionType?
    @State private var showTypePicker = false
    @State private var pickedType: TransactionType?
    @State private var showEditProject = false
    @State private var showSetGoal = false
    @State private var showPaywall = false
    @State private var showDeleteConfirm = false
    @State private var bannerHeight: CGFloat = 0
    @State private var deleteError: String? = nil
    @State private var showDeleteErrorAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if fx.isStale {
                    fxStaleBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                metricsGrid
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                sectionDivider
                monthlyTrendSection

                sectionDivider
                recentEntriesSection

                sectionDivider
                timeLogSection
            }
            .padding(.bottom, 24)
        }
        .contentMargins(.top, bannerHeight + 20, for: .scrollContent)
        .overlay(alignment: .top) {
            heroBanner
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newValue in
                    bannerHeight = newValue
                }
        }
        .background(Theme.appBackground)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit project") { showEditProject = true }
                    if project.goalAmount != nil {
                        Button("Edit goal") { showSetGoal = true }
                    }
                    NavigationLink("專案分析") {
                        ProjectAnalyticsView(project: project)
                    }
                    NavigationLink("All entries") {
                        TransactionsListView(project: project)
                    }
                    NavigationLink("Time logs") {
                        TimeCostView(project: project)
                    }
                    Divider()
                    Button("Delete project", role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(ph: "dots-three-outline", weight: .fill)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Theme.primaryText)
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()
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
        .sheet(isPresented: $showEditProject) {
            NavigationStack {
                AddProjectView(editing: project)
            }
        }
        .sheet(isPresented: $showSetGoal) {
            NavigationStack {
                SetGoalView(project: project)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
        .systemAlert(
            "確定要刪除這個專案？",
            isPresented: $showDeleteConfirm
        ) {
            Button("取消", role: .cancel) { }
            Button("刪除", role: .destructive) {
                Task { await deleteProject() }
            }
        } message: {
            Text("這會永久刪除此專案及其所有支出、收入與時間紀錄,無法復原。")
        }
        .systemAlert("Delete failed", isPresented: $showDeleteErrorAlert) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    @MainActor
    private func deleteProject() async {
        guard let repo = projectRepository else { return }
        do {
            try await repo.deleteProject(project)
            dismiss()
        } catch {
            deleteError = error.localizedDescription
            showDeleteErrorAlert = true
        }
    }

    // MARK: - FX stale banner

    private var fxStaleBanner: some View {
        HStack(spacing: 10) {
            Image(ph: "warning-circle")
                .frame(width: 16, height: 16)
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("匯率可能過期")
                    .appFont(.footnote, weight: .semibold)
                Text(staleSubtitle)
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await fx.refresh() }
            } label: {
                if fx.isFetching {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("立即更新")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(Theme.brand)
                }
            }
            .buttonStyle(.plain)
            .disabled(fx.isFetching)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.warning.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.warning.opacity(0.25), lineWidth: 0.5)
        }
    }

    private var staleSubtitle: String {
        if let last = fx.lastUpdated {
            let days = Int(Date().timeIntervalSince(last) / 86_400)
            return days <= 0 ? "今天還沒更新" : "已 \(days) 天沒更新"
        }
        return "尚未取得匯率"
    }

    // MARK: - Hero banner (fixed-top progress)

    private var heroBanner: some View {
        let progress = project.progress(in: defaultCurrency, fx: fx)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(progressLabel)
                    .appFont(.subheadline, weight: .semibold)
                if shouldShowPercent {
                    Text("\(Int((progress * 100).rounded()))%")
                        .appFont(.subheadline, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                }
                Spacer()
                if project.stage == .justReached {
                    Button {
                        showSetGoal = true
                    } label: {
                        Text("Set your goal")
                            .appFont(.caption, weight: .semibold)
                            .foregroundStyle(Theme.income)
                    }
                    .buttonStyle(.plain)
                } else if let caption = bannerCaption {
                    Text(caption)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            progressBar(progress: progress)

            if let projection = goalProjection {
                Text(projection.text)
                    .appFont(.caption)
                    .foregroundStyle(projection.tint)
            }
        }
        .padding(14)
        .bannerStyle()
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.primaryText.opacity(0.08))
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.income)
                    .frame(width: geo.size.width * progress)
                    .animation(.snappy, value: progress)
            }
        }
        .frame(height: 8)
    }

    private var progressLabel: LocalizedStringKey {
        switch project.stage {
        case .stageOne: return "Break-even"
        case .justReached: return "Break-even reached"
        case .stageTwo: return "Goal"
        }
    }

    private var shouldShowPercent: Bool {
        switch project.stage {
        case .stageOne: return project.totalExpenses(in: defaultCurrency, fx: fx) > 0
        case .justReached: return false
        case .stageTwo: return true
        }
    }

    private var bannerCaption: String? {
        let totalIncome = project.totalIncome(in: defaultCurrency, fx: fx)
        let totalExpenses = project.totalExpenses(in: defaultCurrency, fx: fx)
        switch project.stage {
        case .stageOne:
            guard totalExpenses > 0 else { return nil }
            return "\(totalIncome.asCompactCurrency(defaultCurrency)) / \(totalExpenses.asCompactCurrency(defaultCurrency))"
        case .justReached:
            return nil
        case .stageTwo:
            guard let goal = project.goalAmount else { return nil }
            let goalConverted = fx.convert(goal, from: project.goalCurrencyCode ?? defaultCurrency, to: defaultCurrency) ?? goal
            return "\(totalIncome.asCompactCurrency(defaultCurrency)) / \(goalConverted.asCompactCurrency(defaultCurrency))"
        }
    }

    // MARK: - Goal projection

    private struct Projection {
        let text: LocalizedStringKey
        let tint: Color
    }

    /// Estimated months-to-goal from recent revenue trend, compared with the
    /// optional `goalDeadline`. Returns nil when no deadline is set.
    private var goalProjection: Projection? {
        guard project.stage == .stageTwo,
              let goal = project.goalAmount, goal > 0,
              let deadline = project.goalDeadline else { return nil }
        let goalInDisplay = fx.convert(goal, from: project.goalCurrencyCode ?? defaultCurrency, to: defaultCurrency) ?? goal
        let income = project.totalIncome(in: defaultCurrency, fx: fx)
        let remaining = max(0, goalInDisplay - income)
        if remaining == 0 {
            return Projection(text: "Goal reached", tint: Theme.income)
        }
        let cal = Calendar.current
        let now = Date()
        guard let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: now) else { return nil }
        let recentIncome = (project.transactions ?? [])
            .filter { $0.type == .income && $0.date >= threeMonthsAgo }
            .reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
        let monthlyRate = recentIncome / 3
        guard monthlyRate > 0 else {
            return Projection(text: "No recent revenue — start logging income.", tint: .secondary)
        }
        let monthsRemaining = Int((remaining / monthlyRate).rounded(.up))
        let monthsUntilDeadline = cal.dateComponents([.month], from: now, to: deadline).month ?? 0
        let diff = monthsRemaining - monthsUntilDeadline
        if diff <= 0 {
            let text: LocalizedStringKey = monthsRemaining == 1
                ? "On track — projected in 1 month"
                : "On track — projected in \(monthsRemaining) months"
            return Projection(text: text, tint: Theme.income)
        } else {
            let text: LocalizedStringKey = diff == 1
                ? "Behind by ~1 month"
                : "Behind by ~\(diff) months"
            return Projection(text: text, tint: Theme.expense)
        }
    }

    // MARK: - Toolbar add-entry button (iOS 26: brand-tinted, white icon)

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

    // MARK: - Numbers row — KEEPS card style

    private var metricsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let net = project.netProfit(in: defaultCurrency, fx: fx)
        return LazyVGrid(columns: columns, spacing: 12) {
            incomeExpenseTile
            MetricTile(
                title: "淨利",
                value: net.asCurrency(defaultCurrency),
                tint: net >= 0 ? Theme.income : Theme.expense
            )
        }
    }

    private var incomeExpenseTile: some View {
        let income = project.totalIncome(in: defaultCurrency, fx: fx)
        let expenses = project.totalExpenses(in: defaultCurrency, fx: fx)
        return VStack(alignment: .leading, spacing: 0) {
            Text("收支狀況")
                .appFont(.caption, weight: .medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 2) {
                amountRow(icon: "arrow-circle-up", amount: expenses, tint: Theme.expense)
                amountRow(icon: "arrow-circle-down", amount: income, tint: Theme.income)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 76)
        .cardStyle(padding: 12)
    }

    private func amountRow(icon: String, amount: Double, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(ph: icon, weight: .fill)
                .frame(width: 6, height: 6)
                .foregroundStyle(tint)
            Text(amount.asCurrency(defaultCurrency))
                .appFont(.body, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    // MARK: - Editorial flat sections

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    private var monthlyTrendSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("月度趨勢")
                    .appFont(.title3, weight: .semibold)
                Spacer()
                NavigationLink {
                    ProjectAnalyticsView(project: project)
                } label: {
                    Text("查看分析")
                        .appFont(.footnote)
                        .foregroundStyle(Theme.brand)
                }
            }

            if monthlyData.isEmpty {
                emptyChartPlaceholder
            } else {
                Chart(monthlyData) { point in
                    BarMark(
                        x: .value("Month", point.month, unit: .month),
                        y: .value("Net", point.net)
                    )
                    .foregroundStyle(point.net >= 0 ? Theme.income : Theme.expense)
                    .cornerRadius(4)
                }
                .frame(height: 140)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private var recentEntriesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("收支紀錄")
                    .appFont(.title3, weight: .semibold)
                Spacer()
                NavigationLink {
                    TransactionsListView(project: project)
                } label: {
                    Text("See all")
                        .appFont(.footnote)
                        .foregroundStyle(Theme.brand)
                }
            }
            if recentTransactions.isEmpty {
                Text("No entries yet — tap + to log one.")
                    .appFont(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(recentTransactions) { txn in
                        TransactionRow(transaction: txn)
                            .padding(.vertical, 6)
                        if txn.id != recentTransactions.last?.id {
                            Rectangle()
                                .fill(Theme.primaryText.opacity(0.06))
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    // MARK: - Time Log section (Pro-gated)

    private var timeLogSection: some View {
        ZStack {
            timeLogContent
                .blur(radius: entitlements.isPro ? 0 : 6)
                .allowsHitTesting(entitlements.isPro)

            if !entitlements.isPro {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 6) {
                        Image(ph: "lock")
                            .frame(width: 12, height: 12)
                        Text("Pro")
                            .appFont(.caption, weight: .semibold)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timeLogContent: some View {
        NavigationLink {
            TimeCostView(project: project)
        } label: {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("時間成本")
                        .appFont(.title3, weight: .semibold)
                    Spacer()
                    Text("See all")
                        .appFont(.footnote)
                        .foregroundStyle(Theme.brand)
                }
                HStack(spacing: 20) {
                    timeStat(
                        title: "Total hours",
                        value: "\(Int(project.totalHours)) h"
                    )
                    Divider().frame(height: 28)
                    timeStat(
                        title: "Real hourly rate",
                        value: project.effectiveHourlyRate(in: defaultCurrency, fx: fx).asCompactCurrency(defaultCurrency) + "/h"
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .buttonStyle(.plain)
    }

    private func timeStat(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .appFont(.callout, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(Theme.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyChartPlaceholder: some View {
        Text("Add a few entries to see the monthly trend.")
            .appFont(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    // MARK: - Derived

    private var recentTransactions: [Transaction] {
        let all = project.transactions ?? []
        return all.sorted { $0.date > $1.date }.prefix(5).map { $0 }
    }

    private struct MonthlyPoint: Identifiable {
        let id = UUID()
        let month: Date
        let net: Double
    }

    private var monthlyData: [MonthlyPoint] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: (project.transactions ?? [])) { txn in
            cal.date(from: cal.dateComponents([.year, .month], from: txn.date)) ?? txn.date
        }
        return grouped
            .map { MonthlyPoint(month: $0.key, net: $0.value.reduce(0) { $0 + $1.signedConvertedAmount(to: defaultCurrency, fx: fx) }) }
            .sorted { $0.month < $1.month }
    }
}
