//
//  AuthView.swift
//  DevCal
//
//  Apple-only sign-in. Header sits at the top; the button + legal fine print are
//  pinned to the bottom of the screen. Real Sign in with Apple wiring lives in
//  Files/Firebase_Setup_Checklist.md; AuthService still fakes the call.
//

import SwiftUI
import PhosphorSymbols

struct AuthView: View {
    @Environment(AuthService.self) private var auth
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 64)

            Spacer(minLength: 24)

            VStack(spacing: 14) {
                appleButton
                legalFinePrint
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backgroundGradient.ignoresSafeArea())
        .disabled(isWorking)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.15))
                    .frame(width: 96, height: 96)
                Image(ph: "trend-up")
                    .frame(width: 44, height: 44)
                    .foregroundStyle(.tint)
            }
            Text(verbatim: "SideProfit")
                .appFont(.largeTitle, weight: .bold)
            Text("Track whether your side project is becoming profitable.")
                .appFont(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var appleButton: some View {
        Button {
            Task { await run { await auth.signInWithApple() } }
        } label: {
            HStack(spacing: 10) {
                BrandIconRegistry.image(for: "apple")
                    .frame(width: 24, height: 24)
                Text("Sign in with Apple")
                    .appFont(.body, weight: .semibold)
            }
            .foregroundStyle(Theme.appBackground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.primaryText, in: Capsule())
        }
    }

    private var legalFinePrint: some View {
        Text("By continuing, you agree to the Terms of Use and Privacy Policy.")
            .appFont(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Theme.appBackground, Theme.appBackground, Theme.brand.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Helpers

    private func run(_ work: @Sendable () async -> Void) async {
        isWorking = true
        await work()
        isWorking = false
    }
}

#Preview {
    AuthView()
        .environment(AuthService())
        .environment(Entitlements())
}
