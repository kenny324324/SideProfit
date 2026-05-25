//
//  AuthService.swift
//  DevCal
//
//  Mock auth service for the UI-first phase. Replace with a FirebaseAuthService that
//  conforms to AuthServicing once the Firebase SDK is wired in (see
//  Files/Firebase_Setup_Checklist.md → "1. Firebase Auth").
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class AuthService {

    struct AccountSummary: Equatable {
        var id: String
        var displayName: String
        var email: String?
        var provider: Provider

        enum Provider: String, Codable {
            case apple
            case google
            case email
            case mock
        }
    }

    private(set) var account: AccountSummary?

    var isSignedIn: Bool { account != nil }

    init() {
        // Restore last mock session from UserDefaults so dev iteration survives relaunch.
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(StoredAccount.self, from: data) {
            account = AccountSummary(
                id: decoded.id,
                displayName: decoded.displayName,
                email: decoded.email,
                provider: decoded.provider
            )
        }
    }

    // MARK: - Mock sign-in flows

    func signInWithApple() async {
        // TODO(firebase): real Sign in with Apple via ASAuthorizationAppleIDProvider +
        // OAuthCredential exchange with Firebase Auth.
        await mockSignIn(displayName: "Kenny", email: "kenny@privaterelay.appleid.com", provider: .apple)
    }

    func signInWithGoogle() async {
        // TODO(firebase): real Google Sign-In via GIDSignIn -> Firebase credential.
        await mockSignIn(displayName: "Kenny", email: "justhings2026@gmail.com", provider: .google)
    }

    func signInWithEmail(_ email: String) async {
        // TODO(firebase): real email link / email-password via Firebase Auth.
        let name = String(email.split(separator: "@").first ?? "Indie Dev")
        await mockSignIn(displayName: name, email: email, provider: .email)
    }

    func signInAsGuest() async {
        // Local-only path used during the UI-first phase. Will become real anonymous
        // Firebase Auth (or be removed) depending on final account model.
        await mockSignIn(displayName: "Guest", email: nil, provider: .mock)
    }

    func signOut() {
        account = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    // MARK: - Helpers

    private func mockSignIn(displayName: String, email: String?, provider: AccountSummary.Provider) async {
        try? await Task.sleep(for: .milliseconds(400))
        let next = AccountSummary(
            id: UUID().uuidString,
            displayName: displayName,
            email: email,
            provider: provider
        )
        account = next
        persist(next)
    }

    private func persist(_ account: AccountSummary) {
        let stored = StoredAccount(
            id: account.id,
            displayName: account.displayName,
            email: account.email,
            provider: account.provider
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static let storageKey = "auth.mockAccount"

    private struct StoredAccount: Codable {
        var id: String
        var displayName: String
        var email: String?
        var provider: AccountSummary.Provider
    }
}
