//
//  ProjectCard.swift
//  DevCal
//
//  Row item for the project list. Shows name, status pill, this-month/all-time
//  Net, and a stage-aware progress bar (Break-even %  in Stage 1, Goal % in
//  Stage 2). Renders as a flat editorial row — the parent list separates rows
//  with hairlines, matching the Settings page.
//
//  All amounts render in the user's display currency, converted via the
//  shared `ExchangeRateService`. Per-transaction originals are preserved on
//  disk; this card just rolls them up at today's rate.
//

import SwiftUI

struct ProjectCard: View {
    let project: Project

    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"
    @Environment(ExchangeRateService.self) private var fx

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            metrics
            progressBar
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .contentShape(Rectangle())
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ProjectIconView(
                imageData: project.iconImageData,
                phName: project.iconPhName,
                kindFallback: project.kind,
                size: 36,
                colorHex: project.iconColorHex
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .appFont(.title3, weight: .semibold)
                    .lineLimit(1)
                if !project.projectDescription.isEmpty {
                    Text(project.projectDescription)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        Text(project.status.displayName)
            .appFont(.footnote, weight: .medium)
            .foregroundStyle(project.status.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(project.status.tint.opacity(0.12), in: Capsule())
    }

    // MARK: - Metrics (this month / all time)

    private var metrics: some View {
        HStack(spacing: 16) {
            metric(title: "This month", value: project.netThisMonth(in: defaultCurrency, fx: fx))
            Divider().frame(height: 28)
            metric(title: "All time", value: project.netProfit(in: defaultCurrency, fx: fx))
        }
    }

    private func metric(title: LocalizedStringKey, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .appFont(.caption2)
                .foregroundStyle(.secondary)
            Text(formatted(value))
                .appFont(.callout, weight: .semibold)
                .foregroundStyle(value >= 0 ? Theme.income : Theme.expense)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatted(_ value: Double) -> String {
        let prefix = value > 0 ? "+" : ""
        return prefix + value.asCompactCurrency(defaultCurrency)
    }

    // MARK: - Progress bar (stage-aware)

    private var progressBar: some View {
        let progress = project.progress(in: defaultCurrency, fx: fx)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(progressLabel)
                    .appFont(.caption, weight: .medium)
                Spacer()
                if shouldShowPercent {
                    Text("\(Int((progress * 100).rounded()))%")
                        .appFont(.caption, weight: .semibold)
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                } else {
                    Text("No expenses yet")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.primaryText.opacity(0.05))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.income)
                        .frame(width: geo.size.width * progress)
                        .animation(.snappy, value: progress)
                }
            }
            .frame(height: 8)
        }
    }

    private var progressLabel: LocalizedStringKey {
        switch project.stage {
        case .stageOne, .justReached: return "Break-even"
        case .stageTwo: return "Goal"
        }
    }

    private var shouldShowPercent: Bool {
        switch project.stage {
        case .stageOne: return project.totalExpenses(in: defaultCurrency, fx: fx) > 0
        case .justReached, .stageTwo: return true
        }
    }
}
