//
//  SeedData.swift
//  DevCal
//
//  Populates demo projects + transactions + time logs on first launch so the UI has
//  realistic data covering all three two-stage progress states (Stage 1 / justReached
//  celebration / Stage 2). Skips if any Project already exists in the store.
//

import Foundation
import SwiftData

enum SeedData {

    @MainActor
    static func seedIfEmpty(_ context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<Project>())
        guard (existing?.isEmpty ?? true) else { return }

        let now = Date()
        let calendar = Calendar.current

        // All seed data uses TWD originals — matches the default display
        // currency and avoids needing FX during initial render. Users can
        // change display currency in Settings after first launch.
        let seedCurrency = "TWD"

        // Stage 2 — already past break-even, with a goal + deadline set.
        let shipSwift = Project(
            name: "快艇工具",
            description: "Swift 元件庫，讓 indie dev 加速出貨",
            status: .live,
            kind: .template,
            launchDate: calendar.date(byAdding: .month, value: -8, to: now),
            breakevenReachedAt: calendar.date(byAdding: .month, value: -3, to: now),
            goalAmount: 500_000,
            goalCurrencyCode: seedCurrency,
            goalDeadline: calendar.date(byAdding: .month, value: 6, to: now)
        )

        // justReached — income just caught up to expenses, no goal set yet.
        let devCal = Project(
            name: "開發日曆",
            description: "Indie 開發者的回本追蹤器",
            status: .live,
            launchDate: calendar.date(byAdding: .month, value: -2, to: now),
        )

        // Stage 1 — mid progress (~30%, never crosses break-even).
        let pixelTimer = Project(
            name: "像素番茄",
            description: "像素獎勵的番茄鐘 App",
            status: .live,
            launchDate: calendar.date(byAdding: .month, value: -4, to: now),
        )

        // Stage 1 — early stage, heavy expenses, small revenue.
        let dietJournal = Project(
            name: "飲食手帳",
            description: "給健身教練用的 AI 飲食紀錄",
            status: .building,
            launchDate: calendar.date(byAdding: .month, value: -1, to: now),
        )

        // Stage 1 — planning, only a few expenses, no revenue.
        let indieMap = Project(
            name: "獨立地圖",
            description: "發現你附近的 indie iOS App",
            status: .planned,
            launchDate: nil,
        )

        // Lower sortIndex = closer to the top.
        shipSwift.sortIndex = 0
        devCal.sortIndex = 1
        pixelTimer.sortIndex = 2
        dietJournal.sortIndex = 3
        indieMap.sortIndex = 4

        let projects = [shipSwift, devCal, pixelTimer, dietJournal, indieMap]
        projects.forEach(context.insert)

        // ShipSwift — 8 months of activity; healthy revenue exceeds expenses.
        seedTransactions(
            for: shipSwift,
            into: context,
            calendar: calendar,
            now: now,
            monthsBack: 8,
            entriesPerMonth: 7,
            incomeRange: 3_000...12_000,
            expenseRange: 400...2_500,
            incomeShare: 0.6,
            currency: seedCurrency
        )
        seedTimeLogs(
            for: shipSwift,
            into: context,
            calendar: calendar,
            now: now,
            entries: 30,
            hourlyRate: 600,
            currency: seedCurrency
        )

        // DevCal — 2 months, income just caught up to expenses.
        seedTransactions(
            for: devCal,
            into: context,
            calendar: calendar,
            now: now,
            monthsBack: 2,
            entriesPerMonth: 5,
            incomeRange: 1_500...4_000,
            expenseRange: 500...2_000,
            incomeShare: 0.5,
            currency: seedCurrency
        )
        seedTimeLogs(
            for: devCal,
            into: context,
            calendar: calendar,
            now: now,
            entries: 12,
            hourlyRate: 500,
            currency: seedCurrency
        )

        // PixelTimer — 4 months, mid Stage 1 (~30%); ranges chosen so worst-case
        // income (9 × 1500 = 13_500) stays below best-case expense (21 × 700 =
        // 14_700), guaranteeing it never accidentally hits break-even.
        seedTransactions(
            for: pixelTimer,
            into: context,
            calendar: calendar,
            now: now,
            monthsBack: 4,
            entriesPerMonth: 6,
            incomeRange: 400...1_500,
            expenseRange: 700...2_000,
            incomeShare: 0.3,
            currency: seedCurrency
        )
        seedTimeLogs(
            for: pixelTimer,
            into: context,
            calendar: calendar,
            now: now,
            entries: 14,
            hourlyRate: 400,
            currency: seedCurrency
        )

        // DietJournal — 1 month, early stage, heavy expenses, tiny income.
        seedTransactions(
            for: dietJournal,
            into: context,
            calendar: calendar,
            now: now,
            monthsBack: 1,
            entriesPerMonth: 5,
            incomeRange: 200...1_200,
            expenseRange: 600...4_500,
            incomeShare: 0.2,
            currency: seedCurrency
        )
        seedTimeLogs(
            for: dietJournal,
            into: context,
            calendar: calendar,
            now: now,
            entries: 10,
            hourlyRate: 500,
            currency: seedCurrency
        )

        // IndieMap — planning, only expenses.
        seedTransactions(
            for: indieMap,
            into: context,
            calendar: calendar,
            now: now,
            monthsBack: 1,
            entriesPerMonth: 2,
            incomeRange: 0...0,
            expenseRange: 200...900,
            incomeShare: 0,
            currency: seedCurrency
        )

        // Stamp break-even on any seeded project that genuinely qualifies via its
        // transactions. (ShipSwift already has it stamped to a fixed historical date,
        // which we want to preserve — so only stamp if not already set.)
        // Seed data is single-currency, so we use seedCurrency as the display
        // code and pass the shared FX service.
        let fx = ExchangeRateService.shared
        for project in projects {
            project.stampBreakevenIfReached(in: seedCurrency, fx: fx, triggerDate: now)
        }

        try? context.save()
    }

    // MARK: - Helpers

    private static func seedTransactions(
        for project: Project,
        into context: ModelContext,
        calendar: Calendar,
        now: Date,
        monthsBack: Int,
        entriesPerMonth: Int,
        incomeRange: ClosedRange<Double>,
        expenseRange: ClosedRange<Double>,
        incomeShare: Double,
        currency: String
    ) {
        let incomeCats: [TransactionCategory] = [.appSales, .subscriptions, .adRevenue]
        let expenseCats: [TransactionCategory] = [.server, .api, .appStoreFee, .domain, .design, .software, .aiTools, .devTools]

        for monthOffset in 0...monthsBack {
            guard let monthStart = calendar.date(byAdding: .month, value: -monthOffset, to: now) else { continue }
            for _ in 0..<entriesPerMonth {
                let dayOffset = Int.random(in: 0...27)
                let date = calendar.date(byAdding: .day, value: -dayOffset, to: monthStart) ?? monthStart
                let isIncome = Double.random(in: 0...1) < incomeShare
                let cat = isIncome ? incomeCats.randomElement()! : expenseCats.randomElement()!
                let (txName, brand) = seedNameAndBrand(for: cat)
                let txn = Transaction(
                    type: isIncome ? .income : .expense,
                    category: cat,
                    name: txName,
                    iconBrandKey: brand,
                    iconFallbackName: nil,
                    iconColorHex: nil,
                    originalAmount: Double.random(in: isIncome ? incomeRange : expenseRange).rounded(),
                    originalCurrencyCode: currency,
                    note: "",
                    date: date,
                    project: project
                )
                context.insert(txn)
            }
        }
    }

    /// Pick a plausible display name + brand icon key for each category so
    /// the seeded dashboard looks lived-in instead of full of repeated
    ///「AI Tools」rows.
    private static func seedNameAndBrand(for cat: TransactionCategory) -> (String, String?) {
        switch cat {
        case .appSales:        return ("App Store 銷售", "apple")
        case .subscriptions:   return (["Stripe 訂閱", "Lemon Squeezy", "Paddle"].randomElement()!, "stripe")
        case .adRevenue:       return ("廣告分潤", "admob")
        case .server:          return (["AWS EC2", "DigitalOcean Droplet", "Vercel"].randomElement()!, ["aws", "digitalocean", "vercel"].randomElement())
        case .api:             return (["Resend", "Algolia", "Mapbox"].randomElement()!, ["resend", "algolia", "mapbox"].randomElement())
        case .appStoreFee:     return ("Apple 平台抽成", "apple")
        case .domain:          return ("Namecheap 網域", "namecheap")
        case .design:          return ("Figma", "figma")
        case .software:        return (["Notion", "Linear", "Raycast"].randomElement()!, ["notion", "linear", "raycast"].randomElement())
        case .aiTools:         return (["ChatGPT Plus", "Claude Pro", "Cursor"].randomElement()!, ["openai", "claude", "cursor"].randomElement())
        case .devTools:        return (["GitHub", "Sentry", "RevenueCat"].randomElement()!, ["github", "sentry", "revenuecat"].randomElement())
        default:               return ("", nil)
        }
    }

    private static func seedTimeLogs(
        for project: Project,
        into context: ModelContext,
        calendar: Calendar,
        now: Date,
        entries: Int,
        hourlyRate: Double,
        currency: String
    ) {
        for _ in 0..<entries {
            let dayOffset = Int.random(in: 0...90)
            let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let log = TimeLog(
                hours: Double.random(in: 1...6).rounded(),
                hourlyRate: hourlyRate,
                hourlyCurrencyCode: currency,
                note: "",
                date: date,
                project: project
            )
            context.insert(log)
        }
    }
}
