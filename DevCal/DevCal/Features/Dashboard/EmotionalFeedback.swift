//
//  EmotionalFeedback.swift
//  DevCal
//
//  Picks a context-aware, stage-aware one-liner to show on the project dashboard.
//  Keeps the product emotionally engaging instead of a cold ledger.
//
//  All numeric branches need the user's display currency + FX service so the
//  thresholds (net positive, % to goal) are computed in the same currency the
//  user sees on screen.
//

import Foundation
import SwiftUI
import PhosphorSymbols

enum EmotionalFeedback {

    struct Message {
        let text: LocalizedStringKey
        let icon: Image
        let tint: Color
    }

    static func message(
        for project: Project,
        displayCode: String,
        fx: ExchangeRateService
    ) -> Message {
        let txnCount = (project.transactions ?? []).count
        if txnCount == 0 {
            return Message(
                text: "Log your first income or expense to start tracking progress.",
                icon: Image(ph: "sparkle"),
                tint: .blue
            )
        }

        switch project.stage {
        case .stageOne:
            return stageOneMessage(for: project, displayCode: displayCode, fx: fx)
        case .justReached:
            return Message(
                text: "Break-even reached. Set your next goal.",
                icon: Image(ph: "seal-check"),
                tint: Theme.income
            )
        case .stageTwo:
            return stageTwoMessage(for: project, displayCode: displayCode, fx: fx)
        }
    }

    // MARK: - Stage 1

    private static func stageOneMessage(
        for project: Project,
        displayCode: String,
        fx: ExchangeRateService
    ) -> Message {
        let income = project.totalIncome(in: displayCode, fx: fx)
        let net = project.netProfit(in: displayCode, fx: fx)
        let p = project.progress(in: displayCode, fx: fx)

        if income == 0 {
            return Message(
                text: "Costs are tracked. The first revenue is the hardest — keep shipping.",
                icon: Image(ph: "hammer"),
                tint: Theme.brand
            )
        }
        if p >= 0.75 {
            return Message(
                text: "Almost there — 75% to break-even.",
                icon: Image(ph: "flag-checkered"),
                tint: Theme.income
            )
        }
        if p >= 0.5 {
            return Message(
                text: "Halfway to break-even. Keep the momentum.",
                icon: Image(ph: "gauge"),
                tint: Theme.brand
            )
        }
        if net > 0 {
            return Message(
                text: "You're net positive this period. Good signal.",
                icon: Image(ph: "chart-line-up"),
                tint: Theme.income
            )
        }
        return Message(
            text: "Your project survived another month. That counts.",
            icon: Image(ph: "heart"),
            tint: .pink
        )
    }

    // MARK: - Stage 2

    private static func stageTwoMessage(
        for project: Project,
        displayCode: String,
        fx: ExchangeRateService
    ) -> Message {
        let p = project.progress(in: displayCode, fx: fx)

        if p >= 1 {
            return Message(
                text: "Goal reached. Set the next one when you're ready.",
                icon: Image(ph: "trophy"),
                tint: Theme.income
            )
        }
        if p >= 0.75 {
            return Message(
                text: "75% to goal — the finish line is in sight.",
                icon: Image(ph: "flag-checkered"),
                tint: Theme.income
            )
        }
        if p >= 0.5 {
            return Message(
                text: "Halfway to goal. The math is working.",
                icon: Image(ph: "gauge"),
                tint: Theme.brand
            )
        }
        return Message(
            text: "Past break-even — every dollar from here is pure progress.",
            icon: Image(ph: "chart-line-up"),
            tint: Theme.income
        )
    }
}
