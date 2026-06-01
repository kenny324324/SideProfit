//
//  ProjectAnalyticsView.swift
//  DevCal
//
//  Per-project analytics: monthly performance, cumulative progress, and
//  ranked costs. Kept table-first so this screen explains why a project is
//  improving or slipping instead of repeating the dashboard summary.
//

import SwiftUI
import SwiftData
import Charts
import PhosphorSymbols

struct ProjectAnalyticsView: View {
    let project: Project
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "USD"
    @Environment(ExchangeRateService.self) private var fx

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                monthlyPerformanceSection
                sectionDivider
                cumulativeProgressSection
                sectionDivider
                costRankingSection
            }
            .padding(.bottom, 24)
        }
        .background(Theme.appBackground)
        .navigationTitle("專案分析")
        .toolbarTitleDisplayMode(.inline)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
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
        let groupedByMonth = Dictionary(grouping: (project.transactions ?? [])) { txn in
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
            let net = income - expense
            return MonthlyRow(
                month: month,
                income: income,
                expense: expense,
                net: net
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
                emptyState("記下幾筆收入或支出後，就能看到每月表現。")
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
        VStack(alignment: .leading, spacing: 12) {
            Text("月度明細")
                .appFont(.title3, weight: .semibold)

            VStack(spacing: 0) {
                monthlyHeaderRow
                ForEach(Array(monthlyRowsDescending.prefix(12))) { row in
                    monthlyDataRow(row)
                    if row.id != Array(monthlyRowsDescending.prefix(12)).last?.id {
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
            Text(row.income.asCompactCurrency(defaultCurrency))
                .appFont(.callout, weight: .medium)
                .foregroundStyle(Theme.income)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.expense.asCompactCurrency(defaultCurrency))
                .appFont(.callout, weight: .medium)
                .foregroundStyle(Theme.expense)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.net.asCompactCurrency(defaultCurrency))
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
        let date: Date
        let cumulativeIncome: Double

        var id: Date { date }
    }

    private var cumulativeData: [CumulativePoint] {
        // Bucket per day so multiple same-day transactions collapse into a
        // single (x, y) point. Otherwise AreaMark gets two y values for the
        // same x and renders a tall spike where the vertical jump happens.
        let cal = Calendar.current
        let dailyTotals = Dictionary(grouping: (project.transactions ?? []).filter { $0.type == .income }) { txn in
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
        switch project.stage {
        case .stageOne, .justReached:
            let exp = project.totalExpenses(in: defaultCurrency, fx: fx)
            guard exp > 0 else { return nil }
            return (exp, "回本線")
        case .stageTwo:
            guard let goal = project.goalAmount, goal > 0 else { return nil }
            let converted = fx.convert(goal, from: project.goalCurrencyCode ?? defaultCurrency, to: defaultCurrency) ?? goal
            return (converted, "目標")
        }
    }

    private var remainingAmount: Double {
        let income = project.totalIncome(in: defaultCurrency, fx: fx)
        switch project.stage {
        case .stageOne, .justReached:
            return max(0, project.totalExpenses(in: defaultCurrency, fx: fx) - income)
        case .stageTwo:
            guard let goal = project.goalAmount else { return 0 }
            let converted = fx.convert(goal, from: project.goalCurrencyCode ?? defaultCurrency, to: defaultCurrency) ?? goal
            return max(0, converted - income)
        }
    }

    private var remainingTitle: LocalizedStringKey {
        switch project.stage {
        case .stageOne, .justReached: return "距離回本"
        case .stageTwo: return "距離目標"
        }
    }

    private var cumulativeProgressSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("累積進度")
                .appFont(.title3, weight: .semibold)

            progressGrid

            if cumulativeData.isEmpty {
                emptyState("記下第一筆收入後，就能追蹤累積收入。")
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

    private var progressGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let income = project.totalIncome(in: defaultCurrency, fx: fx)
        let expenses = project.totalExpenses(in: defaultCurrency, fx: fx)
        let net = project.netProfit(in: defaultCurrency, fx: fx)
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(
                title: "累積收入",
                value: income.asCompactCurrency(defaultCurrency),
                tint: Theme.income
            )
            MetricTile(
                title: "累積支出",
                value: expenses.asCompactCurrency(defaultCurrency),
                tint: Theme.expense
            )
            MetricTile(
                title: "累積淨利",
                value: net.asCompactCurrency(defaultCurrency),
                tint: net >= 0 ? Theme.income : Theme.expense
            )
            MetricTile(
                title: remainingTitle,
                value: remainingAmount.asCompactCurrency(defaultCurrency),
                tint: remainingAmount == 0 ? Theme.income : Theme.brand
            )
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
        let expenses = (project.transactions ?? []).filter { $0.type == .expense }
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
                        CostRankingDetailView(project: project, rows: costRows, currencyCode: defaultCurrency)
                    } label: {
                        Text("全部")
                            .appFont(.footnote)
                            .foregroundStyle(Theme.brand)
                    }
                }
            }

            if costRows.isEmpty {
                emptyState("還沒有支出紀錄。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(costRows.prefix(5))) { row in
                        CostRankingRowView(row: row, currencyCode: defaultCurrency)
                        if row.id != Array(costRows.prefix(5)).last?.id {
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
        let project: Project
        let rows: [CostRow]
        let currencyCode: String

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        CostRankingRowView(row: row, currencyCode: currencyCode)
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
        }

        private var rowDivider: some View {
            Rectangle()
                .fill(Theme.primaryText.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    private struct CostRankingRowView: View {
        let row: CostRow
        let currencyCode: String

        var body: some View {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    costIcon(for: row.category)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                    Text(row.category.displayName)
                        .appFont(.subheadline, weight: .medium)
                    Spacer()
                    Text(row.amount.asCompactCurrency(currencyCode))
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

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.06))
            .frame(height: 0.5)
    }

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
