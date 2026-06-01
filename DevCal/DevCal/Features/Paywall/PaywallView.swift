//
//  PaywallView.swift
//  DevCal
//
//  Mock paywall. Visual fidelity matches the eventual StoreKit-backed paywall;
//  purchase actions currently flip Entitlements locally. Real StoreKit 2 wiring
//  is tracked in Files/Firebase_Setup_Checklist.md → "7. Subscription".
//

import SwiftUI
import PhosphorSymbols

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements

    @State private var selectedPlan: Entitlements.Plan = .proYearly
    @State private var isPurchasing = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 28) {
                        hero
                        comparisonTable
                        planPicker
                        Color.clear.frame(height: 160) // sits just above floating bar at max scroll
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)

                bottomFade

                floatingBottomBar
            }
            .background(background.ignoresSafeArea())
            .navigationTitle("升級至 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(ph: "x", weight: .bold)
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Theme.primaryText)
                    }
                    .cancelActionStyle()
                }
            }
        }
    }

    // MARK: - Bottom fade

    private var bottomFade: some View {
        LinearGradient(
            colors: [
                Theme.appBackground.opacity(0),
                Theme.appBackground.opacity(0.85),
                Theme.appBackground
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 240)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 18) {
            Image("PlantFill")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(Theme.brand)
            VStack(spacing: 6) {
                Text("SideProfit Pro")
                    .appFont(size: 32, weight: .bold)
                    .foregroundStyle(Theme.primaryText)
                Text("解鎖無限專案、時間成本追蹤與進階分析")
                    .appFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Comparison table

    private struct ComparisonRow: Identifiable {
        let id = UUID()
        let icon: String
        let label: LocalizedStringKey
        let free: Cell
        let pro: Cell

        enum Cell {
            case dash
            case check
            case text(LocalizedStringKey)
        }
    }

    private var comparisonRows: [ComparisonRow] {
        [
            .init(icon: "stack", label: "專案數量", free: .text("1 個"), pro: .text("無限")),
            .init(icon: "users-three", label: "共用項目", free: .dash, pro: .check),
            .init(icon: "timer", label: "時間成本追蹤", free: .dash, pro: .check),
            .init(icon: "chart-line-up", label: "跨專案洞察", free: .dash, pro: .check),
        ]
    }

    private var comparisonTable: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("功能比較")
                .appFont(.footnote, weight: .semibold)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                // header row
                HStack(spacing: 12) {
                    Color.clear
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("免費版")
                        .appFont(.caption, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .center)
                    Text("Pro")
                        .appFont(.caption, weight: .bold)
                        .foregroundStyle(Theme.brand)
                        .frame(width: 64, alignment: .center)
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                ForEach(Array(comparisonRows.enumerated()), id: \.element.id) { i, row in
                    HStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Image(ph: row.icon, weight: .fill)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 18, height: 18)
                                .foregroundStyle(Theme.brand)
                            Text(row.label)
                                .appFont(.subheadline, weight: .medium)
                                .foregroundStyle(Theme.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        cell(row.free, isPro: false)
                            .frame(width: 64, alignment: .center)
                        cell(row.pro, isPro: true)
                            .frame(width: 64, alignment: .center)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)

                    if i < comparisonRows.count - 1 {
                        Divider()
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.appBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func cell(_ cell: ComparisonRow.Cell, isPro: Bool) -> some View {
        switch cell {
        case .dash:
            Text("—")
                .appFont(.subheadline)
                .foregroundStyle(.tertiary)
        case .check:
            Image(ph: "check", weight: .bold)
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(isPro ? Theme.brand : Theme.primaryText)
        case .text(let key):
            Text(key)
                .appFont(.subheadline, weight: isPro ? .bold : .regular)
                .foregroundStyle(isPro ? Theme.brand : Theme.primaryText)
        }
    }

    // MARK: - Plan picker

    private var planPicker: some View {
        HStack(spacing: 10) {
            planCard(
                plan: .proYearly,
                title: "年付",
                price: "US$39.99",
                perPeriod: "/年",
                badge: "省 33%",
                trial: "7 天免費試用"
            )
            planCard(
                plan: .proMonthly,
                title: "月付",
                price: "US$4.99",
                perPeriod: "/月",
                badge: nil,
                trial: nil
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func planCard(
        plan: Entitlements.Plan,
        title: LocalizedStringKey,
        price: String,
        perPeriod: LocalizedStringKey,
        badge: LocalizedStringKey?,
        trial: LocalizedStringKey?
    ) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Theme.brand : Color.secondary.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                        if isSelected {
                            Circle()
                                .fill(Theme.brand)
                                .frame(width: 10, height: 10)
                        }
                    }
                    Spacer(minLength: 4)
                    if let badge {
                        Text(badge)
                            .appFont(.caption2, weight: .bold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.income.opacity(0.18), in: Capsule())
                            .foregroundStyle(Theme.income)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .appFont(.subheadline, weight: .semibold)
                        .foregroundStyle(Theme.primaryText)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(price)
                            .appFont(.title3, weight: .bold)
                            .monospacedDigit()
                            .foregroundStyle(Theme.primaryText)
                        Text(perPeriod)
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // Bottom slot — trial line on yearly, invisible placeholder on monthly
                // keeps both cards the same natural height.
                Group {
                    if let trial {
                        Text(trial)
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(" ")
                            .appFont(.caption)
                            .opacity(0)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.appBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.brand : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Floating bottom bar

    private var floatingBottomBar: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchase() }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing { ProgressView().controlSize(.small) }
                    Text(entitlements.isPro ? "已是 Pro 會員" : "繼續")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.swPrimary)
            .disabled(isPurchasing || entitlements.isPro)

            Text("隨時可取消。除非在 App Store 設定中取消，否則會自動續訂。")
                .appFont(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                Button {
                    entitlements.restore()
                } label: {
                    Text("還原購買")
                }
                Text("·").foregroundStyle(.tertiary)
                Link("隱私政策", destination: URL(string: "https://example.com/privacy")!)
                Text("·").foregroundStyle(.tertiary)
                Link("服務條款", destination: URL(string: "https://example.com/terms")!)
            }
            .appFont(.caption2)
            .tint(.secondary)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .modifier(FloatingBarBackground())
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Background / purchase

    private var background: some View {
        LinearGradient(
            colors: [Theme.brand.opacity(0.08), Theme.appBackground],
            startPoint: .top,
            endPoint: .center
        )
    }

    @MainActor
    private func purchase() async {
        isPurchasing = true
        try? await Task.sleep(for: .milliseconds(700))
        entitlements.upgrade(to: selectedPlan)
        isPurchasing = false
        dismiss()
    }
}

// MARK: - Floating glass surface
//
// Bottom action bar that floats over the scroll content. iOS 26+ uses native
// Liquid Glass; older systems fall back to a themed card with a soft top edge.

private struct FloatingBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(Theme.appBackground.opacity(0.4)),
                    in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                )
                .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
        } else {
            content
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Theme.appBackground.opacity(0.6))
                }
                .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        }
    }
}
