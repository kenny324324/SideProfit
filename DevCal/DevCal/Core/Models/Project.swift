//
//  Project.swift
//  DevCal
//

import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = ""
    var projectDescription: String = ""
    var statusRaw: String = ProjectStatus.building.rawValue
    var kindRaw: String = ProjectKind.app.rawValue

    /// Custom icon options (mutually exclusive). When both are nil the UI
    /// falls back to `kind.defaultPhName` rendered in Phosphor fill weight.
    /// - `iconImageData`: user-uploaded photo, resized + JPEG-compressed.
    /// - `iconPhName`: user-picked Phosphor symbol name (rendered in fill).
    @Attribute(.externalStorage) var iconImageData: Data? = nil
    var iconPhName: String? = nil
    /// Hex string for the icon tint. nil → use `Theme.brand` so that
    /// re-skinning the brand color automatically updates uncustomized items.
    var iconColorHex: String? = nil
    var launchDate: Date? = nil
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var archivedAt: Date? = nil
    // Lower value = closer to the top of the list. New projects get
    // `currentMin - 1` so they land at the top; drag-to-reorder renumbers
    // every visible row by its new offset.
    var sortIndex: Double = 0

    // MARK: - Two-stage progress
    // Stage 1: progress = totalIncome / totalExpenses, target is implicit.
    // Once income ≥ expenses, `breakevenReachedAt` is stamped (forever).
    // Stage 2: user sets `goalAmount` (+ optional `goalDeadline`); progress = totalIncome / goalAmount.

    /// Stamped the first time cumulative income reached cumulative expenses.
    /// Never cleared once set, even if subsequent expenses push Net negative again.
    var breakevenReachedAt: Date? = nil
    /// Stage-2 lifetime revenue target. Set by the user after break-even is reached.
    var goalAmount: Double? = nil
    /// Currency the goal was set in. Stays fixed even when display currency
    /// changes so the goal value doesn't appear to drift.
    var goalCurrencyCode: String? = nil
    /// Optional target date for the goal — enables ahead/behind projection.
    var goalDeadline: Date? = nil

    @Relationship(deleteRule: .cascade, inverse: \Transaction.project)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .cascade, inverse: \TimeLog.project)
    var timeLogs: [TimeLog]? = []

    @Relationship(deleteRule: .cascade, inverse: \Milestone.project)
    var milestones: [Milestone]? = []

    /// Sub-items the user has created under any category, scoped to this
    /// project. Shared items also list this project here; on project delete,
    /// SwiftData simply removes the back-reference from shared items.
    var categoryItems: [CategoryItem]? = []

    init(
        name: String = "",
        description: String = "",
        status: ProjectStatus = .building,
        kind: ProjectKind = .app,
        iconImageData: Data? = nil,
        iconPhName: String? = nil,
        iconColorHex: String? = nil,
        launchDate: Date? = nil,
        breakevenReachedAt: Date? = nil,
        goalAmount: Double? = nil,
        goalCurrencyCode: String? = nil,
        goalDeadline: Date? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.projectDescription = description
        self.statusRaw = status.rawValue
        self.kindRaw = kind.rawValue
        self.iconImageData = iconImageData
        self.iconPhName = iconPhName
        self.iconColorHex = iconColorHex
        self.launchDate = launchDate
        self.breakevenReachedAt = breakevenReachedAt
        self.goalAmount = goalAmount
        self.goalCurrencyCode = goalCurrencyCode
        self.goalDeadline = goalDeadline
        let now = Date()
        self.createdAt = now
        self.updatedAt = now
    }

    var status: ProjectStatus {
        get { ProjectStatus(rawValue: statusRaw) ?? .building }
        set { statusRaw = newValue.rawValue }
    }

    var kind: ProjectKind {
        get { ProjectKind(rawValue: kindRaw) ?? .app }
        set { kindRaw = newValue.rawValue }
    }

    // MARK: - Sums (cash only — time NEVER included in Net per spec)
    //
    // All aggregations convert each transaction to `displayCode` using today's
    // FX rate, then sum. Per-transaction original currency is preserved on
    // disk; this view is computed.

    func totalIncome(in displayCode: String, fx: ExchangeRateService) -> Double {
        (transactions ?? [])
            .filter { $0.type == .income }
            .reduce(0) { $0 + $1.convertedAmount(to: displayCode, fx: fx) }
    }

    func totalExpenses(in displayCode: String, fx: ExchangeRateService) -> Double {
        (transactions ?? [])
            .filter { $0.type == .expense }
            .reduce(0) { $0 + $1.convertedAmount(to: displayCode, fx: fx) }
    }

    func netProfit(in displayCode: String, fx: ExchangeRateService) -> Double {
        totalIncome(in: displayCode, fx: fx) - totalExpenses(in: displayCode, fx: fx)
    }

    func totalTimeCost(in displayCode: String, fx: ExchangeRateService) -> Double {
        (timeLogs ?? []).reduce(0) { $0 + $1.convertedLaborCost(to: displayCode, fx: fx) }
    }

    var totalHours: Double {
        (timeLogs ?? []).reduce(0) { $0 + $1.hours }
    }

    /// Net ÷ total hours, in display currency. Display-only — never folded into Net.
    func effectiveHourlyRate(in displayCode: String, fx: ExchangeRateService) -> Double {
        guard totalHours > 0 else { return 0 }
        return netProfit(in: displayCode, fx: fx) / totalHours
    }

    // MARK: - Two-stage progress

    var stage: ProgressStage {
        if breakevenReachedAt == nil { return .stageOne }
        if goalAmount == nil { return .justReached }
        return .stageTwo
    }

    /// 0...1 progress for whichever stage the project is in. Computed in
    /// `displayCode` because stage-1 compares income vs expenses and stage-2
    /// compares income vs goal — both need a common currency.
    func progress(in displayCode: String, fx: ExchangeRateService) -> Double {
        switch stage {
        case .stageOne:
            let exp = totalExpenses(in: displayCode, fx: fx)
            guard exp > 0 else { return 0 }
            return min(1, max(0, totalIncome(in: displayCode, fx: fx) / exp))
        case .justReached:
            return 1
        case .stageTwo:
            guard let goal = goalAmount, goal > 0 else { return 0 }
            let goalInDisplay = fx.convert(goal, from: goalCurrencyCode ?? displayCode, to: displayCode) ?? goal
            guard goalInDisplay > 0 else { return 0 }
            return min(1, max(0, totalIncome(in: displayCode, fx: fx) / goalInDisplay))
        }
    }

    /// The denominator behind the current stage's progress — used in the
    /// "$X of $Y" caption under the hero ring. In `displayCode`.
    func progressTarget(in displayCode: String, fx: ExchangeRateService) -> Double {
        switch stage {
        case .stageOne, .justReached: return totalExpenses(in: displayCode, fx: fx)
        case .stageTwo:
            guard let goal = goalAmount else { return 0 }
            return fx.convert(goal, from: goalCurrencyCode ?? displayCode, to: displayCode) ?? goal
        }
    }

    /// Sum of this calendar month's signed amounts (income +, expense −) in
    /// display currency. Used in the project list row.
    func netThisMonth(in displayCode: String, fx: ExchangeRateService) -> Double {
        let cal = Calendar.current
        let now = Date()
        guard let monthStart = cal.date(
            from: cal.dateComponents([.year, .month], from: now)
        ) else { return 0 }
        return (transactions ?? [])
            .filter { $0.date >= monthStart }
            .reduce(0) { $0 + $1.signedConvertedAmount(to: displayCode, fx: fx) }
    }

    // MARK: - Break-even stamp

    /// Call after any income/expense write. Stamps `breakevenReachedAt` the
    /// first time cumulative income ≥ cumulative expense (compared in
    /// `displayCode`); no-op otherwise. Once set, never cleared.
    func stampBreakevenIfReached(
        in displayCode: String,
        fx: ExchangeRateService,
        triggerDate: Date = Date()
    ) {
        guard breakevenReachedAt == nil else { return }
        let exp = totalExpenses(in: displayCode, fx: fx)
        let inc = totalIncome(in: displayCode, fx: fx)
        guard exp > 0, inc >= exp else { return }
        breakevenReachedAt = triggerDate
    }
}
