# DevCal Architecture Audit

Date: 2026-05-26
Scope: Firebase Auth / Firestore integration readiness, layer separation, local-first data architecture.

**Status update (2026-05-26 PM): Phase 0 complete.** DTOs / Repositories / Sync no-op shell landed; `CategoryItem.weightsByProjectId` keyed map + `Transaction.deterministicID` migrated; all six priority views refactored; Swift Testing coverage added. Phase 1+ (Firebase Auth → Firestore push/pull → Settings hookup) is still pending. See [[project-devcal-data-layer]] for the new shape.

## Executive Summary

Current state: the project is in a reasonable UI-first SwiftUI + SwiftData shape, and it already has a clear top-level folder split:

- `App/`: app shell and routing
- `Features/`: screen-level UI by feature
- `Core/Models/`: SwiftData models and domain calculations
- `Core/Services/`: app-level services
- `Core/Theme` and `Core/UX`: UI system and shared UX utilities

Overall verdict: clean enough to continue, but not clean enough to wire Firebase directly into the current View layer.

The main architectural risk is that SwiftData writes are currently scattered through Views. If Firebase mirroring is added by inserting Firestore calls into those same Views, the app will quickly become hard to reason about. Before connecting Firestore, create a small data access layer around local writes and sync.

Suggested readiness score:

- UI structure: 8/10
- Domain model clarity: 7/10
- Firebase Auth readiness: 6/10
- Firestore sync readiness: 4/10
- Test coverage for data rules: 1/10
- Overall Firebase readiness: 5.5/10

## Current Architecture Map

### App Layer

`DevCal/DevCal/DevCalApp.swift`

- Creates `ModelContainer`.
- Injects `AuthService`, `Entitlements`, `ExchangeRateService`, and `AppReviewPrompter` into the SwiftUI environment.
- Seeds demo data on first launch.
- Runs `SubscriptionScheduler.runDueCheck(...)` on launch and scene activation.
- Refreshes FX rates on launch and active scene transitions.

`DevCal/DevCal/App/RootView.swift`

- Routes between `AuthView` and `MainTabView` from `AuthService.isSignedIn`.

`DevCal/DevCal/App/MainTabView.swift`

- Owns the signed-in shell: Projects, Insights, Settings.

Assessment: this app shell is simple and workable. Firebase initialization can fit here, but do not let `DevCalApp` become the owner of every sync rule.

### Feature Layer

Main feature folders:

- `Features/Auth`
- `Features/Projects`
- `Features/Dashboard`
- `Features/Transactions`
- `Features/TimeCost`
- `Features/Analytics`
- `Features/Settings`
- `Features/Paywall`
- `Features/Milestones`

There are 57 SwiftUI View structs in the app. The feature grouping is understandable and matches the planning doc.

Assessment: feature organization is clean at the folder level. The weak point is inside feature files: several screens contain persistence, validation, object construction, and UI behavior together.

### Model Layer

SwiftData models:

- `Project`
- `Transaction`
- `TimeLog`
- `CategoryItem`
- `Milestone`

Model strengths:

- Stable raw string enum storage is already used for future Firestore serialization.
- `Project` owns meaningful domain calculations: income, expense, net profit, progress, break-even stamping.
- `Transaction` and `TimeLog` keep original currency and expose converted display helpers.
- `CategoryItem` captures recurring billing and shared allocation rules.

Model risks:

- SwiftData `@Model` classes are also being used as domain entities and UI-facing objects. This is acceptable for local-only MVP work, but Firestore DTOs should not directly depend on SwiftData model behavior.
- Domain methods accept `ExchangeRateService`, which couples model calculations to a concrete service class. It works, but tests and future sync code will be cleaner if calculation dependencies can be passed as a protocol or pure rate table.
- `CategoryItem.weights` is index-matched to `projects`. That is fragile for remote sync because Firestore document ordering and relationship hydration can change. Prefer storing weights keyed by project id in the remote DTO.

### Service Layer

Existing services:

- `AuthService`: mock auth state persisted in `UserDefaults`
- `Entitlements`: mock subscription plan persisted in `UserDefaults`
- `ExchangeRateService`: observable singleton, network fetch, cache, conversion
- `SubscriptionScheduler`: generates due recurring transactions from `CategoryItem`
- `SeedData`: first-run sample data

Service strengths:

- Auth and entitlement concerns are already not embedded directly in Views.
- Exchange rate logic has a single source of truth.
- Recurring subscription generation is centralized instead of duplicated in UI.

Service risks:

- `AuthService` comment says it should conform to `AuthServicing`, but no protocol exists yet.
- No `FirestoreSyncService` exists yet, despite planning docs requiring local write mirroring.
- No repository / command layer exists around SwiftData writes.
- Most `context.save()` calls use `try?`, so write failures are silently ignored.

## Firebase Readiness

### Auth

Current state:

- `AuthView` depends on `AuthService` from Environment.
- `RootView` switches on `auth.isSignedIn`.
- `SettingsView` uses `auth.account` and calls `auth.signOut()`.
- `AuthService` currently stores a mock account in `UserDefaults`.

Good:

- UI already routes through one service.
- Replacing mock sign-in with Firebase is straightforward if the public API stays stable.

Needs work before Firebase:

- Add an `AuthServicing` protocol or keep the concrete `AuthService` as a facade that delegates to Firebase.
- Track Firebase auth listener state instead of one-time `UserDefaults` restore.
- Decide anonymous auth vs mandatory auth before adding Firestore paths.
- Add account deletion flow that calls backend deletion, not just `signOut()`.

Recommended shape:

```swift
@MainActor
protocol AuthServicing {
    var account: AccountSummary? { get }
    var isSignedIn: Bool { get }
    func start()
    func signInWithApple() async throws
    func signInWithGoogle() async throws
    func signInWithEmail(_ email: String) async throws
    func signOut() throws
    func deleteAccount() async throws
}
```

### Firestore / Sync

Current plan from docs:

- SwiftData remains local store.
- Every local write mirrors to Firestore.
- Launch / pull-to-refresh reconciles remote data.
- MVP accepts last-write-wins.

Current code state:

- SwiftData is directly used from many Views via `@Environment(\.modelContext)`.
- `@Query` is used directly in top-level views.
- There are 54 SwiftData read/write/save-related hits across the app.
- No sync boundary exists.

Main risk:

If Firebase is added directly inside screens like `AddTransactionView`, `AddProjectView`, `SharedExpenseEditView`, and `ProjectListView`, every save/delete flow will need custom local write, remote write, error handling, retry, loading state, and conflict behavior. That will duplicate logic and make partial sync bugs likely.

Recommended minimum before Firestore:

- Add repository/command services for write flows.
- Keep Views responsible for form state and user intent only.
- Let repositories write SwiftData and emit sync operations.
- Let `FirestoreSyncService` own remote push/pull.

Recommended first services:

- `ProjectRepository`
- `TransactionRepository`
- `TimeLogRepository`
- `CategoryItemRepository`
- `SyncQueue` or `PendingSyncOperationStore`
- `FirestoreSyncService`

## Most Important Findings

### 1. High Risk: Persistence Writes Are Scattered Through Views

Examples:

- `Features/Projects/AddProjectView.swift`: creates/edits `Project`, fetches current sort index, saves context.
- `Features/Transactions/AddTransactionView.swift`: creates transactions, creates recurring `CategoryItem`, creates platform fee transaction, stamps break-even, saves context.
- `Features/TimeCost/AddTimeLogView.swift`: creates/edits/deletes `TimeLog`.
- `Features/Projects/SetGoalView.swift`: mutates goal fields directly.
- `Features/Settings/SharedExpenseEditView.swift`: creates/edits/deletes shared `CategoryItem`, then runs scheduler.
- `Features/Projects/ProjectListView.swift`: deletes projects and handles reorder writes.

Impact:

- Firestore mirroring has no single interception point.
- Save errors are hard to surface consistently.
- Unit testing write rules requires rendering or instantiating Views.

Recommendation:

Before Firestore, move write operations into feature repositories or use-case services. Start with transactions because it has the most business logic.

### 2. High Risk: `try? context.save()` Silences Data Failures

Most save/delete flows ignore errors.

Impact:

- A local write can fail while the UI dismisses as if it succeeded.
- Firestore sync will make this worse because local and remote state can diverge without visible errors.

Recommendation:

Repository methods should be `async throws` or `throws`. Views can show a simple error alert, but the write layer must not swallow failures.

### 3. High Risk: No Firestore DTO Boundary

Current models are SwiftData `@Model` classes. There are no Firestore DTOs or mapping methods.

Impact:

- Directly encoding SwiftData models into Firestore will leak local persistence details into the remote schema.
- Relationships such as `Project.transactions`, `CategoryItem.projects`, and external image data need explicit serialization choices.

Recommendation:

Create plain Codable remote DTOs:

- `ProjectDocument`
- `TransactionDocument`
- `TimeLogDocument`
- `CategoryItemDocument`
- `MilestoneDocument`

Map explicitly between SwiftData models and Firestore docs.

### 4. Medium Risk: Auth Is a Concrete Mock Service

`AuthService` is environment-injected, which is good. But it is not protocol-backed yet and the Firebase checklist mentions a protocol that does not exist.

Impact:

- Firebase can still be wired, but tests and previews will become harder once Firebase SDK code enters the concrete service.

Recommendation:

Either:

- make `AuthService` a stable app facade and inject an internal provider, or
- introduce `AuthServicing` before Firebase.

For speed this afternoon, use the facade approach:

```swift
@MainActor
@Observable
final class AuthService {
    private let provider: AuthProvider
}
```

### 5. Medium Risk: `CategoryItem.weights` Is Position-Based

`CategoryItem.weights` is index-matched with `projects`.

Impact:

- A remote DTO that stores arrays can drift if project ordering changes.
- Conflict resolution is harder.

Recommendation:

Keep the SwiftData field if migration cost matters, but Firestore should store:

```text
weightsByProjectId: {
  "{projectId}": 1.0
}
```

### 6. Medium Risk: Subscription Scheduler Is Local-Only

`SubscriptionScheduler` generates transactions from due `CategoryItem`s on launch and scene activation.

Impact:

- On multiple devices, both devices may generate the same recurring transaction unless Firestore-level idempotency is designed.
- Current idempotency checks only local SwiftData transactions by `sourceCategoryItemID` and date.

Recommendation:

When Firestore arrives, recurring transaction ids should be deterministic:

```text
{categoryItemId}_{projectId}_{yyyyMMdd}
```

Then Firestore writes can be idempotent with `setData(..., merge: false)` or transaction checks.

### 7. Medium Risk: Tests Do Not Cover Business Rules

`DevCalTests.swift` is still the template test file.

Impact:

- Break-even, recurring generation, currency conversion, shared split, and Firestore mapping can regress quietly.

Minimum tests before Firestore:

- `Project` totals and progress by stage.
- `stampBreakevenIfReached`.
- `CategoryItem.amount(for:)` equal and weighted split.
- `SubscriptionScheduler` idempotency.
- Firestore DTO mapping round trip.

## What Is Already Clean

- Folder-level feature organization is clear.
- App root injection is simple.
- Auth routing is centralized in `RootView`.
- Core models use stable raw string enum values, good for Firestore.
- Exchange rate service is centralized.
- Subscription generation is not spread across multiple screens.
- Product docs already define the Firebase strategy and Firestore collection layout.
- Build currently succeeds for the simulator.

## Recommended Firebase Integration Order

### Phase 0: Do Not Wire Firestore Into Views — **DONE 2026-05-26**

Before adding Firebase calls:

1. Add `Core/Data/Repositories/`. **Done.** ProjectRepository / TransactionRepository / TimeLogRepository / CategoryItemRepository + TransactionUseCase + DataLayerError, all `@MainActor` and `async throws`.
2. Add `Core/Data/DTOs/`. **Done.** ProjectDocument / TransactionDocument / TimeLogDocument / CategoryItemDocument / MilestoneDocument — plain Codable, stable string ids, isDeleted tombstones, updatedAt on every doc.
3. Add `Core/Data/Sync/` (note: chose `Core/Data/Sync` over `Core/Services/Sync` to keep all data-layer code under one root). **Done.** SyncStatus / PendingSyncOperation / FirestoreSyncService.swift (SyncServicing protocol + NoopSyncService placeholder, no Firebase imports).
4. Move write logic out of the busiest Views. **Done for the six named:** `AddTransactionView`, `AddProjectView`, `SharedExpenseEditView`, `SetGoalView`, `ProjectListView`, `AddTimeLogView`. Views now hold form state + intent + an error alert; persistence flows go through the repo.

Bonus: business-rule fixes Codex called out as Firebase pre-reqs also done in Phase 0 — `CategoryItem.weights` → `weightsByProjectId: [String: Double]?`, `Transaction.deterministicID` added and stamped by the scheduler. Swift Testing suite covers project totals/progress, split allocation, scheduler idempotency + deterministic id format, and DTO round-trips.

Suggested folder structure:

```text
DevCal/DevCal/Core/
  Data/
    DTOs/
      ProjectDocument.swift
      TransactionDocument.swift
      TimeLogDocument.swift
      CategoryItemDocument.swift
    Repositories/
      ProjectRepository.swift
      TransactionRepository.swift
      TimeLogRepository.swift
      CategoryItemRepository.swift
    Sync/
      FirestoreSyncService.swift
      PendingSyncOperation.swift
      SyncStatus.swift
```

### Phase 1: Auth — **DONE (code-side) 2026-05-26** (see [Phase_1_Plan_2026-05-26.md](Phase_1_Plan_2026-05-26.md))

1. ~~Add Firebase SDK packages~~. *Manual prereq Kenny does — Phase 1 needs only `FirebaseAuth`.* **Pending on Kenny.**
2. `FirebaseApp.configure()` in `DevCalApp.init()`. **Done** — runs before `AuthService` is constructed via `_auth = State(initialValue: AuthService())`.
3. Convert `AuthService` from mock storage to Firebase listener-backed state. **Done** — facade approach kept; `Auth.auth().addStateDidChangeListener` publishes account state; Sign in with Apple wired through `ASAuthorizationAppleIDProvider` + `OAuthProvider.appleCredential(...)`; Google / Email / Guest paths deleted under the Apple-only decision.
4. `RootView`, `AuthView`, `SettingsView` ripple: `signInWithApple()` and `deleteAccount(...)` now `async throws`, `signOut()` `throws`; views surface failures through the existing `systemAlert` error pattern.
5. **Decisions locked 2026-05-26 PM** (also recorded in plan): Apple-only mandatory auth, no email path, account deletion = local SwiftData wipe via Phase 0 repositories (queues tombstones for Phase 4) + `Auth.currentUser.delete()` — Cloud Function cascade deferred to Phase 4 with Firestore.

### Phase 2: DTOs and Remote Schema

Create Codable document structs before writing any sync code.

Important remote field choices:

- Use stable `id.uuidString`.
- Store all dates as Firestore `Timestamp`.
- Store enum raw values as strings.
- Store original currency codes exactly as local models do.
- Store `updatedAt` on every synced document.
- Store `isDeleted` tombstones or a delete operation queue if offline delete matters.

### Phase 3: Local Write Boundary

Move these first:

1. `AddTransactionView.save()` and `deleteTransaction()`
2. `AddProjectView.save()`
3. `SharedExpenseEditView.save()` and `deleteItem()`
4. `SetGoalView.save()` and `clearGoal()`
5. `ProjectListView.handleMove()` and project delete

Views should call methods like:

```swift
try await transactionRepository.createOneTimeTransaction(...)
try await projectRepository.updateGoal(...)
try await categoryItemRepository.saveSharedItem(...)
```

### Phase 4: Firestore Push/Pull

Add sync after repositories exist.

Recommended MVP behavior:

- Local write succeeds first.
- Repository enqueues a sync operation.
- Sync service pushes pending operations when signed in and network is available.
- Pull remote data on sign-in and app launch.
- Use last-write-wins by `updatedAt`.

### Phase 5: Settings UI Hookup

Replace the fake sync button in `CloudSyncSettingsView.triggerSync()` with `FirestoreSyncService.syncNow()`.

## Specific File-Level Notes

### `DevCalApp.swift`

Good root for:

- `FirebaseApp.configure()`
- app-wide service injection
- initial sync trigger after auth state is ready

Avoid:

- putting Firestore collection logic here
- adding per-model sync code here

### `AuthService.swift`

Good:

- environment-injected
- already centralizes sign-in state

Change:

- replace `UserDefaults` mock restore with Firebase auth listener
- expose errors
- add account deletion API

### `AddTransactionView.swift`

Highest priority refactor before Firestore.

This file currently owns:

- form state
- validation
- transaction creation
- recurring item creation
- scheduler trigger
- platform fee creation
- break-even stamping
- save/delete
- app review prompt triggering

Recommendation:

Extract a `TransactionRepository` or `TransactionUseCase`. Keep fee alert UI in the View, but move object creation and persistence out.

### `SharedExpenseEditView.swift`

Needs special care for Firestore because shared allocation touches multiple projects.

Recommendation:

Remote DTO should not rely on SwiftData relationship ordering. Store selected project ids and weights by id.

### `SubscriptionScheduler.swift`

Good:

- centralized recurring transaction generation
- local idempotency guard exists

Change for Firebase:

- deterministic transaction ids
- remote idempotency
- sync-aware generation rules for multi-device use

### `ExchangeRateService.swift`

Good:

- single service
- cached fallback

Possible improvement:

- introduce a tiny protocol for tests or pass rate table into pure calculations.

## Testing Plan Before Firebase

Add focused Swift Testing tests:

1. `ProjectFinancialTests`
   - total income/expense/net with multiple currencies
   - progress stage one, just reached, stage two
   - break-even stamp only happens once

2. `CategoryItemSplitTests`
   - equal split
   - weighted split
   - project not in allocation returns 0
   - invalid weights fallback behavior

3. `SubscriptionSchedulerTests`
   - creates due transaction
   - catches up multiple billing periods
   - does not duplicate same day/source item
   - stamps break-even

4. `FirestoreMappingTests`
   - SwiftData model to document
   - document to local model
   - optional fields and enum raw values survive round trip

5. `AuthServiceTests`
   - mock provider sign in/out
   - auth listener state changes

## Build / Verification

Commands run:

```sh
xcodebuild -list -project DevCal/DevCal.xcodeproj
xcodebuild -project DevCal/DevCal.xcodeproj -scheme DevCal -destination 'generic/platform=iOS Simulator' build
```

Result:

- Scheme detected: `DevCal`
- Local package dependency detected: `PhosphorSymbols`
- Simulator build result: `BUILD SUCCEEDED`

Note:

- I did not modify app source code for this audit.
- Existing working tree had unrelated modified files before this report was created.

## Bottom Line

You can start Firebase today, but the safe path is:

1. Wire Firebase Auth through the existing `AuthService` boundary.
2. Do not add Firestore calls directly to Views.
3. Add DTOs and repositories first.
4. Move the transaction write flow before implementing sync, because it is currently the most complex and highest-risk path.
5. Add a few business-rule tests around scheduler, split allocation, and break-even before remote sync.

The current architecture is not messy; it is just still UI-first. The main job before Firebase database work is to create one clean data boundary so local SwiftData and remote Firestore do not leak into every screen.
