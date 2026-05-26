# Firebase Setup Checklist

Project: SideProfit (DevCal Xcode target)
Strategy: UI is built local-first using SwiftData. Firebase is integrated **after** the UI is approved. This file collects every Firebase-related setup item discovered while building the UI, so the integration pass is mechanical.

Last updated: 2026-05-26 (Phase 1 fully done — code + SDK + Console all live in `sideprofit-dev`, verified end-to-end on device)

## 0. Firebase Console — Project Bootstrap

- [x] Create Firebase project named `sideprofit-dev`. *(Phase 1 — done 2026-05-26. Dev only; `sideprofit-prod` to be created before App Store submission.)*
- [ ] Decide if separate dev + prod Firebase projects are needed. *(Phase 1: dev created; prod deferred until launch readiness.)*
- [x] Register an iOS app with bundle ID `com.kenny.DevCal`. *(Phase 1 — done 2026-05-26. Final SideProfit bundle ID swap deferred until App Store Connect setup.)*
- [x] Download `GoogleService-Info.plist` → `DevCal/DevCal/`. Already gitignored at `.gitignore:55`. *(Phase 1 — done 2026-05-26.)*
- [x] Add Firebase iOS SDK via Swift Package Manager — **only `FirebaseAuth`** for Phase 1 (Firestore / Crashlytics / Analytics / RemoteConfig defer to their own phases). *(Phase 1 — done 2026-05-26: firebase-ios-sdk 12.13.0.)*
- [x] In `DevCalApp.swift`, call `FirebaseApp.configure()` inside an `init()` block before any view is created. *(Phase 1 — done 2026-05-26; runs before `AuthService` is constructed.)*
- [ ] Enable App Check (DeviceCheck on iOS) to block server abuse from non-app clients.

## 1. Firebase Auth

Triggered by: the mock Auth screen in `Features/Auth/`.

- [x] Enable **Sign in with Apple** in Firebase Console → Authentication → Sign-in method. *(Phase 1 — done 2026-05-26.)*
  - [x] App's `Sign in with Apple` capability enabled in Xcode → Signing & Capabilities. *(Done — Xcode auto-created `DevCal.entitlements`, synced App ID capability in Apple Dev Portal, regenerated provisioning profile.)*
  - [x] ~~Service ID + private key registered in Apple Developer Portal, then uploaded to Firebase.~~ *(NOT needed for iOS-only native flow. Firebase verifies the Apple identity token using the app's bundle ID, not the Service ID. Service ID + .p8 only required when adding web / Android Sign in with Apple later.)*
- [x] ~~Enable **Google Sign-In**~~. *Out of scope per Phase 1 decision (Apple-only mandatory auth). Revisit post-MVP if a real need surfaces.*
- [x] ~~Enable **Email link (passwordless)** or Email/Password~~. *Out of scope per Phase 1 decision (Apple-only). No email path in MVP.*
- [x] Replace `MockAuthService` in `Core/Services/AuthService.swift`. *(Phase 1 — done 2026-05-26.)* Implemented as a **facade** (concrete `AuthService` keeps its public surface; internals now talk to FirebaseAuth) per Codex audit recommendation — faster than introducing a fresh `AuthServicing` protocol.
- [x] Implement Apple credential exchange. *(Phase 1 — done 2026-05-26.)* `signInWithApple()` uses `ASAuthorizationAppleIDProvider` + SHA-256 nonce + `OAuthProvider.appleCredential(...)` → `Auth.auth().signIn(with:)`. Google path explicitly skipped.
- [x] Account deletion flow — **Phase 1 partial: local + Auth only.** `Auth.currentUser.delete()` + repository-driven local wipe enqueues `isDeleted = true` tombstones into `NoopSyncService` so Phase 4 sync will issue Firestore deletes. The Cloud Function cascade for App Store guideline 5.1.1(v) lands in **Phase 4** (no remote data to cascade until then, so MVP still complies).
- [x] Decide on anonymous-auth-first vs. mandatory-auth. *(Decided 2026-05-26: **mandatory, Apple-only.** Onboarding lands the user on `AuthView` and there's no signed-out path into `MainTabView`.)*

## 2. Firestore Database

Triggered by: every SwiftData model in `Core/Models/`.

- [ ] Create Firestore database in **Native mode**, region `asia-east1` (Taiwan) or `nam5` multi-region depending on user base.
- [ ] Collections to create (mirroring SwiftData models):
  - [ ] `users/{userId}` — UserProfile doc (email, displayName, preferredLanguage, defaultCurrency, createdAt).
  - [ ] `users/{userId}/projects/{projectId}` — Project docs.
  - [ ] `users/{userId}/projects/{projectId}/transactions/{transactionId}` — Transaction docs.
  - [ ] `users/{userId}/projects/{projectId}/timeLogs/{timeLogId}` — TimeLog docs.
  - [ ] `users/{userId}/projects/{projectId}/milestones/{milestoneId}` — Milestone docs.
  - [ ] `users/{userId}/subscription` — single doc storing entitlement state (mirrored from StoreKit; updated by App Store Server Notifications via Cloud Function).
- [ ] Decide between sub-collection layout (above) vs. flat collections with `userId` field on every doc. Sub-collections are simpler for security rules.
- [ ] Write Firestore Security Rules: authenticated users can read/write only under their own `users/{userId}` path. No public read.
- [ ] Decide on conflict resolution. MVP planning doc says offline conflict resolution is **out of scope** — last-write-wins via Firestore's built-in offline persistence is acceptable.
- [ ] Implement `FirestoreSyncService` that mirrors SwiftData writes to Firestore and pulls remote changes on launch.

## 3. Cloud Functions

- [ ] Account deletion Cloud Function (cascades delete of all `users/{userId}/**` docs after Auth user delete).
- [ ] StoreKit 2 App Store Server Notification webhook → update `users/{userId}/subscription` doc with current entitlement.
- [ ] Optional: milestone-detection background function (when a transaction is added, recompute and write milestone docs). MVP can do this client-side instead.

## 4. Storage (Optional)

- [ ] If user-uploaded receipt images are added post-MVP, configure Firebase Storage with per-user folder rules. Not required for MVP.

## 5. Crashlytics + Analytics

- [ ] Verify Crashlytics symbol upload Run Script Build Phase is added.
- [ ] Force a test crash in DEBUG to confirm the dashboard receives crashes.
- [ ] Define custom Analytics events:
  - `onboarding_completed`
  - `project_created`
  - `transaction_added` (with `type: income|expense`)
  - `time_log_added`
  - `milestone_reached` (with `milestone_type`)
  - `paywall_viewed` (with `trigger: second_project|time_cost|share_template|export`)
  - `subscription_started` (with `plan: monthly|yearly`)
  - `share_card_exported`
- [ ] Disable Analytics in DEBUG builds to keep dev data clean.

## 6. Remote Config

- [ ] Used by the `whatsnew` skill: `whats_new_v{version}` JSON payload for in-app announcements.
- [ ] Optional: feature flags for paywall A/B (yearly-default vs. monthly-default, different prices for regions).

## 7. Subscription / StoreKit 2 Backend Glue

- [ ] StoreKit 2 transactions written client-side to `users/{userId}/subscription` for fast UI checks.
- [ ] App Store Server Notifications V2 endpoint as Cloud Function — source of truth for renewals, refunds, billing retries.
- [ ] Define product IDs in App Store Connect:
  - `com.sideprofit.pro.monthly` — US$4.99/mo, NT$150/mo
  - `com.sideprofit.pro.yearly` — US$39.99/yr, NT$1,190/yr
- [ ] StoreKit Configuration file (`.storekit`) for local sandbox testing — add to repo, not built into release.

## 8. App Check + Security

- [ ] Enable App Check with DeviceCheck provider in Firebase Console.
- [ ] Enforce App Check on Firestore + Cloud Functions after testing.
- [ ] Rotate / restrict Firebase API key in Google Cloud Console (HTTP referrer + bundle ID restrictions).

## 9. Privacy / Legal

- [ ] Privacy Policy URL — must mention Firebase data collection (Analytics, Crashlytics, Auth).
- [ ] Terms of Use URL.
- [ ] App Privacy questionnaire in App Store Connect:
  - Identifiers: user ID (Firebase Auth)
  - Usage Data: product interactions (Analytics)
  - Diagnostics: crash data (Crashlytics)
  - Financial Info: user-entered (Firestore) — linked to user, not used for tracking.
- [ ] Sign in with Apple "Hide My Email" relay address support.

## Items Discovered During UI Build

This section grows as Phase 1 UI surfaces new requirements. Each item should reference the file/feature that surfaced it.

- Phase 1 (2026-05-26): no `MilestoneRepository` exists yet, so `AuthService.purgeLocalData(_:)` doesn't enqueue tombstones for Milestone documents — they cascade-delete with their parent project locally but won't sync as tombstones. Add a `MilestoneRepository` before Phase 4 push/pull so milestone deletions reach Firestore.
