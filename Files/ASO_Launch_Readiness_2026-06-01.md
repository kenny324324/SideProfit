# SideProfit ASO Launch Readiness

Date: 2026-06-01

Purpose: final ASO and App Store asset plan for the first App Store submission this week.

## Executive Recommendation

Launch with the current brand:

- On-device display name: `SideProfit`
- App Store localized app name, English: `SideProfit: Profit Tracker`
- App Store localized app name, Traditional Chinese: `SideProfit | 專案收益回本追蹤`
- English subtitle: `Revenue, Expenses, Break-even`
- Traditional Chinese subtitle: `獨立開發者 App/SaaS 收入支出與時間成本`
- Primary category: `Developer Tools`
- Secondary category: `Finance`

Do not use only `SideProfit` as the App Store Connect localized app name. The ASC name field is a high-value indexed field and should carry the brand plus the clearest category/search phrase. Keep the shorter `SideProfit` only for the binary display name on the user's Home Screen.

Position SideProfit as a project profit and break-even tracker for app makers, SaaS builders, solo founders, and side projects. Do not lead with generic budgeting, personal finance, bookkeeping, invoice, tax, or household expense language. Those searches are broader and more competitive, and the app does not implement those workflows.

## Product Reality Check

Current implemented promise, based on the repo:

- Project list and project dashboard.
- Income and expense records by project.
- Cash-only net profit.
- Two-stage break-even progress, then revenue goal tracking.
- Time cost tracking and effective hourly return.
- Cross-project insights.
- Shared recurring costs / shared items.
- Multi-currency display using Frankfurter / ECB exchange rates.
- Firebase Auth with Sign in with Apple.
- Firestore sync.
- Account deletion flow.
- Mock paywall / local entitlement switching, not real StoreKit subscription yet.

Important launch caveats:

- Bundle ID is still `com.kenny.DevCal`; App Store bundle ID still needs to become the real SideProfit ID.
- `GoogleService-Info.plist` points to `sideprofit-dev`; production Firebase project / plist is still a launch blocker.
- `PrivacyInfo.xcprivacy` was not found in the app target.
- Paywall still links to `https://example.com/privacy` and `https://example.com/terms`; Auth and Settings point to a Notion privacy page and Apple standard EULA.
- No screenshot or preview asset files were found in the repo.
- Pricing docs recommend `US$4.99/month` and `US$29.99/year`, but the current paywall UI says `US$39.99/year`.
- Localizable string catalog has launch-language coverage, but English still has 5 `new` strings and 28 missing localization entries in the string catalog check.

## Competitive Read

Closest competitors cluster into three groups:

- Founder dashboard apps, e.g. qdBox: stronger integrations and multi-platform positioning. qdBox currently uses `Revenue Tracker for Founders` as its subtitle and mentions Stripe and RevenueCat sync.
- Business profit / reseller trackers, e.g. Profit Tracker - Made Simple: stronger generic finance and inventory coverage, but less relevant to indie app/SaaS builders.
- Indie revenue trackers, e.g. IndieBar and SoldIt: stronger live revenue / integration angle, but either Mac-only, revenue-only, or focused on App Store Connect notifications.

SideProfit's first-launch opening is not "better revenue analytics." The sharper angle is:

> Manual project profitability before your project is big enough for Stripe, RevenueCat, or App Store Connect dashboards to tell the whole story.

The strongest visible differentiators:

- Break-even progress per project.
- Revenue + expenses + hidden time cost in one place.
- Developer-specific expense categories.
- Cross-project allocation decisions.
- Designed for the early and messy side project stage.

## Metadata - English

### Recommended

App name:

`SideProfit: Profit Tracker`

Subtitle:

`Revenue, Expenses, Break-even`

Keyword field:

`indie,developer,founder,maker,solo,app,saas,mrr,revenue,expense,income,cost,roi,startup,side project`

Promotional text:

`Track revenue, expenses, time cost, and break-even progress for every app, SaaS, or small project you are building.`

Description:

```text
SideProfit helps you see whether a small project is actually becoming profitable.

Track revenue, expenses, time cost, and break-even progress for every app, SaaS, side project, or product experiment you are building. Instead of guessing whether a project is working, SideProfit shows the numbers that matter: income, costs, net profit, hidden development time, and how far each project is from paying for itself.

Built for solo founders, indie developers, app makers, SaaS builders, creators, and small teams managing real projects with real costs.

What you can track:

- Income from app sales, subscriptions, payouts, sponsorships, or other project revenue
- Expenses like hosting, APIs, domains, design, ads, tools, App Store fees, and AI services
- Time spent on each project, with an estimated hourly rate
- Break-even progress before a project becomes profitable
- Long-term revenue goals after a project reaches break-even
- Monthly revenue and expense trends
- Net profit across one or more projects

SideProfit is not a personal budget app or full accounting system. It is a focused project profitability tracker for people who want to know whether a small project is turning into something real.
```

What's New:

```text
Initial release of SideProfit: track project income, expenses, time cost, net profit, and break-even progress in one focused dashboard.
```

### English Alternatives

Conservative:

- App name: `SideProfit: Profit Tracker`
- Subtitle: `Revenue, Expenses, Break-even`
- Best for first launch clarity and conversion. This uses the name for the high-intent `profit tracker` phrase and the subtitle for the product-specific `projects` + `break-even` angle.

Search-growth:

- App name: `SideProfit: Revenue Tracker`
- Subtitle: `Revenue, Expenses, Break-even`
- Use if early App Store impressions are too low.
- Risk: less specific about profit, and closer to generic revenue dashboard competitors.

Niche:

- App name: `SideProfit: Project Profit`
- Subtitle: `Revenue & Break-even`
- Use if product-builder traffic converts better than broader project-profit traffic.
- Risk: reads slightly less naturally than `Profit Tracker`, but captures `project`, `profit`, `revenue`, and `break-even` across visible fields.

## Metadata - Traditional Chinese

App name:

`SideProfit | 專案收益回本追蹤`

Subtitle:

`獨立開發者 App/SaaS 收入支出與時間成本`

Keyword field:

`獨立開發,開發者,個人開發,app,saas,maker,founder,side project,副業,創業,損益,記帳,工具,時薪,現金流,訂閱,主機,API,分潤,淨利,營收,產品,MRR,投入`

Promotional text:

`追蹤每個 App、SaaS 或小型專案的收入、支出、時間成本與回本進度，看清楚它是否正在變成一門生意。`

Description:

```text
SideProfit 幫助你看清楚每個小型專案是否真的正在變成一門生意。

你可以追蹤 App、SaaS、副業或產品實驗的收入、支出、時間成本與回本進度。不需要再用試算表手動計算，也不需要把專案塞進一般記帳 App。SideProfit 會把每個專案的收入、成本、淨利、投入時間，以及距離回本還差多少整理在同一個清楚的 dashboard。

適合 solo founder、獨立開發者、App 創作者、SaaS builder、小型團隊，以及任何正在經營小型專案的人。

你可以追蹤：

- 每個專案的收入與支出
- App sales、訂閱收入、分潤、贊助或其他收入
- 主機、API、網域、設計、廣告、工具、App Store 年費與 AI 服務等成本
- 投入時間與估算時薪
- 專案回本前的進度
- 回本後的長期收入目標
- 每月收入與支出趨勢
- 跨專案的淨利狀態

SideProfit 不是一般家庭記帳 App，也不是完整會計系統。它是一個專注在小型專案收益、成本與回本進度的追蹤工具。
```

What's New:

```text
SideProfit 首次推出：追蹤專案收入、支出、時間成本、淨利與回本進度，幫助你看清楚每個小型專案是否正在變成一門生意。
```

## Metadata - Japanese and Korean Starting Point

These should be reviewed by a native speaker before launch. They are good enough as a first draft for App Store Connect fields.

Japanese:

- App name: `SideProfit: 収益管理`
- Subtitle: `個人開発App/SaaSの収益・費用・時間管理`
- Keywords: `個人開発,開発者,indie,maker,founder,app,saas,roi,mrr,費用,利益,損益分岐,副業,起業,時間,売上,分析,月次,投資,サブスク,ツール,黒字,赤字,収支,収益,円`
- Promotional text: `App、SaaS、副業プロジェクトの収益、費用、時間コスト、損益分岐までの進捗を追跡できます。`

Korean:

- App name: `SideProfit: 수익 추적`
- Subtitle: `개인 개발 앱·SaaS 수익·비용·시간 관리`
- Keywords: `개인개발,개발자,indie,maker,founder,app,saas,roi,mrr,비용,이익,부업,창업,프로젝트,시간,매출,분석,월간,구독,도구,흑자,적자,수입,목표,투자,수익,앱`
- Promotional text: `App, SaaS, 사이드 프로젝트의 수익, 비용, 시간 비용, 손익분기 진행률을 한곳에서 추적하세요.`

## Screenshot Plan

Use real product UI with seeded but realistic data. Avoid abstract marketing cards. The first three screenshots matter most in search results and the product page gallery.

### Screenshot 1 - Core Promise

Caption:

`Know when a project pays for itself`

Visual:

- Project dashboard hero with break-even progress.
- Metrics grid showing income, expenses, net, and progress.
- Use a real project name like `ShipSwift`, `TinyCRM`, or `MenuBarKit`.

Traditional Chinese caption:

`看懂專案何時回本`

### Screenshot 2 - Revenue and Expenses

Caption:

`Track income and costs per project`

Visual:

- Add income / expense flow or recent entries list.
- Show categories like App Sales, Subscriptions, Server, API, AI Tools, App Store Fee.

Traditional Chinese caption:

`每個專案獨立追蹤收入與支出`

### Screenshot 3 - Time Cost

Caption:

`See your hidden time cost`

Visual:

- Time cost screen showing total hours, hidden cost, net including labor, effective rate.

Traditional Chinese caption:

`看見被忽略的時間成本`

### Screenshot 4 - Cross-Project Insights

Caption:

`Compare which projects are working`

Visual:

- Insights screen with net profit ranking, monthly performance, cost ranking.

Traditional Chinese caption:

`比較哪個專案值得繼續投入`

### Screenshot 5 - Shared Costs / Recurring Tools

Caption:

`Split shared tools across projects`

Visual:

- Shared expenses / shared item setup.
- Example: ChatGPT, Figma, Vercel, RevenueCat, Sentry.

Traditional Chinese caption:

`分攤跨專案共用工具成本`

### Screenshot 6 - Goal After Break-even

Caption:

`Set the next revenue goal`

Visual:

- Break-even reached state or set-goal flow.
- Show goal amount and optional deadline projection.

Traditional Chinese caption:

`回本後設定下一個營收目標`

## App Preview Video

Recommendation for V1: optional. If time is tight this week, ship with strong screenshots first. If making one preview, keep it simple and use a real screen recording with short overlay captions.

Length target: 20-25 seconds.

Storyboard:

1. 0-3s: Project list with multiple app/SaaS projects.
   - Caption: `Track every side project like a business`
2. 3-8s: Open a project dashboard, show break-even progress and net profit.
   - Caption: `See revenue, cost, net profit, and break-even`
3. 8-12s: Add income or expense with developer categories.
   - Caption: `Log the numbers that matter`
4. 12-16s: Time cost screen.
   - Caption: `Include your hidden labor cost`
5. 16-21s: Cross-project insights.
   - Caption: `Know which project deserves more time`
6. 21-24s: Logo / project dashboard final frame.
   - Caption: `SideProfit`

## Asset Specs to Prepare

For a minimal iOS + iPadOS launch:

- App icon: 1024 x 1024, already represented by the icon asset, but inspect the final rendered icon in App Store Connect.
- iPhone screenshots: prepare 6.9-inch portrait assets first. Apple can scale down to smaller iPhone display classes if the UI is the same.
- iPad screenshots: required because `TARGETED_DEVICE_FAMILY = "1,2"` includes iPad. Prepare 13-inch iPad screenshots.
- App preview: optional, up to 3 previews per localization, 15-30 seconds, max 30 fps, max 500 MB.

Suggested first launch screenshot count:

- English: 6 iPhone screenshots + 4 iPad screenshots.
- Traditional Chinese: 6 iPhone screenshots + 4 iPad screenshots.
- Japanese/Korean: acceptable to launch later, but if metadata is localized and screenshots are missing, App Store may fall back to the next best language's preview/screenshot assets.

## Privacy Label Draft

This must be verified against the final Firebase SDKs and any App Store Connect answers.

Likely data linked to the user:

- Contact Info: email address, if collected from Sign in with Apple / Firebase Auth.
- User ID: Firebase UID / Apple identity mapping.
- User Content or Other Data: project names, transaction entries, time logs, categories, milestones, sync data.

Likely purpose:

- App Functionality.

Likely not used:

- Tracking.
- Third-party advertising.
- Developer advertising or marketing.

Notes:

- Firebase Analytics appears disabled in `GoogleService-Info.plist`, but Firebase Auth and Firestore are active.
- The app stores project finance data in Firestore sync, so do not claim "Data Not Collected."
- Apple says privacy answers must include third-party partners' practices and must stay accurate if practices change.

## Conversion Risks

Highest impact before launch:

1. The app is strongest when screenshots show concrete project numbers, not generic empty states.
2. If StoreKit is not wired, launch as free and remove or hide purchase-facing claims that imply real subscriptions.
3. If the paywall stays visible, align yearly price with the launch pricing decision: `US$29.99/year` or `US$39.99/year`, not both.
4. Replace `example.com` links before review.
5. Use a production Firebase project / bundle ID before the submitted build.
6. Fix the remaining localization gaps if launching EN, zh-Hant, ja, and ko metadata together.

## First 14 Days After Launch

Track these manually in App Store Connect:

- Product page impressions.
- Product page views.
- Conversion rate from product page view to download.
- Search terms from Apple Search Ads if available.
- Which localization / storefront produces impressions.
- Ratings and reviews, especially confusion around "budget", "accounting", or "revenue import."

First optimization rule:

- If impressions are low, test `Project Revenue Tracker` or `Revenue & Break-even`.
- If impressions are acceptable but conversion is low, rewrite screenshots before changing the app name or subtitle.
- If users expect automatic Stripe/RevenueCat/App Store import, make the manual-first positioning more explicit or prioritize imports.

## Sources Checked

- Apple App information limits: https://developer.apple.com/help/app-store-connect/reference/app-information/app-information
- Apple platform version metadata limits: https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information
- Apple screenshot specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Apple app preview specifications: https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications
- Apple upload screenshots/previews guidance: https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/
- Apple app privacy details: https://developer.apple.com/app-store/app-privacy-details/
- qdBox App Store listing: https://apps.apple.com/us/app/qdbox-business-dashboard/id6758437065
- Profit Tracker - Made Simple App Store listing: https://apps.apple.com/us/app/profit-tracker-made-simple/id6753639259
- IndieBar App Store listing: https://apps.apple.com/us/app/indiebar-revenue-tracker/id6759783060
- SoldIt Taiwan App Store listing: https://apps.apple.com/tw/app/soldit-sales-tracker-widget/id6761266197
