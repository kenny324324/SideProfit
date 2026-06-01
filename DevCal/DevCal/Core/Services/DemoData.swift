//
//  DemoData.swift
//  DevCal
//
//  DEBUG-only demo content for App Store screenshots. Wipes the local store and
//  seeds a realistic, multi-stage portfolio in a chosen *content* language +
//  matching currency. The app UI chrome still localizes via the device language
//  (set separately in iOS Settings) — this only controls the seeded *data* text
//  (project names, descriptions, transaction labels).
//
//  Inserts go straight through the ModelContext (not the repository layer) on
//  purpose, so demo data never enqueues Firestore tombstones/pushes. Best used
//  signed-out or on a throwaway device.
//

#if DEBUG
import Foundation
import SwiftData

enum DemoLanguage: String, CaseIterable, Identifiable {
    case en, zhHant, ja, ko
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: "English"
        case .zhHant: "繁體中文"
        case .ja: "日本語"
        case .ko: "한국어"
        }
    }

    /// Currency that reads naturally for this content language. Also written to
    /// `defaultCurrency` so the display matches the seeded originals (no FX).
    var currency: String {
        switch self {
        case .en: "USD"
        case .zhHant: "TWD"
        case .ja: "JPY"
        case .ko: "KRW"
        }
    }

    /// The base amounts below are tuned in TWD; scale them into this currency.
    fileprivate var factorFromTWD: Double {
        switch self {
        case .en: 1.0 / 32.0
        case .zhHant: 1.0
        case .ja: 150.0 / 32.0
        case .ko: 1350.0 / 32.0
        }
    }

    /// Rounding step so scaled amounts look tidy per currency.
    fileprivate var roundStep: Double {
        switch self {
        case .en: 1
        case .zhHant: 10
        case .ja: 100
        case .ko: 1000
        }
    }
}

enum DemoData {

    /// Replace everything with a fresh demo portfolio in `language`.
    @MainActor
    static func apply(language: DemoLanguage, context: ModelContext) {
        wipe(context)
        seed(language: language, context: context)
        // Match the display currency to the seeded originals so screenshots
        // show clean amounts with no FX conversion.
        UserDefaults.standard.set(language.currency, forKey: "defaultCurrency")
    }

    @MainActor
    static func wipe(_ context: ModelContext) {
        deleteAll(Transaction.self, context)
        deleteAll(TimeLog.self, context)
        deleteAll(Milestone.self, context)
        deleteAll(CategoryItem.self, context)
        deleteAll(Project.self, context)
        try? context.save()
    }

    @MainActor
    private static func deleteAll<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for item in items { context.delete(item) }
    }

    // MARK: - Seed

    @MainActor
    private static func seed(language: DemoLanguage, context: ModelContext) {
        let cal = Calendar.current
        let now = Date()
        let cur = language.currency
        let c = content(for: language)

        // 1. Stage 2 — past break-even, goal + deadline set.
        let p0 = Project(
            name: c.projects[0].name, description: c.projects[0].desc,
            status: .live, kind: .template,
            launchDate: cal.date(byAdding: .month, value: -8, to: now),
            breakevenReachedAt: cal.date(byAdding: .month, value: -3, to: now),
            goalAmount: scaled(500_000, language), goalCurrencyCode: cur,
            goalDeadline: cal.date(byAdding: .month, value: 6, to: now)
        )
        // 2. justReached — income just caught up to expenses.
        let p1 = Project(
            name: c.projects[1].name, description: c.projects[1].desc,
            status: .live, kind: .web,
            launchDate: cal.date(byAdding: .month, value: -2, to: now)
        )
        // 3. Stage 1 mid (~30%).
        let p2 = Project(
            name: c.projects[2].name, description: c.projects[2].desc,
            status: .live, kind: .app,
            launchDate: cal.date(byAdding: .month, value: -4, to: now)
        )
        // 4. Stage 1 early — heavy expenses, tiny income.
        let p3 = Project(
            name: c.projects[3].name, description: c.projects[3].desc,
            status: .building, kind: .app,
            launchDate: cal.date(byAdding: .month, value: -1, to: now)
        )
        // 5. Planning — only expenses.
        let p4 = Project(
            name: c.projects[4].name, description: c.projects[4].desc,
            status: .planned, kind: .app
        )

        let projects = [p0, p1, p2, p3, p4]
        for (i, p) in projects.enumerated() {
            p.sortIndex = Double(i)
            context.insert(p)
        }

        seedTx(p0, into: context, lang: language, cal: cal, now: now, monthsBack: 8, perMonth: 7, income: 3000...12000, expense: 400...2500, share: 0.6, content: c)
        seedTx(p1, into: context, lang: language, cal: cal, now: now, monthsBack: 2, perMonth: 5, income: 1500...4000, expense: 500...2000, share: 0.5, content: c)
        seedTx(p2, into: context, lang: language, cal: cal, now: now, monthsBack: 4, perMonth: 6, income: 400...1500, expense: 700...2000, share: 0.3, content: c)
        seedTx(p3, into: context, lang: language, cal: cal, now: now, monthsBack: 1, perMonth: 5, income: 200...1200, expense: 600...4500, share: 0.2, content: c)
        seedTx(p4, into: context, lang: language, cal: cal, now: now, monthsBack: 1, perMonth: 2, income: 0...0, expense: 200...900, share: 0, content: c)

        seedTime(p0, into: context, lang: language, cal: cal, now: now, entries: 30, rate: 600)
        seedTime(p1, into: context, lang: language, cal: cal, now: now, entries: 12, rate: 500)
        seedTime(p2, into: context, lang: language, cal: cal, now: now, entries: 14, rate: 400)
        seedTime(p3, into: context, lang: language, cal: cal, now: now, entries: 10, rate: 500)

        // One shared recurring tool across the top 3 projects (enables the
        // shared-cost screenshot). Future due date so the scheduler doesn't
        // back-fill transactions for it.
        let shared = CategoryItem(
            name: "ChatGPT Team",
            category: .aiTools,
            totalAmount: scaled(900, language),
            originalCurrencyCode: cur,
            billingType: .monthly,
            brandIconKey: "openai",
            nextDueDate: cal.date(byAdding: .day, value: 15, to: now),
            isActive: true,
            isShared: true,
            splitMode: .equal,
            projects: [p0, p1, p2]
        )
        context.insert(shared)

        // Stamp break-even on any project that genuinely qualifies (p0 is
        // already stamped to a fixed historical date and stays put).
        let fx = ExchangeRateService.shared
        for p in projects {
            p.stampBreakevenIfReached(in: cur, fx: fx, triggerDate: now)
        }

        try? context.save()
    }

    @MainActor
    private static func seedTx(
        _ project: Project, into context: ModelContext, lang: DemoLanguage,
        cal: Calendar, now: Date, monthsBack: Int, perMonth: Int,
        income: ClosedRange<Double>, expense: ClosedRange<Double>, share: Double,
        content c: DemoContent
    ) {
        let incomeCats: [TransactionCategory] = [.appSales, .subscriptions, .adRevenue]
        let expenseCats: [TransactionCategory] = [.server, .api, .appStoreFee, .domain, .design, .software, .aiTools, .devTools]

        for monthOffset in 0...monthsBack {
            guard let monthStart = cal.date(byAdding: .month, value: -monthOffset, to: now) else { continue }
            for _ in 0..<perMonth {
                let dayOffset = Int.random(in: 0...27)
                let date = cal.date(byAdding: .day, value: -dayOffset, to: monthStart) ?? monthStart
                let isIncome = Double.random(in: 0...1) < share
                let cat = isIncome ? incomeCats.randomElement()! : expenseCats.randomElement()!
                let (name, brand) = c.nameAndBrand(for: cat)
                let range = isIncome ? income : expense
                let txn = Transaction(
                    type: isIncome ? .income : .expense,
                    category: cat, name: name,
                    iconBrandKey: brand, iconFallbackName: nil, iconColorHex: nil,
                    originalAmount: scaled(Double.random(in: range), lang),
                    originalCurrencyCode: lang.currency,
                    note: "", date: date, project: project
                )
                context.insert(txn)
            }
        }
    }

    @MainActor
    private static func seedTime(
        _ project: Project, into context: ModelContext, lang: DemoLanguage,
        cal: Calendar, now: Date, entries: Int, rate: Double
    ) {
        for _ in 0..<entries {
            let dayOffset = Int.random(in: 0...90)
            let date = cal.date(byAdding: .day, value: -dayOffset, to: now) ?? now
            let log = TimeLog(
                hours: Double.random(in: 1...6).rounded(),
                hourlyRate: scaled(rate, lang),
                hourlyCurrencyCode: lang.currency,
                note: "", date: date, project: project
            )
            context.insert(log)
        }
    }

    private static func scaled(_ twdBase: Double, _ lang: DemoLanguage) -> Double {
        let value = twdBase * lang.factorFromTWD
        let step = lang.roundStep
        return max(step, (value / step).rounded() * step)
    }

    // MARK: - Localized content

    fileprivate struct DemoProject { let name: String; let desc: String }

    fileprivate struct DemoContent {
        let projects: [DemoProject]
        /// Localized labels for the generic (non-brand) transaction names.
        let appSales: String
        let adRevenue: String
        let appleFee: String
        let domain: String

        func nameAndBrand(for cat: TransactionCategory) -> (String, String?) {
            func pick(_ options: [(String, String)]) -> (String, String?) {
                let o = options.randomElement()!
                return (o.0, o.1)
            }
            switch cat {
            case .appSales:      return (appSales, "apple")
            case .subscriptions: return (["Stripe", "Lemon Squeezy", "Paddle"].randomElement()!, "stripe")
            case .adRevenue:     return (adRevenue, "admob")
            case .server:        return pick([("AWS EC2", "aws"), ("DigitalOcean", "digitalocean"), ("Vercel", "vercel")])
            case .api:           return pick([("Resend", "resend"), ("Algolia", "algolia"), ("Mapbox", "mapbox")])
            case .appStoreFee:   return (appleFee, "apple")
            case .domain:        return ("Namecheap " + domain, "namecheap")
            case .design:        return ("Figma", "figma")
            case .software:      return pick([("Notion", "notion"), ("Linear", "linear"), ("Raycast", "raycast")])
            case .aiTools:       return pick([("ChatGPT Plus", "openai"), ("Claude Pro", "claude"), ("Cursor", "cursor")])
            case .devTools:      return pick([("GitHub", "github"), ("Sentry", "sentry"), ("RevenueCat", "revenuecat")])
            default:             return ("", nil)
            }
        }
    }

    fileprivate static func content(for language: DemoLanguage) -> DemoContent {
        switch language {
        case .en:
            return DemoContent(
                projects: [
                    DemoProject(name: "ShipSwift", desc: "Swift component library for shipping faster"),
                    DemoProject(name: "TinyCRM", desc: "Lightweight CRM for solo founders"),
                    DemoProject(name: "MenuBarKit", desc: "Menu bar utility for macOS"),
                    DemoProject(name: "FitJournal", desc: "AI food log for fitness coaches"),
                    DemoProject(name: "IndieMap", desc: "Discover indie iOS apps near you")
                ],
                appSales: "App Store Sales", adRevenue: "Ad Revenue",
                appleFee: "Apple Commission", domain: "Domain"
            )
        case .zhHant:
            return DemoContent(
                projects: [
                    DemoProject(name: "快艇工具", desc: "幫 indie dev 加速出貨的 Swift 元件庫"),
                    DemoProject(name: "迷你 CRM", desc: "給個人創業者的輕量 CRM"),
                    DemoProject(name: "選單列工具", desc: "macOS 選單列小工具"),
                    DemoProject(name: "飲食手帳", desc: "給健身教練的 AI 飲食紀錄"),
                    DemoProject(name: "獨立地圖", desc: "發現你附近的 indie iOS App")
                ],
                appSales: "App Store 銷售", adRevenue: "廣告分潤",
                appleFee: "Apple 平台抽成", domain: "網域"
            )
        case .ja:
            return DemoContent(
                projects: [
                    DemoProject(name: "シップキット", desc: "個人開発者向けのSwiftコンポーネント集"),
                    DemoProject(name: "タイニーCRM", desc: "個人創業者向けの軽量CRM"),
                    DemoProject(name: "メニューバーキット", desc: "macOSのメニューバーユーティリティ"),
                    DemoProject(name: "フィットジャーナル", desc: "トレーナー向けのAI食事記録"),
                    DemoProject(name: "インディーマップ", desc: "近くのインディーiOSアプリを発見")
                ],
                appSales: "App Store 売上", adRevenue: "広告収益",
                appleFee: "Apple手数料", domain: "ドメイン"
            )
        case .ko:
            return DemoContent(
                projects: [
                    DemoProject(name: "쉽스위프트", desc: "인디 개발자를 위한 Swift 컴포넌트 모음"),
                    DemoProject(name: "타이니CRM", desc: "1인 창업자를 위한 가벼운 CRM"),
                    DemoProject(name: "메뉴바킷", desc: "macOS 메뉴 막대 유틸리티"),
                    DemoProject(name: "핏저널", desc: "트레이너를 위한 AI 식단 기록"),
                    DemoProject(name: "인디맵", desc: "내 주변 인디 iOS 앱 찾기")
                ],
                appSales: "App Store 판매", adRevenue: "광고 수익",
                appleFee: "Apple 수수료", domain: "도메인"
            )
        }
    }
}
#endif
