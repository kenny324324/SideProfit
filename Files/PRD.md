# DevCal — Product Concept

Last updated: 2026-05-19

## Identity

- Xcode target / codename: **DevCal**
- App Store product name: **SideProfit**
- Subtitle (EN): *Project Profit Tracker*
- Subtitle (繁中): *專案收益與回本追蹤*

This document supersedes earlier framings. For implementation, see [MVP_Planning_and_ShipSwift_Map.md](MVP_Planning_and_ShipSwift_Map.md).

---

## Vision

A break-even tracker for small projects.

The app exists to answer one question:

> Is this side project becoming real?

It does so through a single mechanic: a **two-stage progress system** that first tracks break-even, then tracks a user-defined revenue goal after break-even is reached.

---

## Target User

People running one or more small projects who:

- Pay real money for tools, services, and outsourcing
- Want to know which projects are financially viable
- Currently track this in spreadsheets, Notion, or not at all

Primary archetype: solo founder, indie developer, or small product team running 2–4 apps, SaaS products, or side projects in parallel.

---

## The Core Mechanic — Two-Stage Progress

This is the single most important concept in the product. Everything else supports it.

### Stage 1 — Before break-even

- Progress = `累積收入 ÷ 累積支出` (cumulative revenue ÷ cumulative cash expense)
- Label: **"Break-even XX%"**
- The user does **not** set a target. The target is implicit and updates automatically as the user logs expenses.

### Transition — Break-even reached

The first moment `累積收入 ≥ 累積支出`:

1. App stamps `breakeven_reached_at` on the project
2. Project Detail switches to a celebration state
3. User is prompted to set a long-term goal

### Stage 2 — After break-even

User sets:

- **Goal amount** (required): a lifetime revenue target, e.g., NT$500,000
- **Goal deadline** (optional): a target date

- Progress = `累積收入 ÷ Goal amount`
- Label: **"Goal XX%"**
- If a deadline is set, the app projects an estimated completion date based on recent revenue trend and indicates whether the user is ahead or behind.

This single mechanic replaces the need for a separate "milestone system." Break-even is the one milestone that matters; the goal-setting moment is the second.

---

## What the User Records

| Type | Examples | Notes |
| --- | --- | --- |
| 收入 Income | App sales, subscription payouts, Stripe, Gumroad | Per project, with date and note |
| 支出 Expense | Apple Developer fee, server, AI tools, ads, design, outsourcing | Per project, categorised |
| 時間紀錄 Time log | Hours worked × hourly rate | Per project, manual entry (no timer in V1) |

Wording note (繁中):

- Use **「支出」** and **「收入」** as the two entry types. Avoid the umbrella word **「交易」** in user-facing copy — it sounds clinical/businesslike and indie devs don't think in those terms.
- 「成本」 is fine for **conceptual** phrases — 「回本」, 「時間成本」, 「現金成本 vs 時間成本」, etc.
- 「時間成本」 is preserved as the **feature name** because it represents estimated labor value, not a real cash outflow — distinct from a 支出 entry.

---

## What the App Calculates

| Metric | Formula | Where shown |
| --- | --- | --- |
| Revenue 累積收入 | Σ income | Project Detail, list row |
| Expenses 累積支出 | Σ expense | Project Detail |
| Net 淨利 | Revenue − Expenses (cash only) | Project Detail, list row |
| Hourly rate 實質時薪 | Net ÷ total hours | Project Detail, Time section |
| Progress | See two-stage system above | Project Detail hero, list row |

**Critical decision:** Net is cash-only. Time cost is **not** subtracted from Net.

Time cost is shown as a separate view: *"if you also count your time, your real hourly rate is NT$XX."* Counting time in Net would make most indie projects look like permanent failures, which is demotivating and not how indie devs intuitively think about ROI.

---

## Anti-Features (NOT in this app)

The app is intentionally narrow. The following are not in scope, ever:

- General personal finance (groceries, rent, transportation)
- Team collaboration / multi-user projects
- Receipt scanning / OCR
- Full bookkeeping or accounting
- Tax preparation
- Bank account linking / open banking
- Cryptocurrency
- Invoicing or client management

If a feature does not directly support *"is this side project becoming real?"*, it does not belong in this app.

---

## Differentiation vs Existing Tools

| Tool | Why it fails for indie devs |
| --- | --- |
| Excel / Notion | Manual math, no per-project rollup, no progress visualisation |
| Mint, YNAB, generic finance apps | Framed around personal expenses; no project concept; no break-even |
| App Store Connect | Revenue only; no expense view; no per-app profitability |
| Bookkeeping apps (Xero, Wave) | Built for businesses with employees and invoicing; way too heavy |

DevCal's unique combination: **project-scoped + break-even-centric + designed for solo developers**.

---

## Emotional Layer

The dashboard surfaces motivating context alongside raw numbers. These are sentence templates filled with the user's actual data — not standalone "achievements."

Examples:

- After first income: *"You earned your first NT$120. This covered 4 days of server cost."*
- Mid-progress: *"Today's income paid for 2 months of server cost."*
- Break-even reached: *"🎉 ShipSwift broke even after 8 months. Set your next goal."*
- Time milestone: *"Your project survived another month."*

Tone: matter-of-fact, never sycophantic. The numbers do the celebrating; the copy just gives them voice.

---

## Monetization

Freemium with subscription.

### Free

- 1 project
- 50 transactions per project
- Project Detail with two-stage progress
- Monthly trend chart
- 1 share card template
- **Cloud sync included** (sync is a trust feature, not a paywall)

### Pro — US$4.99/mo, US$39.99/yr (NT$150/mo, NT$1,190/yr)

- Unlimited projects
- Unlimited transactions
- Time Cost view (Hourly rate, hours-by-project)
- Cross-project Insights
- Premium share card templates
- CSV export
- AI Summary (future)

### Paywall trigger points

- Attempt to create a 2nd project
- Reach the 50-transaction limit on a project
- Open Time Cost section
- Open Insights tab
- Select a premium share template
- Tap Export

Paywall is **not** shown during onboarding. Users must experience the core value first.

---

## Localization

V1 launch languages:

1. English
2. Traditional Chinese (繁中)
3. Japanese
4. Korean

Phase 2: Spanish, Portuguese (BR), German, French.

---

## Future (not V1)

- AI Summary on Project Detail ("Your AI Tools cost is growing 23% MoM")
- Predictive break-even date from recent trend
- App Store Connect / RevenueCat / Stripe integrations (auto-import revenue)
- Activity heatmap (GitHub-style commit/revenue grid)
- Yearly recap
- Apple Watch / widget surface

---

## Core Product Promise

> Your side project is becoming something real — and here's the number that proves it.
