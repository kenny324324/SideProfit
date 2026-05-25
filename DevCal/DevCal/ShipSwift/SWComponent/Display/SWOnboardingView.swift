//
//  SWOnboardingView.swift
//  DevCal
//
//  Copied from ShipSwift (SWPackage/SWComponent/Display/SWOnboardingView.swift) and customized
//  for SideProfit. The OnboardingPage enum's cases / icons / titles / descriptions are the
//  SideProfit-specific content; the view structure is unchanged.
//

import SwiftUI
import PhosphorSymbols

// MARK: - Onboarding Main View
struct SWOnboardingView: View {
    let onComplete: () -> Void

    private let pages = OnboardingPage.allCases
    @State private var currentPage = 0

    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.element) { index, page in
                    VStack(spacing: 24) {
                        Spacer()

                        page.icon
                            .frame(width: 80, height: 80)
                            .foregroundStyle(.tint)
                        Text(page.title)
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        Text(page.description)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                    .padding(.horizontal)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            #endif

            Button {
                if currentPage < pages.count - 1 {
                    withAnimation {
                        currentPage += 1
                    }
                } else {
                    onComplete()
                }
            } label: {
                Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
            }
            .buttonStyle(.swPrimary)
            .padding(.bottom)

            Button {
                onComplete()
            } label: {
                Text("Skip")
                    .foregroundStyle(.secondary)
            }
            .opacity(currentPage < pages.count - 1 ? 0 : 1)
        }
        .safeAreaPadding(.horizontal)
    }
}

// MARK: - Onboarding Page Model
enum OnboardingPage: CaseIterable {
    case profitability
    case breakEven
    case timeCost
    case shareProgress

    var icon: Image {
        switch self {
        case .profitability: Image(ph: "chart-line-up")
        case .breakEven: Image(ph: "target")
        case .timeCost: Image(ph: "timer")
        case .shareProgress: Image(ph: "share-fat")
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .profitability: "Is your project profitable?"
        case .breakEven: "See your break-even progress"
        case .timeCost: "Don't ignore your time"
        case .shareProgress: "Share your progress"
        }
    }

    var description: LocalizedStringKey {
        switch self {
        case .profitability: "Track revenue and expenses for each app or side project. See if you're making money — or just burning it."
        case .breakEven: "Visualize how close you are to recovering your costs. Know exactly when your project pays off."
        case .timeCost: "Track hours and your real hourly rate. Uncover the hidden labor cost most developers miss."
        case .shareProgress: "Generate shareable cards for revenue milestones and break-even moments. Build in public, on your terms."
        }
    }
}

// MARK: - Preview
#Preview("Onboarding") {
    SWOnboardingView(onComplete: { print("Done") })
}
