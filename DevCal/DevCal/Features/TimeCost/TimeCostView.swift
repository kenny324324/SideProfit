//
//  TimeCostView.swift
//  DevCal
//
//  Time logs per project. Top MetricTile grid surfaces hidden labor cost and
//  effective hourly earnings; flat editorial "Sessions" list below — same
//  pattern as ProjectDashboardView (hairline-separated rows, no List).
//

import SwiftUI
import SwiftData
import PhosphorSymbols

struct TimeCostView: View {
    @Environment(\.modelContext) private var context
    @Environment(Entitlements.self) private var entitlements
    @Environment(ExchangeRateService.self) private var fx
    @AppStorage("defaultCurrency") private var defaultCurrency: String = "TWD"
    let project: Project

    @State private var showAddLog = false
    @State private var editingLog: TimeLog?
    @State private var showPaywall = false

    var body: some View {
        Group {
            if entitlements.isPro {
                content
            } else {
                proGate
            }
        }
        .background(Theme.appBackground)
        .navigationTitle("Time cost")
        .toolbarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if entitlements.isPro {
                ToolbarItem(placement: .topBarTrailing) {
                    addLogButton
                }
            }
        }
        .sheet(isPresented: $showAddLog) {
            NavigationStack {
                AddTimeLogView(project: project)
            }
        }
        .sheet(item: $editingLog) { log in
            NavigationStack {
                AddTimeLogView(project: project, editing: log)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    @ViewBuilder
    private var content: some View {
        if logs.isEmpty {
            ContentUnavailableView {
                Label("沒有時間紀錄", phImage: "timer")
            } description: {
                Text("記錄你花在這個專案上的時數,看見隱藏的勞動成本。")
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    summaryGrid
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                    sectionDivider
                    sessionsSection
                }
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var addLogButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                showAddLog = true
            } label: {
                Image(ph: "plus")
                    .frame(width: 18, height: 18)
                    .foregroundStyle(Theme.onTint)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
        } else {
            Button {
                showAddLog = true
            } label: {
                Image(ph: "plus")
                    .frame(width: 18, height: 18)
            }
        }
    }

    private var summaryGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        let totalTimeCost = project.totalTimeCost(in: defaultCurrency, fx: fx)
        let net = project.netProfit(in: defaultCurrency, fx: fx)
        let labourNet = net - totalTimeCost
        let effectiveRate = project.effectiveHourlyRate(in: defaultCurrency, fx: fx)
        return LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(
                title: "Total hours",
                value: "\(Int(project.totalHours)) h",
                tint: .indigo
            )
            MetricTile(
                title: "Hidden cost",
                value: totalTimeCost.asCompactCurrency(defaultCurrency),
                tint: Theme.expense
            )
            MetricTile(
                title: "Net (incl. labor)",
                value: labourNet.asCompactCurrency(defaultCurrency),
                tint: labourNet >= 0 ? Theme.income : Theme.expense
            )
            MetricTile(
                title: "Effective rate",
                value: effectiveRate.asCompactCurrency(defaultCurrency) + "/h",
                tint: Theme.brand
            )
        }
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Theme.primaryText.opacity(0.08))
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Sessions")
                .appFont(.title3, weight: .semibold)

            VStack(spacing: 0) {
                ForEach(logs) { log in
                    Button {
                        editingLog = log
                    } label: {
                        timeLogRow(log)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if log.id != logs.last?.id {
                        Rectangle()
                            .fill(Theme.primaryText.opacity(0.06))
                            .frame(height: 0.5)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private func timeLogRow(_ log: TimeLog) -> some View {
        let convertedRate = log.convertedHourlyRate(to: defaultCurrency, fx: fx)
        let convertedCost = log.convertedLaborCost(to: defaultCurrency, fx: fx)
        let showOriginal = log.hourlyCurrencyCode != defaultCurrency
        return HStack(spacing: 12) {
            Image(ph: "timer")
                .frame(width: 16, height: 16)
                .foregroundStyle(.indigo)
                .frame(width: 36, height: 36)
                .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(log.hours.formatted(.number.precision(.fractionLength(0...1)))) h × \(convertedRate.asCompactCurrency(defaultCurrency))/h")
                    .appFont(.subheadline, weight: .medium)
                HStack(spacing: 6) {
                    Text(log.date, style: .date)
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                    if !log.note.isEmpty {
                        Text("·").foregroundStyle(.secondary).appFont(.caption)
                        Text(log.note).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(convertedCost.asCompactCurrency(defaultCurrency))
                    .appFont(.callout, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(.indigo)
                if showOriginal {
                    Text(log.laborCost.asCompactCurrency(log.hourlyCurrencyCode) + " " + log.hourlyCurrencyCode)
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var proGate: some View {
        ContentUnavailableView {
            Label("Time cost is a Pro feature", phImage: "timer")
        } description: {
            Text("Track hours, hidden labor cost, and your real hourly return.")
        } actions: {
            Button("Upgrade to Pro") {
                showPaywall = true
            }
            .buttonStyle(.swPrimary)
        }
    }

    private var logs: [TimeLog] {
        (project.timeLogs ?? []).sorted { $0.date > $1.date }
    }
}
