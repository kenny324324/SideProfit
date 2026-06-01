//
//  InsightsView.swift
//  DevCal
//
//  Cross-project portfolio view. This screen is for allocation decisions:
//  which projects are working, which are still burning cash, and where time is
//  going.
//

import SwiftUI
import SwiftData
import Charts
import PhosphorSymbols

struct InsightsView: View {
    @Environment(Entitlements.self) private var entitlements
    @Environment(ExchangeRateService.self) private var fx
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "USD"
    @Query(sort: [SortDescriptor(\Project.createdAt, order: .reverse)]) private var projects: [Project]
    @State private var showPaywall = false
    @State private var selectedRange: InsightsTimeRange = .all
    @State private var activeDrilldownSheet: InsightDrilldownSheet?

    var body: some View {
        Group {
            if projects.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to analyze yet", phImage: "chart-line-up")
                } description: {
                    Text("Create a project and log activity to see insights.")
                }
            } else if !entitlements.isPro {
                proGate
            } else {
                content
            }
        }
        .background(Theme.appBackground)
        .navigationTitle("洞察")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                rangeMenu
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(item: $activeDrilldownSheet) { sheet in
            drilldownSheet(sheet)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(true)
        }
    }

    private enum InsightsTimeRange: String, CaseIterable, Identifiable {
        case month
        case year
        case all

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .month: "本月"
            case .year: "本年"
            case .all: "全部"
            }
        }

        var netTitle: LocalizedStringKey {
            switch self {
            case .month: "本月總淨利"
            case .year: "本年總淨利"
            case .all: "累積總淨利"
            }
        }

        var incomeTitle: LocalizedStringKey {
            switch self {
            case .month: "本月總收入"
            case .year: "本年總收入"
            case .all: "累積總收入"
            }
        }

        var progressIncomeTitle: LocalizedStringKey {
            self == .all ? "累積收入" : "區間收入"
        }

        var progressExpenseTitle: LocalizedStringKey {
            self == .all ? "累積支出" : "區間支出"
        }

        var progressNetTitle: LocalizedStringKey {
            self == .all ? "累積淨利" : "區間淨利"
        }

        func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
            switch self {
            case .month:
                guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else {
                    return true
                }
                return date >= monthStart && date <= now
            case .year:
                guard let yearStart = calendar.date(from: calendar.dateComponents([.year], from: now)) else {
                    return true
                }
                return date >= yearStart && date <= now
            case .all:
                return date <= now
            }
        }
    }

    private enum PortfolioBreakdownMetric: String, Identifiable {
        case income
        case expense
        case net
        case breakeven

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .income: "專案收入明細"
            case .expense: "專案支出明細"
            case .net: "專案淨利明細"
            case .breakeven: "專案回本狀況"
            }
        }

        var primaryLabel: LocalizedStringKey {
            switch self {
            case .income: "收入"
            case .expense: "支出"
            case .net: "淨利"
            case .breakeven: "回本"
            }
        }
    }

    private enum InsightDrilldownSheet: Identifiable {
        case portfolio(PortfolioBreakdownMetric)
        case cost(TransactionCategory)

        var id: String {
            switch self {
            case .portfolio(let metric):
                return "portfolio-\(metric.rawValue)"
            case .cost(let category):
                return "cost-\(category.rawValue)"
            }
        }
    }

    private var rangeMenu: some View {
        Menu {
            ForEach(InsightsTimeRange.allCases) { range in
                Button {
                    selectedRange = range
                } label: {
                    Text(range.title)
                }
            }
        } label: {
            Text(selectedRange.title)
                .foregroundStyle(Theme.primaryText)
        }
    }

    // MARK: - Pro content

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                headlineGrid
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)

                sectionDivider
                netProfitRankingSection
                sectionDivider
                monthlyPerformanceSection
                sectionDivider
                cumulativeProgressSection
                sectionDivider
                costRankingSection
            }
            .padding(.bottom, 24)
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    // MARK: - Portfolio summary

    private var selectedTransactions: [Transaction] {
        projects
            .flatMap { $0.transactions ?? [] }
            .filter { selectedRange.contains($0.date) }
    }

    private var selectedTimeLogs: [TimeLog] {
        projects
            .flatMap { $0.timeLogs ?? [] }
            .filter { selectedRange.contains($0.date) }
    }

    private var selectedIncome: Double {
        selectedTransactions
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
    }

    private var selectedExpense: Double {
        selectedTransactions
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
    }

    private var selectedNet: Double {
        selectedIncome - selectedExpense
    }

    private var selectedHours: Double {
        selectedTimeLogs.reduce(0) { $0 + $1.hours }
    }

    private var portfolioHourlyRate: Double {
        guard selectedHours > 0 else { return 0 }
        return selectedNet / selectedHours
    }

    private var breakEvenCount: Int {
        projects.filter { $0.breakevenReachedAt != nil }.count
    }

    private var displayCurrency: String { defaultCurrency }

    /// Multi-currency is no longer a portfolio-wide flag — every transaction
    /// converts to displayCurrency individually, so aggregations are always
    /// safe. Kept as `false` to preserve the call sites without breaking them.
    private var usesMixedCurrencies: Bool { false }

    private func portfolioCurrency(_ value: Double) -> String {
        value.asCompactCurrency(displayCurrency)
    }

    private var headlineGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(
                title: selectedRange.netTitle,
                value: portfolioCurrency(selectedNet),
                tint: usesMixedCurrencies ? Theme.brand : (selectedNet >= 0 ? Theme.income : Theme.expense)
            )
            MetricTile(
                title: selectedRange.incomeTitle,
                value: portfolioCurrency(selectedIncome),
                tint: usesMixedCurrencies ? Theme.brand : Theme.income
            )
            MetricTile(
                title: "已回本",
                value: "\(breakEvenCount)/\(projects.count)",
                tint: Theme.income
            )
            MetricTile(
                title: "平均時薪",
                value: usesMixedCurrencies ? "多幣別" : portfolioHourlyRate.asCompactCurrency(displayCurrency) + "/h",
                tint: Theme.brand
            )
        }
    }

    // MARK: - Project performance table

    private struct ProjectPerformance: Identifiable {
        let project: Project
        let netProfit: Double

        var id: UUID { project.id }
    }

    private var performanceRows: [ProjectPerformance] {
        projects
            .map { project in
                ProjectPerformance(
                    project: project,
                    netProfit: netProfit(for: project)
                )
            }
            .sorted { lhs, rhs in
                if lhs.netProfit == rhs.netProfit {
                    let lhsAll = lhs.project.netProfit(in: defaultCurrency, fx: fx)
                    let rhsAll = rhs.project.netProfit(in: defaultCurrency, fx: fx)
                    if lhsAll == rhsAll {
                        return lhs.project.name.localizedStandardCompare(rhs.project.name) == .orderedAscending
                    }
                    return lhsAll > rhsAll
                }
                return lhs.netProfit > rhs.netProfit
            }
    }

    private var netProfitRankingSection: some View {
        let topRows = Array(performanceRows.prefix(5))

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("淨利排行榜")
                    .appFont(.title3, weight: .semibold)
                Spacer()
                if performanceRows.count > 5 {
                    NavigationLink {
                        NetProfitRankingDetailView(rows: performanceRows, currencyCode: defaultCurrency)
                    } label: {
                        Text("全部")
                        .appFont(.footnote, weight: .medium)
                        .foregroundStyle(Theme.brand)
                    }
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(topRows.enumerated()), id: \.element.id) { index, row in
                    NavigationLink {
                        ProjectDashboardView(project: row.project)
                    } label: {
                        netProfitRankingRow(row, rank: index + 1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if row.id != topRows.last?.id {
                        rowDivider
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private func netProfitRankingRow(_ row: ProjectPerformance, rank: Int) -> some View {
        let project = row.project
        return HStack(alignment: .center, spacing: 12) {
            Text("#\(rank)")
                .appFont(.callout, weight: .semibold)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 34, alignment: .leading)

            ProjectIconView(
                imageData: project.iconImageData,
                phName: project.iconPhName,
                kindFallback: project.kind,
                size: 24,
                colorHex: project.iconColorHex
            )

            Text(project.name)
                .appFont(.headline, weight: .semibold)
                .foregroundStyle(Theme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 16)

            Text(signedCurrency(row.netProfit, currencyCode: defaultCurrency))
                .appFont(.title3, weight: .semibold)
                .foregroundStyle(row.netProfit >= 0 ? Theme.income : Theme.expense)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: 140, alignment: .trailing)
        }
        .padding(.vertical, 16)
    }

    private struct NetProfitRankingDetailView: View {
        let rows: [ProjectPerformance]
        let currencyCode: String

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        NavigationLink {
                            ProjectDashboardView(project: row.project)
                        } label: {
                            rowView(row, rank: index + 1)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if row.id != rows.last?.id {
                            rowDivider
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Theme.appBackground)
            .navigationTitle("淨利排行榜")
            .toolbarTitleDisplayMode(.inline)
        }

        private func rowView(_ row: ProjectPerformance, rank: Int) -> some View {
            let project = row.project
            return HStack(alignment: .center, spacing: 12) {
                Text("#\(rank)")
                    .appFont(.callout, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .leading)

                ProjectIconView(
                    imageData: project.iconImageData,
                    phName: project.iconPhName,
                    kindFallback: project.kind,
                    size: 24,
                    colorHex: project.iconColorHex
                )

                Text(project.name)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 16)

                Text(signedCurrency(row.netProfit, currencyCode: currencyCode))
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(row.netProfit >= 0 ? Theme.income : Theme.expense)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            .padding(.vertical, 16)
        }

        private var rowDivider: some View {
            Rectangle()
                .fill(Theme.primaryText.opacity(0.06))
                .frame(height: 0.5)
        }

        private func signedCurrency(_ value: Double, currencyCode: String) -> String {
            let prefix = value > 0 ? "+" : ""
            return prefix + value.asCompactCurrency(currencyCode)
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.06))
            .frame(height: 0.5)
    }

    private func signedCurrency(_ value: Double, currencyCode: String) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + value.asCompactCurrency(currencyCode)
    }

    private func netProfit(for project: Project) -> Double {
        projectNet(for: project)
    }

    private func selectedTransactions(for project: Project) -> [Transaction] {
        (project.transactions ?? [])
            .filter { selectedRange.contains($0.date) }
    }

    private func projectIncome(for project: Project) -> Double {
        selectedTransactions(for: project)
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
    }

    private func projectExpense(for project: Project) -> Double {
        selectedTransactions(for: project)
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
    }

    private func projectNet(for project: Project) -> Double {
        selectedTransactions(for: project)
            .reduce(0) { $0 + $1.signedConvertedAmount(to: defaultCurrency, fx: fx) }
    }

    // MARK: - Monthly performance

    private struct MonthlyRow: Identifiable {
        let month: Date
        let income: Double
        let expense: Double
        let net: Double

        var id: Date { month }
    }

    private struct MonthlyBar: Identifiable {
        let month: Date
        let kind: String
        let amount: Double

        var id: String { "\(month.timeIntervalSince1970)-\(kind)" }
    }

    private var monthlyRows: [MonthlyRow] {
        let cal = Calendar.current
        let groupedByMonth = Dictionary(grouping: selectedTransactions) { txn in
            cal.date(from: cal.dateComponents([.year, .month], from: txn.date)) ?? txn.date
        }

        return groupedByMonth.keys.sorted().map { month in
            let transactions = groupedByMonth[month] ?? []
            let income = transactions
                .filter { $0.type == .income }
                .reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
            let expense = transactions
                .filter { $0.type == .expense }
                .reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
            return MonthlyRow(
                month: month,
                income: income,
                expense: expense,
                net: income - expense
            )
        }
    }

    private var monthlyRowsDescending: [MonthlyRow] {
        monthlyRows.sorted { $0.month > $1.month }
    }

    private var monthlyBars: [MonthlyBar] {
        monthlyRows.flatMap { row in
            [
                MonthlyBar(month: row.month, kind: "收入", amount: row.income),
                MonthlyBar(month: row.month, kind: "支出", amount: row.expense)
            ]
        }
    }

    private var monthlyPerformanceSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("月度表現")
                .appFont(.title3, weight: .semibold)

            if monthlyRows.isEmpty {
                emptyState("目前區間還沒有收入或支出紀錄。")
            } else {
                Chart(monthlyBars) { bar in
                    BarMark(
                        x: .value("Month", bar.month, unit: .month),
                        y: .value("Amount", bar.amount)
                    )
                    .foregroundStyle(by: .value("Kind", bar.kind))
                    .position(by: .value("Kind", bar.kind))
                }
                .chartForegroundStyleScale([
                    "收入": Theme.income,
                    "支出": Theme.expense
                ])
                .chartLegend(position: .bottom, alignment: .center)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month)) { _ in
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    }
                }
                .frame(height: 220)

                monthlyDetailTable
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private var monthlyDetailTable: some View {
        let rows = Array(monthlyRowsDescending.prefix(12))

        return VStack(alignment: .leading, spacing: 12) {
            Text("月度明細")
                .appFont(.title3, weight: .semibold)

            VStack(spacing: 0) {
                monthlyHeaderRow
                ForEach(rows) { row in
                    monthlyDataRow(row)
                    if row.id != rows.last?.id {
                        rowDivider
                    }
                }
            }
        }
    }

    private var monthlyHeaderRow: some View {
        HStack(spacing: 8) {
            tableHeader("月份", width: 56, alignment: .leading)
            tableHeader("收入", alignment: .trailing)
            tableHeader("支出", alignment: .trailing)
            tableHeader("淨利", alignment: .trailing)
            tableHeader("狀態", width: 48, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private func monthlyDataRow(_ row: MonthlyRow) -> some View {
        let status = monthStatus(for: row.net)
        return HStack(spacing: 8) {
            Text(row.month, format: .dateTime.month(.abbreviated))
                .appFont(.callout)
                .foregroundStyle(Theme.primaryText)
                .frame(width: 56, alignment: .leading)
            Text(portfolioCurrency(row.income))
                .appFont(.callout, weight: .medium)
                .foregroundStyle(Theme.income)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(portfolioCurrency(row.expense))
                .appFont(.callout, weight: .medium)
                .foregroundStyle(Theme.expense)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(portfolioCurrency(row.net))
                .appFont(.callout, weight: .semibold)
                .foregroundStyle(row.net >= 0 ? Theme.income : Theme.expense)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(status.label)
                .appFont(.callout, weight: .medium)
                .foregroundStyle(status.tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }

    private func monthStatus(for net: Double) -> (label: LocalizedStringKey, tint: Color) {
        if net > 0 {
            return ("獲利", Theme.income)
        } else if net < 0 {
            return ("虧損", Theme.expense)
        } else {
            return ("打平", .secondary)
        }
    }

    // MARK: - Cumulative progress

    private struct CumulativePoint: Identifiable {
        let id = UUID()
        let date: Date
        let cumulativeIncome: Double
    }

    private var cumulativeData: [CumulativePoint] {
        // Bucket per day so multiple same-day transactions collapse into a
        // single (x, y) point. Otherwise AreaMark gets two y values for the
        // same x and renders a tall spike where the vertical jump happens.
        let cal = Calendar.current
        let dailyTotals = Dictionary(grouping: selectedTransactions.filter { $0.type == .income }) { txn in
            cal.startOfDay(for: txn.date)
        }
        .map { (day, txns) in
            (day: day, amount: txns.reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) })
        }
        .sorted { $0.day < $1.day }

        var running: Double = 0
        return dailyTotals.map { item in
            running += item.amount
            return CumulativePoint(date: item.day, cumulativeIncome: running)
        }
    }

    private var referenceTarget: (value: Double, label: LocalizedStringKey)? {
        guard selectedExpense > 0 else { return nil }
        return (selectedExpense, "回本線")
    }

    private var remainingAmount: Double {
        max(0, selectedExpense - selectedIncome)
    }

    private var cumulativeProgressSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("累積進度")
                .appFont(.title3, weight: .semibold)

            progressGrid

            if cumulativeData.isEmpty {
                emptyState("目前區間還沒有收入紀錄。")
            } else {
                VStack(spacing: 8) {
                    Chart {
                        ForEach(cumulativeData) { point in
                            AreaMark(
                                x: .value("Date", point.date),
                                y: .value("Revenue", point.cumulativeIncome)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(lineAreaGradient)

                            LineMark(
                                x: .value("Date", point.date),
                                y: .value("Revenue", point.cumulativeIncome)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(Theme.income)
                        }

                        if let target = referenceTarget {
                            RuleMark(y: .value("Target", target.value))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .foregroundStyle(Theme.expense)
                        }
                    }
                    .frame(height: 200)

                    if let target = referenceTarget {
                        referenceTargetLegend(target.label)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    /// Shading under the cumulative line — picks up the line color and fades
    /// to transparent toward the x-axis for a soft glow.
    private var lineAreaGradient: LinearGradient {
        LinearGradient(
            colors: [Theme.income.opacity(0.35), Theme.income.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var progressGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            progressMetricTile(
                .income,
                title: selectedRange.progressIncomeTitle,
                value: portfolioCurrency(selectedIncome),
                tint: usesMixedCurrencies ? Theme.brand : Theme.income
            )
            progressMetricTile(
                .expense,
                title: selectedRange.progressExpenseTitle,
                value: portfolioCurrency(selectedExpense),
                tint: usesMixedCurrencies ? Theme.brand : Theme.expense
            )
            progressMetricTile(
                .net,
                title: selectedRange.progressNetTitle,
                value: portfolioCurrency(selectedNet),
                tint: usesMixedCurrencies ? Theme.brand : (selectedNet >= 0 ? Theme.income : Theme.expense)
            )
            progressMetricTile(
                .breakeven,
                title: "距離回本",
                value: portfolioCurrency(remainingAmount),
                tint: remainingAmount == 0 ? Theme.income : Theme.brand
            )
        }
    }

    private func progressMetricTile(
        _ metric: PortfolioBreakdownMetric,
        title: LocalizedStringKey,
        value: String,
        tint: Color
    ) -> some View {
        Button {
            activeDrilldownSheet = .portfolio(metric)
        } label: {
            MetricTile(title: title, value: value, tint: tint)
        }
        .buttonStyle(.plain)
    }

    private func referenceTargetLegend(_ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 3))
                path.addLine(to: CGPoint(x: 28, y: 3))
            }
            .stroke(Theme.expense, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .frame(width: 28, height: 6)

            Text(label)
                .appFont(.caption, weight: .medium)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Drilldown sheets

    private struct PortfolioProjectBreakdownRow: Identifiable {
        let project: Project
        let income: Double
        let expense: Double
        let net: Double
        let isBreakeven: Bool
        let remaining: Double

        var id: UUID { project.id }
    }

    private struct CostProjectBreakdownRow: Identifiable {
        let project: Project
        let amount: Double

        var id: UUID { project.id }
    }

    @ViewBuilder
    private func drilldownSheet(_ sheet: InsightDrilldownSheet) -> some View {
        switch sheet {
        case .portfolio(let metric):
            PortfolioBreakdownSheet(
                metric: metric,
                rows: portfolioBreakdownRows(sortedBy: metric),
                currencyCode: defaultCurrency
            )
        case .cost(let category):
            CostCategoryBreakdownSheet(
                category: category,
                rows: costProjectRows(for: category),
                currencyCode: defaultCurrency
            )
        }
    }

    private func portfolioBreakdownRows(sortedBy metric: PortfolioBreakdownMetric) -> [PortfolioProjectBreakdownRow] {
        let rows = projects.map { project in
            let income = projectIncome(for: project)
            let expense = projectExpense(for: project)
            let projectTotalExpense = project.totalExpenses(in: defaultCurrency, fx: fx)
            let projectTotalIncome = project.totalIncome(in: defaultCurrency, fx: fx)
            let isBreakeven = project.breakevenReachedAt != nil
                || (projectTotalExpense > 0 && projectTotalIncome >= projectTotalExpense)
            return PortfolioProjectBreakdownRow(
                project: project,
                income: income,
                expense: expense,
                net: income - expense,
                isBreakeven: isBreakeven,
                remaining: max(0, expense - income)
            )
        }

        return rows.sorted { lhs, rhs in
            switch metric {
            case .income:
                return sortProjects(lhs, rhs, lhsValue: lhs.income, rhsValue: rhs.income)
            case .expense:
                return sortProjects(lhs, rhs, lhsValue: lhs.expense, rhsValue: rhs.expense)
            case .net:
                return sortProjects(lhs, rhs, lhsValue: lhs.net, rhsValue: rhs.net)
            case .breakeven:
                if lhs.isBreakeven != rhs.isBreakeven {
                    return lhs.isBreakeven
                }
                if lhs.remaining != rhs.remaining {
                    return lhs.remaining < rhs.remaining
                }
                return sortProjects(lhs, rhs, lhsValue: lhs.net, rhsValue: rhs.net)
            }
        }
    }

    private func sortProjects(
        _ lhs: PortfolioProjectBreakdownRow,
        _ rhs: PortfolioProjectBreakdownRow,
        lhsValue: Double,
        rhsValue: Double
    ) -> Bool {
        if lhsValue == rhsValue {
            return lhs.project.name.localizedStandardCompare(rhs.project.name) == .orderedAscending
        }
        return lhsValue > rhsValue
    }

    private func costProjectRows(for category: TransactionCategory) -> [CostProjectBreakdownRow] {
        projects.compactMap { project in
            let amount = selectedTransactions(for: project)
                .filter { $0.type == .expense && $0.category == category }
                .reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
            guard amount > 0 else { return nil }
            return CostProjectBreakdownRow(project: project, amount: amount)
        }
        .sorted { lhs, rhs in
            if lhs.amount == rhs.amount {
                return lhs.project.name.localizedStandardCompare(rhs.project.name) == .orderedAscending
            }
            return lhs.amount > rhs.amount
        }
    }

    private struct PortfolioBreakdownSheet: View {
        @Environment(\.dismiss) private var dismiss

        let metric: PortfolioBreakdownMetric
        let rows: [PortfolioProjectBreakdownRow]
        let currencyCode: String

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            NavigationLink {
                                ProjectDashboardView(project: row.project)
                            } label: {
                                rowView(row, rank: index + 1)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if row.id != rows.last?.id {
                                rowDivider
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .background(Theme.appBackground)
                .navigationTitle(metric.title)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        private func rowView(_ row: PortfolioProjectBreakdownRow, rank: Int) -> some View {
            HStack(alignment: .center, spacing: 12) {
                Text("#\(rank)")
                    .appFont(.callout, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .leading)

                ProjectIconView(
                    imageData: row.project.iconImageData,
                    phName: row.project.iconPhName,
                    kindFallback: row.project.kind,
                    size: 24,
                    colorHex: row.project.iconColorHex
                )

                Text(row.project.name)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 16)

                Text(primaryText(for: row))
                    .appFont(.title3, weight: .semibold)
                    .foregroundStyle(primaryTint(for: row))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            .padding(.vertical, 16)
        }

        private func primaryText(for row: PortfolioProjectBreakdownRow) -> String {
            switch metric {
            case .income:
                return row.income.asCompactCurrency(currencyCode)
            case .expense:
                return row.expense.asCompactCurrency(currencyCode)
            case .net:
                return signedCurrency(row.net, currencyCode: currencyCode)
            case .breakeven:
                if row.isBreakeven {
                    return String(localized: "已回本")
                }
                return String(localized: "差 \(row.remaining.asCompactCurrency(currencyCode))")
            }
        }

        private func primaryTint(for row: PortfolioProjectBreakdownRow) -> Color {
            switch metric {
            case .income:
                return Theme.income
            case .expense:
                return Theme.expense
            case .net:
                return row.net >= 0 ? Theme.income : Theme.expense
            case .breakeven:
                return row.isBreakeven ? Theme.income : Theme.expense
            }
        }

        private func signedCurrency(_ value: Double, currencyCode: String) -> String {
            let prefix = value > 0 ? "+" : ""
            return prefix + value.asCompactCurrency(currencyCode)
        }

        private var rowDivider: some View {
            Rectangle()
                .fill(Theme.primaryText.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private struct CostCategoryBreakdownSheet: View {
        @Environment(\.dismiss) private var dismiss

        let category: TransactionCategory
        let rows: [CostProjectBreakdownRow]
        let currencyCode: String

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 0) {
                        if rows.isEmpty {
                            Text("目前沒有專案使用這個成本。")
                                .appFont(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 160)
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                NavigationLink {
                                    ProjectDashboardView(project: row.project)
                                } label: {
                                    rowView(row, rank: index + 1)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if row.id != rows.last?.id {
                                    rowDivider
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
                .background(Theme.appBackground)
                .navigationTitle(category.displayName)
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        private func rowView(_ row: CostProjectBreakdownRow, rank: Int) -> some View {
            HStack(spacing: 12) {
                Text("#\(rank)")
                    .appFont(.callout, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .leading)

                ProjectIconView(
                    imageData: row.project.iconImageData,
                    phName: row.project.iconPhName,
                    kindFallback: row.project.kind,
                    size: 24,
                    colorHex: row.project.iconColorHex
                )

                Text(row.project.name)
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(row.amount.asCompactCurrency(currencyCode))
                    .appFont(.headline, weight: .semibold)
                    .foregroundStyle(Theme.expense)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .padding(.vertical, 16)
        }

        private var rowDivider: some View {
            Rectangle()
                .fill(Theme.primaryText.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    // MARK: - Cost ranking

    private struct CostRow: Identifiable {
        let category: TransactionCategory
        let amount: Double
        let share: Double

        var id: TransactionCategory { category }
    }

    private var costRows: [CostRow] {
        let expenses = selectedTransactions.filter { $0.type == .expense }
        let total = expenses.reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
        guard total > 0 else { return [] }

        let grouped = Dictionary(grouping: expenses) { $0.category }
        return grouped
            .map { category, transactions in
                let amount = transactions.reduce(0) { $0 + $1.convertedAmount(to: defaultCurrency, fx: fx) }
                return CostRow(category: category, amount: amount, share: amount / total)
            }
            .sorted { $0.amount > $1.amount }
    }

    private var costRankingSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("成本排行")
                    .appFont(.title3, weight: .semibold)
                Spacer()
                if !costRows.isEmpty {
                    NavigationLink {
                        CostRankingDetailView(
                            rows: costRows,
                            currencyCode: displayCurrency,
                            projectRowsProvider: { category in costProjectRows(for: category) }
                        )
                    } label: {
                        Text("全部")
                        .appFont(.footnote, weight: .medium)
                        .foregroundStyle(Theme.primaryText)
                    }
                }
            }

            if costRows.isEmpty {
                emptyState("目前區間還沒有支出紀錄。")
            } else {
                let rows = Array(costRows.prefix(5))
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            activeDrilldownSheet = .cost(row.category)
                        } label: {
                            CostRankingRowView(
                                row: row,
                                amountText: portfolioCurrency(row.amount)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if row.id != rows.last?.id {
                            rowDivider
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private struct CostRankingDetailView: View {
        let rows: [CostRow]
        let currencyCode: String
        let projectRowsProvider: (TransactionCategory) -> [CostProjectBreakdownRow]

        @State private var activeCategory: TransactionCategory?

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button {
                            activeCategory = row.category
                        } label: {
                            CostRankingRowView(
                                row: row,
                                amountText: amountText(row.amount)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if row.id != rows.last?.id {
                            rowDivider
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Theme.appBackground)
            .navigationTitle("成本排行")
            .toolbarTitleDisplayMode(.inline)
            .sheet(item: $activeCategory) { category in
                CostCategoryBreakdownSheet(
                    category: category,
                    rows: projectRowsProvider(category),
                    currencyCode: currencyCode
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled(true)
            }
        }

        private func amountText(_ value: Double) -> String {
            value.asCompactCurrency(currencyCode)
        }

        private var rowDivider: some View {
            Rectangle()
                .fill(Theme.primaryText.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private struct CostRankingRowView: View {
        let row: CostRow
        let amountText: String

        var body: some View {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    costIcon(for: row.category)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text(row.category.displayName)
                        .appFont(.subheadline, weight: .medium)
                    Spacer()
                    Text(amountText)
                        .appFont(.callout, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.expense)
                }

                HStack(spacing: 10) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.primaryText.opacity(0.08))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.expense)
                                .frame(width: geo.size.width * row.share)
                        }
                    }
                    .frame(height: 6)

                    Text(row.share.formatted(.percent.precision(.fractionLength(0))))
                        .appFont(.caption2, weight: .medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 38, alignment: .trailing)
                }
            }
            .padding(.vertical, 10)
        }

        @ViewBuilder
        private func costIcon(for category: TransactionCategory) -> some View {
            switch category {
            case .appStoreFee:
                BrandIconRegistry.image(for: "apple")
            case .googlePlayFee:
                BrandIconRegistry.image(for: "google")
            case .aiTools:
                BrandIconRegistry.image(for: "openai")
            default:
                phosphorIcon(category.costRankingPhosphorName)
            }
        }

        private func phosphorIcon(_ name: String) -> some View {
            Image(ph: name)
                .resizable()
                .scaledToFit()
                .padding(2)
        }
    }

    // MARK: - Shared pieces

    private func tableHeader(
        _ text: LocalizedStringKey,
        width: CGFloat? = nil,
        alignment: Alignment
    ) -> some View {
        Text(text)
            .appFont(.footnote, weight: .medium)
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }

    private func emptyState(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .appFont(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 100)
    }

    // MARK: - Pro gate

    private var proGate: some View {
        ContentUnavailableView {
            Label("跨專案洞察是 Pro 功能", phImage: "chart-line-up")
        } description: {
            Text("See cross-project performance, hours invested, and your effective hourly rate.")
        } actions: {
            Button("Upgrade to Pro") { showPaywall = true }
                .buttonStyle(.swPrimary)
        }
    }
}

private extension TransactionCategory {
    var costRankingPhosphorName: String {
        switch self {
        case .appSales:
            return "device-mobile"
        case .subscriptions:
            return "arrows-clockwise"
        case .adRevenue:
            return "megaphone"
        case .sponsorship:
            return "heart"
        case .otherIncome:
            return "plus-circle"
        case .server:
            return "hard-drives"
        case .api:
            return "network"
        case .appStoreFee:
            return "app-store-logo"
        case .googlePlayFee:
            return "google-play-logo"
        case .domain:
            return "globe"
        case .design:
            return "paint-brush"
        case .advertising:
            return "speaker-high"
        case .outsourcing:
            return "users"
        case .software:
            return "app-window"
        case .aiTools:
            return "hexagon"
        case .testingDevices:
            return "devices"
        case .devTools:
            return "wrench"
        case .otherExpense:
            return "dots-three-circle"
        }
    }
}
