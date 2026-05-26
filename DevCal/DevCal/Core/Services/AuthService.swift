//
//  AuthService.swift
//  DevCal
//
//  Phase 1: real Firebase Auth, Apple-only.
//
//  Kept as a concrete facade (per Codex audit) so `RootView`, `AuthView`, and
//  `SettingsView` keep talking to one `@Observable` service — the Firebase
//  internals never leak past this file. Sign in with Apple is the only path;
//  Google / Email / Guest are intentionally absent under the mandatory-auth
//  model locked on 2026-05-26 (see Files/Phase_1_Plan_2026-05-26.md).
//
//  Account deletion is local-only in Phase 1: `Auth.currentUser.delete()` +
//  walking every record through its Phase 0 repository so `NoopSyncService`
//  receives `isDeleted = true` tombstones. The Cloud Function cascade for
//  Firestore lands in Phase 4 alongside push/pull.
//

import Foundation
import SwiftUI
import SwiftData
import UIKit
import AuthenticationServices
import CryptoKit
import FirebaseAuth

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
        }
    }

    /// Bundle the four Phase 0 repositories + the model context that
    /// `deleteAccount` needs to enumerate and tombstone every local record.
    /// SettingsView assembles this from its `@Environment` injections; tests
    /// construct it directly against an in-memory ModelContainer.
    struct AccountPurgeContext {
        let modelContext: ModelContext
        let project: ProjectRepository
        let transaction: TransactionRepository
        let timeLog: TimeLogRepository
        let categoryItem: CategoryItemRepository
    }

    enum AuthError: LocalizedError {
        case appleCredentialMissing
        case appleAuthorizationFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .appleCredentialMissing:
                return "Apple 沒有回傳有效的登入憑證，請再試一次。"
            case .appleAuthorizationFailed(let underlying):
                return underlying.localizedDescription
            }
        }
    }

    private(set) var account: AccountSummary?
    var isSignedIn: Bool { account != nil }

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    /// Strong-held bridge between `ASAuthorizationController`'s delegate
    /// callbacks and the `async throws` surface we expose. Re-assigned per
    /// sign-in attempt so consecutive attempts can't clobber each other.
    private var pendingSignIn: AppleSignInCoordinator?

    init() {
        // Pick up an already-restored Firebase user synchronously so RootView
        // routes straight to MainTabView on launch instead of flashing AuthView
        // for one tick while the listener catches up.
        if let user = Auth.auth().currentUser {
            account = AccountSummary(from: user)
        }
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Firebase fires the listener on the main thread, but the closure
            // itself isn't @MainActor-annotated. Hop explicitly so @Observable
            // mutations stay isolated.
            Task { @MainActor in
                self?.account = user.map(AccountSummary.init(from:))
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Sign in with Apple

    func signInWithApple() async throws {
        let rawNonce = Self.randomNonceString()
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)

        let coordinator = AppleSignInCoordinator()
        pendingSignIn = coordinator
        defer { pendingSignIn = nil }

        let authorization = try await coordinator.start(request: request)
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw AuthError.appleCredentialMissing
        }

        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: identityToken,
            rawNonce: rawNonce,
            fullName: credential.fullName
        )
        _ = try await Auth.auth().signIn(with: firebaseCredential)
        // The auth state listener will publish the new AccountSummary; we
        // don't set `account` here so there's only one source of truth.
    }

    // MARK: - Sign out

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Account deletion (Phase 1: local + Auth only)

    /// Deletes the Firebase Auth user, then walks every local record through
    /// its repository so Phase 4 sync sees an `isDeleted = true` tombstone for
    /// each one. Cloud Function cascade for Firestore is Phase 4.
    ///
    /// Auth deletion runs first: if Firebase rejects it (commonly because the
    /// user needs to re-authenticate), the local SwiftData is never touched
    /// and the user can retry without losing data.
    func deleteAccount(localPurge: AccountPurgeContext) async throws {
        if let user = Auth.auth().currentUser {
            try await user.delete()
        }
        try await Self.purgeLocalData(localPurge)
    }

    /// Static so tests can exercise the tombstone pipeline without
    /// constructing an `AuthService` (which would require `FirebaseApp` to be
    /// configured). The instance method `deleteAccount(localPurge:)` calls
    /// this after the Firebase Auth delete succeeds.
    static func purgeLocalData(_ ctx: AccountPurgeContext) async throws {
        // Leaf entities first so each tombstone is enqueued with the same
        // parent reference its document carried at write time, then category
        // items (some are shared across projects), then projects.
        //
        // Milestones aren't enumerated here because there's no MilestoneRepository
        // yet (Phase 0 stopped at the four busiest aggregates). They cascade-
        // delete locally with their parent project; Phase 4 sync will need a
        // small MilestoneRepository to enqueue tombstones for them, but the
        // MVP can ship without it because milestones are local-only today.
        let txns = try ctx.modelContext.fetch(FetchDescriptor<Transaction>())
        for txn in txns {
            try await ctx.transaction.deleteTransaction(txn)
        }
        let logs = try ctx.modelContext.fetch(FetchDescriptor<TimeLog>())
        for log in logs {
            try await ctx.timeLog.deleteTimeLog(log)
        }
        let items = try ctx.modelContext.fetch(FetchDescriptor<CategoryItem>())
        for item in items {
            try await ctx.categoryItem.deleteCategoryItem(item)
        }
        let projects = try ctx.modelContext.fetch(FetchDescriptor<Project>())
        for project in projects {
            try await ctx.project.deleteProject(project)
        }
    }

    // MARK: - Nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array(
            "0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._"
        )
        var result = ""
        var remaining = length
        while remaining > 0 {
            var byte: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            guard status == errSecSuccess else { continue }
            if byte < charset.count {
                result.append(charset[Int(byte)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension AuthService.AccountSummary {
    /// Map a Firebase `User` onto the small summary RootView / SettingsView
    /// already consume. Apple often returns nil for `displayName` after the
    /// first sign-in, so fall back to the email local part, then to a generic
    /// label — never show a blank account pill.
    init(from user: User) {
        let name: String
        if let displayName = user.displayName, !displayName.isEmpty {
            name = displayName
        } else if let email = user.email, let local = email.split(separator: "@").first {
            name = String(local)
        } else {
            name = "Indie Dev"
        }
        self.init(
            id: user.uid,
            displayName: name,
            email: user.email,
            provider: .apple
        )
    }
}

// MARK: - Apple Sign In bridge

/// Thin NSObject delegate that turns the ASAuthorizationController callback
/// surface into a single `async throws` call. Owned by `AuthService` for the
/// duration of one sign-in attempt.
@MainActor
private final class AppleSignInCoordinator: NSObject,
                                            ASAuthorizationControllerDelegate,
                                            ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?

    func start(request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        continuation?.resume(returning: authorization)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(
            throwing: AuthService.AuthError.appleAuthorizationFailed(underlying: error)
        )
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
