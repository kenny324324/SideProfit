# Launch Manual Checklist — Kenny only

**Launch target:** ~2026-06-02 (next week).
**State of code:** Phase 4 (Firestore sync) DONE, Step 6 (cascade-delete Cloud Function) source committed, splash-style auth transition wired, SeedData removed. Everything below is something only you can do.

---

## 1. Pre-flight on your machine (do once)

```bash
# from repo root
cd Functions && npm install && cd -

# Firebase CLI (if not installed)
npm install -g firebase-tools
firebase login
firebase use sideprofit-dev  # or --add if first time
```

---

## 2. Deploy security rules + Cloud Function to `sideprofit-dev`

**Required before any real-device sync test will succeed** — Firestore is currently in test mode (or rejecting writes if you locked it down), and the cascade-delete function isn't running yet.

```bash
firebase deploy --only firestore:rules,functions
```

Verify after deploy:

- Firebase Console → Firestore → Rules — should match what's in `firestore.rules`.
- Firebase Console → Functions — `cascadeDeleteUser` should be listed, region `asia-east1`.

---

## 3. Dogfood the whole flow on a real device

Delete the app from your iPhone first so the local SwiftData store starts empty (SeedData is gone, but old demo rows from previous installs may still be there).

1. Cold launch → AuthView appears.
2. Tap Apple sign-in → splash overlay fades over the transition → MainTabView appears.
3. Auto-sync runs in the background (status pill in `設定 → 雲端同步` should show 「上次同步 just now」). Since cloud is empty for this uid, nothing pulls down.
4. Create a project + add an expense + add a time log + add one shared expense (CategoryItem) + reach break-even on the project so a Milestone fires.
5. Tap **設定 → 雲端同步 → 立即同步**.
6. Open Firebase Console → Firestore → check the 5 collections (`projects`, `transactions`, `timeLogs`, `categoryItems`, `milestones`). Each should have your docs with `ownerUid == <your uid>`.
7. Sign out from Settings → splash overlay fades → AuthView.
8. Sign in again with the same Apple account → splash fades → MainTabView shows the data you created (auto-sync pulled it back from Firestore).
9. **Delete account** → splash fades → AuthView. Firebase Console:
   - Authentication → Users — your account should be gone.
   - Firestore → users/{uid}/deletionRequests — the request doc shows up briefly, then disappears once the function runs.
   - Firestore → projects / transactions / … — your docs should all be gone (give it 10s for the function to finish).

If any step fails:
- Function logs: `firebase functions:log`
- Sync errors: shown in 「立即同步」row as red 「同步失敗」.

---

## 4. Before App Store submission

These are blocking for launch, in rough order.

### 4a. Bundle ID swap

- [ ] Apple Developer Portal: register the real bundle ID (e.g. `com.sideprofit.app`).
- [ ] Apple Developer Portal: create a provisioning profile for the new ID (and Sign in with Apple capability).
- [ ] Xcode: change target → Signing & Capabilities → Bundle Identifier.
- [ ] Firebase Console (`sideprofit-dev`): Project Settings → iOS apps → register the new bundle ID → download new `GoogleService-Info.plist`.
- [ ] Replace `DevCal/DevCal/GoogleService-Info.plist` with the new one.
- [ ] Test on device once with the new bundle ID before continuing.

### 4b. (Recommended) Spin up `sideprofit-prod`

We've been writing to `sideprofit-dev` throughout dev + dogfood. App Store version should point at a separate prod project so dev experiments don't pollute real-user data.

- [ ] Firebase Console: create new project `sideprofit-prod`, region `asia-east1`.
- [ ] Enable Authentication → Sign in with Apple.
- [ ] Register iOS app with the real bundle ID → download `GoogleService-Info-prod.plist`.
- [ ] Decide how you want to switch between dev / prod:
  - Cheapest: only swap the plist file at submission time, leave the rest of the code alone.
  - Cleaner (future v1.1): add an Xcode build configuration that selects the plist via `Configuration.storekit`-style.
- [ ] Deploy rules + functions to `sideprofit-prod`:
  ```bash
  firebase use sideprofit-prod
  firebase deploy --only firestore:rules,functions
  firebase use sideprofit-dev  # switch back
  ```

### 4c. App Store Connect entry

- [ ] Create app entry, link to the bundle ID.
- [ ] Upload screenshots (you'll need to take these manually — Share Cards V1 isn't done, so use real-device captures).
- [ ] App description in EN + 繁中 (minimum). Pull positioning from `Files/ASO_SideProfit_Metadata_2026-05-21.md`.
- [ ] Privacy policy URL + support URL (host on `sideprofit.com` or similar).
- [ ] App Privacy nutrition labels — declare what we collect (Apple ID / email / project + transaction data) and how (linked to identity, used for app functionality).
- [ ] **Account-deletion contact** field is mandatory; the in-app delete flow satisfies the technical requirement, but you also have to provide a contact method.

### 4d. (Optional) Skip StoreKit for v1, free launch

`Entitlements.swift` is a 57-LOC UserDefaults mock — everything is "free" today. You can ship like this and add real subscriptions in v1.1. The Paywall UI is a 410-LOC dead end without it.

If you want IAP at launch:
- [ ] App Store Connect → Subscriptions group, create product IDs.
- [ ] Add a `Configuration.storekit` for sandbox testing.
- [ ] Wire `Product.purchase()` + `Product.SubscriptionInfo.Status` into `Entitlements.swift`.
- [ ] Mirror subscription status to `subscriptionStatus/{uid}` (the path security rules + Cloud Function already account for).

This is the largest pre-launch task by far. Recommended: free launch, IAP in v1.1.

---

## 5. Things I can do in the next session if you want

- Real-device verification of sync push/pull (you'd need to push the deploy first).
- StoreKit wire-up if you decide v1 has IAP.
- Paywall redesign per [[project-devcal-dogfood-2026-05-25]].
- Share Cards V1 (3 templates).
- SWDateExtension Locale refactor (so JA/KO users don't see 繁中 relative time).
- Account-deletion contact page (static HTML you'd host).

I'll work through whatever you point me at — just tell me what to do next.
