//
//  AuthView.swift
//  DevCal
//
//  Apple-only sign-in. The splash brand mark is rendered at the same offset
//  it had on the splash so it appears to "stay put" while the splash fades
//  out and the sign-in surface fades in. The Apple button + legal fine print
//  are pinned to the bottom. Sign in with Apple is wired through to
//  `AuthService.signInWithApple()` (FirebaseAuth + ASAuthorizationController);
//  errors surface in a systemAlert per the Phase 0 pattern.
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AuthService.self) private var auth
    @State private var isWorking = false
    @State private var signInError: String? = nil
    @State private var showErrorAlert = false

    /// Auth's brand mark sits at exactly the splash offset so the icon+name
    /// lockup doesn't visually jump when the splash fades.
    @AppStorage(SplashDefaults.blockOffsetYKey) private var brandOffsetY: Int = SplashDefaults.defaultBlockOffsetY

    var body: some View {
        ZStack {
            Theme.appBackground.ignoresSafeArea()

            SplashBrandMark()
                .offset(y: CGFloat(brandOffsetY))

            VStack(spacing: 14) {
                Spacer()
                appleButton
                legalFinePrint
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .disabled(isWorking)
        .systemAlert("登入失敗", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { signInError = nil }
        } message: {
            Text(signInError ?? "")
        }
    }

    // MARK: - Sections

    private var appleButton: some View {
        Button {
            Task { await runSignIn() }
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
        Text(legalAttributed)
            .appFont(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var legalAttributed: AttributedString {
        let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
        let privacyURL = URL(string: "https://ripe-cereal-4f9.notion.site/Privacy-Policy-36c341fcbfde806e850dd81ac8b72b63")!

        var result = AttributedString("登入即表示您同意我們的\n")

        var terms = AttributedString("服務條款")
        terms.link = termsURL
        terms.foregroundColor = Theme.brand
        terms.underlineStyle = .single

        let conjunction = AttributedString(" 和 ")

        var privacy = AttributedString("隱私權政策")
        privacy.link = privacyURL
        privacy.foregroundColor = Theme.brand
        privacy.underlineStyle = .single

        result.append(terms)
        result.append(conjunction)
        result.append(privacy)
        return result
    }

    // MARK: - Helpers

    /// Guards against double-taps and surfaces sign-in errors through the
    /// same systemAlert pattern Phase 0 introduced for save failures. The
    /// `.canceled` case (user dismissed the Apple sheet) is swallowed
    /// silently — re-prompting on dismissal would feel hostile.
    private func runSignIn() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await auth.signInWithApple()
        } catch let AuthService.AuthError.appleAuthorizationFailed(underlying) {
            if let asError = underlying as? ASAuthorizationError, asError.code == .canceled {
                return
            }
            signInError = underlying.localizedDescription
            showErrorAlert = true
        } catch {
            signInError = error.localizedDescription
            showErrorAlert = true
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthService())
        .environment(Entitlements())
}
