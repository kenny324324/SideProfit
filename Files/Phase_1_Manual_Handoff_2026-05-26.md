# Phase 1 Manual Handoff — what Kenny still has to do

Date: 2026-05-26
Reads from: [Phase_1_Plan_2026-05-26.md](Phase_1_Plan_2026-05-26.md), [Firebase_Setup_Checklist.md](Firebase_Setup_Checklist.md)

Claude did all the code changes for Phase 1. **The build will not compile yet** because `import FirebaseAuth` / `import FirebaseCore` need the SDK to actually be in the project. Below is the exact sequence to get back to green.

## What changed in code (so you know what's depending on the SDK)

- `Core/Services/AuthService.swift` — full rewrite. Imports `FirebaseAuth`, `AuthenticationServices`, `CryptoKit`, `UIKit`, `SwiftData`. Mock methods (`signInWithGoogle`, `signInWithEmail`, `signInAsGuest`) deleted. New surface: `signInWithApple() async throws`, `signOut() throws`, `deleteAccount(localPurge:) async throws`, plus a static `purgeLocalData(_:)` for tests.
- `DevCalApp.swift` — imports `FirebaseCore`; `init()` calls `FirebaseApp.configure()` before constructing `AuthService`. `@State private var auth` is now `init`-bound (re-assigned via `_auth = State(initialValue: ...)`) so the listener attaches after Firebase is configured.
- `Features/Auth/AuthView.swift` — Apple button does try/catch around `auth.signInWithApple()`; `ASAuthorizationError.canceled` is swallowed silently; everything else hits a `systemAlert("登入失敗", ...)`.
- `Features/Settings/SettingsView.swift` — sign-out + delete-account confirms now wire through `runSignOut()` / `runDeleteAccount()`. Delete passes an `AuthService.AccountPurgeContext` built from the four repositories. Copy: 「登入帳號與本機資料都會永久移除，且無法復原。」
- `DevCalTests/AuthServiceTests.swift` — new file. Exercises `AuthService.purgeLocalData(_:)` against an in-memory ModelContainer. Doesn't import Firebase, doesn't construct an `AuthService`.

## The exact manual steps, in order

### 1. Add Firebase SDK via SPM — `FirebaseAuth` only

In Xcode → File → Add Package Dependencies → enter:

```
https://github.com/firebase/firebase-ios-sdk
```

Pick a recent stable tag (10.x or 11.x). When the products picker appears, **tick only `FirebaseAuth`**. (`FirebaseCore` comes along automatically as a transitive dep — that's fine; do not tick Firestore / Crashlytics / Analytics / Remote Config yet, those land in their own phases.)

### 2. Enable Sign in with Apple capability

Xcode → DevCal target → Signing & Capabilities → `+` Capability → **Sign in with Apple**.

This creates a `.entitlements` file (or adds to an existing one). Confirm the entitlement key `com.apple.developer.applesignin` is present with value `["Default"]`.

You'll also need, in Apple Developer Portal:
- Service ID + private key (Sign in with Apple) registered to your app bundle ID
- Upload the private key (.p8) to Firebase Console → Authentication → Sign-in method → Apple

### 3. Firebase Console — enable only Sign in with Apple

Firebase Console → Authentication → Sign-in method:
- **Enable Apple.** Provide Service ID + key from step 2.
- **Leave Anonymous, Email/Password, Email link, and Google disabled.** Phase 1 decision: Apple-only.

### 4. Drop `GoogleService-Info.plist` into the Xcode target

Download from Firebase Console → Project settings → iOS app → Download `GoogleService-Info.plist`. Drag into the Xcode target, "Copy items if needed" checked. If the repo is or becomes public, add it to `.gitignore`.

### 5. Build

Cmd-B in Xcode. Expected results:
- `import FirebaseAuth` and `import FirebaseCore` resolve.
- AuthService / DevCalApp / AuthView / SettingsView compile clean.
- AuthServiceTests target compiles too (it doesn't import Firebase, so it would have already compiled, but won't run without the main target building first).

If you get a build error about `AppleSignInCoordinator` being non-Sendable: that's a Swift 6 strict concurrency thing on UIKit delegates. The class is `@MainActor` so it should be fine, but if it complains anyway, ping Claude — we may need to flip a delegate method to `nonisolated` and hop with `Task { @MainActor in ... }`.

### 6. Smoke test on a real device (Apple sign-in needs one)

Sign in with Apple does not work in the simulator. Run on a real iPhone signed into an iCloud account:
- Tap "Sign in with Apple" → system sheet → confirm → app should land on `MainTabView` and the Settings account pill should show your Apple Relay email or chosen email.
- Settings → Sign out → should bounce back to `AuthView`.
- Settings → Delete account → confirm → Firebase user is deleted + local SwiftData is wiped (you should see seed data gone on next launch, but Phase 0 seeds again if store is empty — by design).

## If Apple Sign in fails on the first attempt

A common gotcha: the Service ID's Return URLs in Apple Developer Portal must include the Firebase OAuth handler — Firebase Console tells you the exact URL when you enable the provider. Copy it over and re-try.

## When all of this lands

- Tick the remaining Phase 1 items in [Firebase_Setup_Checklist.md](Firebase_Setup_Checklist.md) (the ones still showing `[ ]`).
- Phase 1 plan ([Phase_1_Plan_2026-05-26.md](Phase_1_Plan_2026-05-26.md)) is already marked "code-side DONE"; you can promote it to fully DONE once the manual side is also done.
- Next data-layer step: **Phase 4 Firestore push/pull** (Phase 2 DTOs already exist as Phase 0 bonus work). Replace `NoopSyncService` with a real `FirestoreSyncService`, add a `MilestoneRepository` (the one gap in Phase 0), and add the Cloud Function for account-deletion cascade.
