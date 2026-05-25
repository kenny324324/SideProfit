# MVP Planning and ShipSwift Map

Last updated: 2026-05-19

Product: **DevCal** (App Store: SideProfit)

This document specifies V1 implementation. For product rationale, see [PRD.md](PRD.md).

---

## V1 Decisions (locked 2026-05-19)

| Decision | Value | Rationale |
| --- | --- | --- |
| Architecture | SwiftUI + MVVM, feature-based folders | Existing scaffold matches |
| Backend | Firebase (Auth + Firestore + Crashlytics + Remote Config) | Decided 2026-05-12; cross-device sync from day 1 |
| Local persistence | SwiftData (already in code) | Local-first cache; Firestore as remote of record once integrated |
| Subscription | StoreKit 2 | Standard for iOS |
| UI library | ShipSwift (SWPackage) | Already wired into project |
| Charts | ShipSwift SWChart + Swift Charts where needed | Existing code uses Swift Charts in places |
| Localization | Xcode String Catalog (Localizable.xcstrings) | Already in code |
| Auth | Required (cloud sync from day 1) | Sign in with Apple primary |
| Net formula | Revenue − Expenses (cash only) | Time NOT included in Net |
| Hero metric | Two-stage progress (Break-even → Goal) | Auto-derived target, then user-set goal |
| Time tracking | Manual hours/rate entry | No timer in V1 |
| Home screen | Project List | Multi-project users primary archetype |
| Target dev time | 6–10 weeks to TestFlight | From locked spec |

---

## Terminology

To prevent UI/copy drift:

| 繁中 | EN | Notes |
| --- | --- | --- |
| 收入 | Income | Entry type (one of two) |
| 支出 | Expense | Entry type (one of two) |
| 累積收入 | Revenue | Sum of income on a project |
| 累積支出 | Total Expenses | Sum of expenses on a project |
| 淨利 | Net | Revenue − Total Expenses (cash only) |
| 回本 | Break-even | First moment Revenue ≥ Total Expenses |
| 目標 | Goal | User-set lifetime revenue target, post break-even |
| 時間成本 | Time Cost | **Feature name**; estimated labor value (hours × rate) |
| 時間紀錄 | Time Log | A single time entry |
| 實質時薪 | Hourly Rate | Net ÷ total hours |

**Wording rules (繁中):**

- **Do NOT use 「交易」** anywhere in user-facing copy. The word is too clinical for the indie-dev mental model.
- Entries are either 「支出」 or 「收入」; never call them collectively 「交易」.
- For section headings that group both types, use 「最近紀錄」/「近期紀錄」/「項目」 — never 「最近交易」.
- 「成本」 is fine in conceptual phrases (「回本」, 「時間成本」, 「現金成本」). It is **not** a synonym for 「支出」 in UI copy.
- The Swift type name `Transaction` may remain (internal/technical), but no Chinese-facing string should surface the word 「交易」.

---

## V1 Screens

V1 has **5 product screens** plus supporting layers.

### 1. Project List (home)

Tab: Projects (primary tab).

Each row shows:

- Project name
- Status pill (Planned / Building / Live / Paused)
- Two-stage progress bar with label (`Break-even 23%` or `Goal 47%`)
- This month: Net (+/−)
- All time: Net (+/−)

Empty state: prompt to create first project.

ShipSwift: `SWListPageTemplate`, `SWAddSheet`.

### 2. Project Detail (the core)

The entire product value is on this one scrollable screen. Sections from top to bottom:

1. **Hero — Two-stage progress**
   - Stage 1 (pre break-even): SWRingChart showing Break-even %, with caption `$X of $Y`
   - Stage 2.5 (just reached, no goal set yet): celebration state with **Set your goal →** CTA
   - Stage 2 (post break-even with goal): SWRingChart showing Goal %, plus deadline projection if set

2. **Numbers row** — Revenue / Expenses / Net / Hourly
   - Hourly is Pro-gated (greyed for Free)

3. **Monthly Trend** — line/bar chart of income vs expense by month

4. **Expense Breakdown** — donut chart by category

5. **Recent entries (近期紀錄)** — latest 5–10 income + expense rows mixed; "See all →" opens full list. **Chinese heading must not be 「近期交易」**.

6. **Time Log (Pro)** — total hours, last entry, real hourly rate; "See all →" opens full list

7. **(Future)** AI Summary block

### 3. New / Edit Project (sheet)

Fields:

- Name
- Currency
- Status
- Launch date (optional)
- Color

**No `breakEvenTarget` field.** The break-even target is derived automatically from cumulative expenses. The goal amount is set only after break-even is reached, via the goal-setting flow.

### 4. New Entry (sheet) — 新增支出 / 新增收入

The sheet title flips based on the type toggle:

- Expense selected → title 「新增支出」 / "Add Expense"
- Income selected → title 「新增收入」 / "Add Income"

Fields:

- Type toggle (支出 / 收入) — SWTabButton, top of sheet
- Amount
- Category (only shown for 支出)
- Date
- Note

Expense categories (V1): Server, API, App Store Fee, Google Play Fee, Domain, Design, Ads, Outsourcing, AI Tools, Testing Devices, Development Tools, Other.

**Do not** name this sheet 「新增交易」 or "Add Transaction" in user-facing strings.

### 5. New Time Log (sheet)

Fields:

- Hours (SWStepper)
- Hourly rate (SWStepper, persists last used per project)
- Date
- Note

### Goal-Setting Flow (post break-even)

Triggered when `breakeven_reached_at` first becomes non-null on a project.

1. Project Detail hero switches to celebration state
2. Tapping CTA opens a sheet:
   - Goal amount (required)
   - Deadline toggle (default off); if on, date picker
3. On save, Project gets `goal_amount` (+ optional `goal_deadline`); hero switches to Stage 2

### Supporting layers

- **Onboarding** — 3–4 pages explaining the two-stage progress concept. Skippable. (`SWOnboardingView`)
- **Auth** — Sign in with Apple primary; email link secondary. Required. (Custom UI; Firebase Auth)
- **Settings** — Account / Language / Currency / Subscription / Export / Legal / Delete Account. (`SWSettingTemplate`)
- **Paywall** — StoreKit 2, monthly + yearly. Triggered at gates (see PRD). (`SWPaywallView`, `SWStoreManager`)

### Pro-only extras (kept from existing code)

- **Insights tab** — cross-project rollup: total net by project, total hours by project. Pro-gated.
- **Premium share card templates** — basic 1 template free; the rest Pro.

---

## Data Model

### UserProfile
- id, email, display_name, preferred_language, default_currency, created_at, updated_at

### Project
- id, user_id, name, description, currency, status, launch_date, color
- **`breakeven_reached_at`** (timestamp, nullable, auto-stamped)
- **`goal_amount`** (decimal, nullable, set by user post break-even)
- **`goal_deadline`** (date, nullable)
- sort_index (for drag-to-reorder)
- created_at, updated_at, archived_at

**Removed from existing code:** `breakEvenTarget`. The Stage 1 target is computed (`totalExpenses`), not stored. Stage 2 target lives in `goal_amount`.

### Transaction
- id, user_id, project_id, type (income/expense), category, amount, note, date, created_at, updated_at

### TimeLog
- id, user_id, project_id, hours, hourly_rate, note, date, created_at, updated_at

### SubscriptionStatus
- user_id, entitlement, is_active, source, expires_at, updated_at

### Milestones?

**No separate Milestone table in V1.** The single meaningful milestone (break-even) is computed from `Project.breakeven_reached_at`. Goal % milestones (25/50/75/100) are derived. The existing `MilestoneType` enum / `MilestonesView` / `Milestone @Model` should be **deprecated** — kept compiling for now if convenient, but new development does not extend them.

### Break-even computation rule

- Computed at write time, not as a query.
- On every Transaction save (income or expense):
  - If `breakeven_reached_at` is nil and cumulative income ≥ cumulative expense, stamp `breakeven_reached_at` to the date of the triggering transaction.
- Once set, **never** clear it (even if subsequent expenses make Net negative again — that's just normal life cycle, not "un-broke-even").

---

## ShipSwift Modules Used in V1

| Area | Module | Status |
| --- | --- | --- |
| Tabs | `SWRootTabView` | use |
| Project list | `SWListPageTemplate` | use |
| Add sheets | `SWAddSheet` | use |
| Numeric input | `SWStepper` | use |
| Income/expense switch | `SWTabButton` | use |
| Ring progress (hero) | `SWRingChart` | use |
| Monthly trend | `SWLineChart` or `SWBarChart` | use |
| Expense breakdown | `SWDonutChart` | use |
| Onboarding | `SWOnboardingView` | already copied |
| Settings | `SWSettingTemplate` | use |
| Paywall | `SWPaywallView`, `SWStoreManager` | use |
| Loading | `SWLoading` | use |
| Alerts | `SWAlert` | use |
| Utilities | `SWUtil` | already copied |

**Not used in V1:** `SWCamera`, `SWChat`, `SWSubjectLifting`, `SWTikTokTracking`, `SWAuth` (using Firebase Auth instead), `SWActivityHeatmap` (post-V1).

---

## Backend Plan

Firebase responsibilities:

- **Auth** — Firebase Auth: Sign in with Apple primary, email link secondary
- **Firestore** — per-user collections: `users/{uid}/projects/...`, `users/{uid}/transactions/...`, `users/{uid}/timeLogs/...`, `users/{uid}/subscriptionStatus/current`
- **Firestore Security Rules** — restrict every read/write to `request.auth.uid == userId`
- **Crashlytics** — production crash reporting
- **Remote Config** — paywall A/B, "what's new" banner, feature flags
- **Account deletion** — Cloud Function cascades subcollections (App Store 5.1.1(v))

V1 sync model:

- SwiftData remains the local store (already implemented).
- On every local write, mirror to Firestore.
- On launch and pull-to-refresh, reconcile from Firestore.
- No offline editing or conflict resolution in V1 (last-write-wins is acceptable for solo single-device-most-of-the-time use; Firestore's own offline cache buffers short outages).

Cloud sync is part of **Free**, not Pro.

Setup items tracked in [Firebase_Setup_Checklist.md](Firebase_Setup_Checklist.md). Strategy is UI-first: do not integrate the Firebase SDK until the UI is approved.

---

## Localization

Xcode String Catalog (`Localizable.xcstrings`) — already in code.

V1: English, Traditional Chinese, Japanese, Korean.

Audit pass needed: remove **「交易」** from user-facing strings entirely; use 「支出」 and 「收入」 as the two entry types. 「成本」 stays where conceptually correct (回本, 時間成本, etc.).

Localize: onboarding, auth, empty states, dashboard labels, transaction categories, emotional copy, paywall, settings, errors, share card text, App Store metadata.

---

## Folder Structure (current, kept)

```
DevCal/
  App/
  Core/
    Models/
    Services/
    Localization/
    Theme/
  Features/
    Onboarding/
    Auth/
    Projects/
    Dashboard/       # = Project Detail in spec terminology
    Transactions/
    TimeCost/
    Analytics/       # Per-project + Insights
    Milestones/      # Deprecated; do not extend
    Settings/
    Paywall/
    ShareCards/      # to add when share cards are built
  ShipSwift/
    SWUtil/
    SWComponent/
    SWChart/
    SWModule/
    SWTemplate/
```

Note: the existing `Dashboard/` folder is what this spec calls **Project Detail**. Keep the folder name to avoid churning the file tree.

---

## Development Order (from current state)

The UI scaffold already exists. The work below is the gap between scaffold and V1 spec.

1. **Model migration** — Add `breakeven_reached_at`, `goal_amount`, `goal_deadline` to `Project`. Remove or stop using `breakEvenTarget`. Update derived computed properties (`breakEvenProgress`, `isBreakEvenReached`) to use the new two-stage logic.
2. **Goal-setting flow** — New sheet for setting `goal_amount` / `goal_deadline`; trigger from celebration state.
3. **Hero rewrite** — `BreakEvenRing` becomes a two-state component: Stage 1 (auto target = totalExpenses) vs Stage 2 (target = goal_amount). Plus the 2.5 celebration state.
4. **Project list row** — Update `ProjectCard` to show the two-stage progress label + this-month Net + all-time Net.
5. **Wording audit (繁中)** — `Localizable.xcstrings` pass: remove **「交易」** from all user-facing strings. Replace 「新增交易」 → 「新增支出」/「新增收入」 (split by context), 「最近交易」 → 「最近紀錄」, etc. 「成本」 stays as a conceptual word; 「時間成本」 stays as feature name.
6. **Deprecate Milestone surface** — Hide `MilestonesView` from main nav; keep enum/model for now to avoid SwiftData migration; do not extend.
7. **Firebase integration** — Firestore schema + Security Rules + Auth wiring; replace mock `AuthService` and `Entitlements`. Driven by [Firebase_Setup_Checklist.md](Firebase_Setup_Checklist.md).
8. **StoreKit 2 products** — Real entitlement check; replace local toggle.
9. **Share Cards V1** — One template (Break-even reached / Goal milestone / Monthly revenue); ImageRenderer export.
10. **Localization pass** — JA + KO; review EN + 繁中 wording with new terminology.
11. **ASO assets** — Screenshots, App Store copy, metadata.

---

## V1 Definition of Done

TestFlight-ready when:

- User can sign in with Apple (real Firebase Auth)
- User can create projects (Free: 1; Pro: unlimited)
- User can add income, expenses, and time logs
- Project Detail shows the two-stage progress correctly:
  - Stage 1 progress = revenue / expenses
  - Break-even detection stamps `breakeven_reached_at`
  - Celebration state appears
  - User can set goal amount + optional deadline
  - Stage 2 progress = revenue / goal
- Monthly trend and expense breakdown charts render with real data
- Data persists and syncs across reinstall / second device (Firestore)
- Free/Pro limits enforced via Entitlements
- Paywall works with sandbox StoreKit products
- English + Traditional Chinese fully localized; **no occurrence of 「交易」 in user-facing strings**
- App Store screenshot flow is reproducible in-app
