# SideProfit Pricing Research

Research date: 2026-06-01

## Recommendation

Launch Pro at:

- Monthly: US$4.99
- Yearly: US$29.99
- Taiwan target: about NT$150/month and about NT$990/year, using App Store Connect's storefront pricing unless a local test says otherwise.
- Default selected plan on the paywall: yearly.
- Intro offer: 7-day free trial on yearly only.

This keeps the monthly anchor at the familiar US$5 level while making the yearly plan feel like the obvious purchase. It also prices SideProfit below direct competitors that already include RevenueCat or Stripe integrations.

Do not launch at US$9.99/month yet. That level is more appropriate after automatic revenue imports, richer reports, widgets, AI summaries, or team/business workflows are live.

## Current App Packaging

Current implementation and planning docs show:

- Free: 1 project, 50 records, core project dashboard, monthly trend, 1 share template, cloud sync included.
- Pro: unlimited projects, unlimited records, time cost tracking, cross-project insights, premium share templates, CSV export, future AI summary.
- Current placeholder price in the app: US$4.99/month and US$39.99/year.
- Primary upgrade triggers: second project, record limit, Time Cost, Insights, premium share template, export.

The strongest Pro value is not "more charts"; it is "I run multiple projects and need to know which one is worth continuing." The second-project gate is the cleanest purchase moment.

## Competitor Pricing

| Product | Closest angle | Current public pricing found | Implication |
| --- | --- | --- | --- |
| qdBox - Projects & Revenue | Very close: projects, manual income/expenses, RevenueCat and Stripe sync, CSV/JSON export | US$6.99/month, US$49.99/year | SideProfit should be cheaper until integrations exist. |
| Profit Tracker - Made Simple | Broader small-business/reseller profit tracker with inventory, images, exports, cloud storage | App Store copy says US$9.99/month or US$99.99/year | Higher ceiling exists, but it serves broader business use and has heavier features. |
| Trendly: App Sales | App Store Connect revenue analytics for indie developers | US$3, US$5, US$9 in-app plans | Developer tools can support tiered pricing, but SideProfit is simpler in V1. |
| SoldIt: Sales Tracker & Widget | iOS developer sales notifications and widgets | US$1.99/month Solo, US$4.99/month Studio in copy; Taiwan page shows NT$60/NT$150 IAPs | US$4.99 is accepted for serious indie dev utility, but narrow tools can be cheaper. |
| IndieBar - Revenue Tracker | macOS menu bar revenue tracker for Stripe/RevenueCat/GA4 | US$19.99 Solo, US$59.99 Team IAPs | One-time/lifetime style pricing is common in indie dev utilities. Consider a founder lifetime later. |
| App Earnings and Widgets | App Store Connect financial data/widgets | US$1.99 full version | Cheap one-time tools exist; SideProfit must justify recurring value through ongoing project tracking. |
| Cube Time & Expense Tracker | Time and expense tracking for projects/clients | Cloud Sync and Cube Anywhere subscriptions, plus Pro upgrade | Time/expense tools can monetize recurring sync/report value, but older competitors mix one-time and subscription products. |

## Market Benchmarks

RevenueCat's 2026 subscription benchmarks show:

- Common app anchors: weekly around US$5, monthly around US$10, yearly around US$30.
- Monthly median has moved toward US$8, while yearly median is around US$34.80.
- Productivity is heavily yearly-skewed in plan mix.
- North America often anchors at about US$9.99/month and US$39.99/year, while Asia-Pacific is lower on monthly/yearly medians.

For SideProfit, this means US$39.99/year is defensible in the broader subscription market, but US$29.99/year is the better V1 launch price because the app is still manual-first and direct competitor qdBox has more integrations.

## Why Not Lower Than US$4.99/US$29.99

US$2.99/month or US$19.99/year would likely increase purchases from casual users, but it weakens the business-tool positioning. The target user is tracking real project money. If they have 2 to 4 projects, US$29.99/year is still a small expense compared with one developer account, one SaaS bill, or one avoidable project mistake.

The app should feel affordable, not disposable.

## Why Not Keep US$39.99 Yearly For V1

US$39.99/year is not wrong, but it puts SideProfit near the current North America subscription benchmark and close to qdBox's US$49.99/year. qdBox already offers RevenueCat and Stripe sync. SideProfit's current differentiation is break-even framing, time cost, and focus, not automation.

Use US$39.99/year after one or more of these land:

- App Store Connect, RevenueCat, Stripe, or Paddle import
- Predictive break-even date
- AI monthly summary that identifies cost/revenue changes
- Widgets or share cards that users use weekly
- Strong export/reporting workflow

## Suggested App Store Products

Use one subscription group:

- `com.sideprofit.pro.monthly`
  - Display name: SideProfit Pro Monthly
  - Price: US$4.99
  - No intro trial
- `com.sideprofit.pro.yearly`
  - Display name: SideProfit Pro Yearly
  - Price: US$29.99
  - 7-day free trial

Optional after launch:

- Founder Lifetime: US$49.99 or US$59.99 non-consumable

Only add lifetime if cloud costs are low and feature support will not become expensive. It may convert indie developers who dislike subscriptions, but it weakens recurring revenue quality.

## Paywall Copy Direction

Current feature list is reasonable, but the highest-value wording should shift from "unlock features" to "manage more than one real project."

Suggested headline:

> Track every project that could become real.

Suggested subhead:

> Unlimited projects, time cost, cross-project insights, and exports for builders running more than one idea.

Suggested yearly badge:

> Best for active builders

Suggested annual price helper:

> About US$2.50/month

Keep the comparison table, but order rows by purchase value:

1. Projects
2. Income and expense records
3. Time cost tracking
4. Cross-project insights
5. CSV export
6. Share templates

Add cloud sync as a trust row with both Free and Pro checked, or mention it under the table. It helps explain why the app asks for sign-in without making sync feel paywalled.

## Experiments

Run these only after analytics events are reliable.

1. Control: US$4.99/month, US$29.99/year, yearly default, 7-day yearly trial.
2. Higher annual: US$4.99/month, US$39.99/year, yearly default.
3. Lower monthly anchor: US$3.99/month, US$29.99/year.
4. No trial: US$4.99/month, US$29.99/year, no trial, stronger free tier preview.
5. Founder lifetime: US$4.99/month, US$29.99/year, US$49.99 lifetime.

Do not test more than one dimension at once. The first useful test is annual US$29.99 vs US$39.99.

## Metrics To Track

Minimum events:

- `paywall_viewed(trigger)`
- `plan_selected(plan)`
- `trial_started(plan)`
- `purchase_started(plan)`
- `purchase_completed(plan)`
- `purchase_failed(plan, error)`
- `restore_started`
- `restore_completed`
- `subscription_status_changed(status, plan)`

Key cuts:

- Conversion by trigger: `second_project`, `record_limit`, `time_cost`, `insights`, `export`, `settings`.
- Yearly share of purchases.
- Trial-to-paid conversion.
- First-week retained usage after starting trial.
- Paid user activation: created second project, added at least 3 entries, opened Insights or Time Cost.
- Refund/cancel rate by plan.

Decision guardrails:

- If most payers come from `settings`, the paywall is not tied to core value.
- If `second_project` converts but `time_cost` does not, lead paywall copy with multi-project tracking.
- If annual starts are high but paid conversion is weak, shorten or remove the trial rather than lowering price.
- If users regularly hit the 50-record limit but do not subscribe, the limit may feel punitive or the export/insight value is not clear.

## Proceeds Planning

Apple states auto-renewable subscriptions normally pay 70% in the first year, then 85% after one year of paid service, minus applicable taxes. If enrolled in the App Store Small Business Program, proceeds are 85% at each billing cycle.

Approximate proceeds before taxes:

| Plan | Customer price | 70% proceeds | 85% proceeds |
| --- | ---: | ---: | ---: |
| Monthly | US$4.99 | US$3.49 | US$4.24 |
| Yearly | US$29.99 | US$20.99 | US$25.49 |
| Yearly, future | US$39.99 | US$27.99 | US$33.99 |

## Sources

- Apple App Store Connect, pricing by storefront: https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/
- Apple auto-renewable subscriptions and proceeds: https://developer.apple.com/app-store/subscriptions/
- Apple introductory offers: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/
- RevenueCat State of Subscription Apps 2026, Productivity: https://www.revenuecat.com/state-of-subscription-apps-2026-productivity/
- qdBox App Store listing: https://apps.apple.com/us/app/qdbox-projects-revenue/id6758437065
- Profit Tracker - Made Simple App Store listing: https://apps.apple.com/us/app/profit-tracker-made-simple/id6753639259
- Trendly App Store listing: https://apps.apple.com/us/app/trendly-app-sales/id1669815607
- SoldIt Taiwan App Store listing: https://apps.apple.com/tw/app/soldit-sales-tracker-widget/id6761266197
- IndieBar App Store listing: https://apps.apple.com/us/app/indiebar-revenue-tracker/id6759783060
- App Earnings and Widgets App Store listing: https://apps.apple.com/us/app/app-earnings-and-widgets/id6448806730
- Cube Time & Expense Tracker App Store listing: https://apps.apple.com/tw/app/cube-time-expense-tracker/id586003524
