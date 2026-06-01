# SideProfit App Store Connect 訂閱項目設定

日期：2026-06-01

用途：在 App Store Connect 先建立 `SideProfit Pro` 自動續訂訂閱項目。這份只處理 ASC 要填的資料與操作步驟；StoreKit 2 程式串接另行處理。

## 先講結論

建立一個 subscription group，裡面放兩個 auto-renewable subscriptions：

- `com.sideprofit.pro.monthly`：月付，US$4.99，台灣約 NT$150，無免費試用。
- `com.sideprofit.pro.yearly`：年付，US$29.99，台灣約 NT$990，7 天免費試用。

兩個訂閱提供同一組 Pro 權益，只是週期不同，所以放在同一個 subscription group、同一個 level。

## 重要前提

- App Store Connect 的「協議、稅務與銀行業務」要完成 Paid Apps agreement，否則付費 IAP / subscription 可能不能正式上架。
- 目前 repo 裡 `Entitlements.swift` 還是 mock entitlement，`PaywallView` 目前也還顯示 `US$39.99/year`。如果 1.0 要真的賣訂閱，送審前要把 StoreKit 2 串好，並把 UI 年付價格改成 `US$29.99/year`。
- 可以先在 ASC 建立訂閱項目，但不要把 IAP 跟 binary 一起送審，除非 app 內已經能用 StoreKit 成功購買與還原。
- 訂閱 duration 建立後送審就不能改。Product ID 儲存後也不能改、不能重複使用。

## Subscription Group

在 ASC：

`App` → `SideProfit` → 側邊欄 `Monetization` → `Subscriptions` → 建立 group

填：

- Subscription Group Reference Name：`SideProfit Pro`
- Subscription Group Display Name：`SideProfit Pro`
- App Name Display Options：使用 app name / `SideProfit`
- Levels：兩個產品都放同一個 level。如果 ASC 需要排序，年付放上面、月付放下面。

本地化：

| 語言 | Group Display Name | Description |
| --- | --- | --- |
| 繁體中文 | `SideProfit Pro` | `解鎖所有專案收益追蹤功能` |
| English (U.S.) | `SideProfit Pro` | `Unlock all project profit tracking features.` |
| Japanese | `SideProfit Pro` | `すべてのプロジェクト収益管理機能を解放。` |
| Korean | `SideProfit Pro` | `모든 프로젝트 수익 추적 기능을 잠금 해제.` |

## 訂閱項目 1：月付

基本資料：

- Type：`Auto-Renewable Subscription`
- Reference Name：`SideProfit Pro Monthly`
- Product ID：`com.sideprofit.pro.monthly`
- Subscription Duration：`1 Month`
- Subscription Price：`US$4.99`
- Taiwan price target：`NT$150/month`
- Availability：所有 App 可上架的國家 / 地區
- Introductory Offer：不設定
- Level：與年付同一個 level

本地化：

| 語言 | Display Name | Description |
| --- | --- | --- |
| 繁體中文 | `SideProfit Pro 月付` | `無限專案、時間成本、跨專案洞察與匯出。` |
| English (U.S.) | `SideProfit Pro Monthly` | `Unlimited projects, time cost, insights, CSV.` |
| Japanese | `SideProfit Pro 月額` | `無制限プロジェクト、時間コスト、分析、書き出し。` |
| Korean | `SideProfit Pro 월간` | `무제한 프로젝트, 시간 비용, 인사이트, 내보내기.` |

Review Notes：

```text
SideProfit Pro Monthly unlocks unlimited projects, time cost tracking, cross-project insights, and export features. It provides the same entitlement as the yearly plan with monthly billing.
```

## 訂閱項目 2：年付

基本資料：

- Type：`Auto-Renewable Subscription`
- Reference Name：`SideProfit Pro Yearly`
- Product ID：`com.sideprofit.pro.yearly`
- Subscription Duration：`1 Year`
- Subscription Price：`US$29.99`
- Taiwan price target：`NT$990/year`
- Availability：所有 App 可上架的國家 / 地區
- Introductory Offer：設定 7 天免費試用
- Level：與月付同一個 level

本地化：

| 語言 | Display Name | Description |
| --- | --- | --- |
| 繁體中文 | `SideProfit Pro 年付` | `年付解鎖 Pro，含 7 天免費試用。` |
| English (U.S.) | `SideProfit Pro Yearly` | `Annual Pro access with a 7-day free trial.` |
| Japanese | `SideProfit Pro 年額` | `年額 Pro。7日間の無料トライアル付き。` |
| Korean | `SideProfit Pro 연간` | `연간 Pro 이용, 7일 무료 체험 포함.` |

Review Notes：

```text
SideProfit Pro Yearly unlocks unlimited projects, time cost tracking, cross-project insights, and export features. It provides the same entitlement as the monthly plan with annual billing and a 7-day free trial for eligible users.
```

## 年付 Introductory Offer

在年付產品頁：

`Subscription Prices` → `View all Subscription Pricing` → `Set up Introductory Offer`

填：

- Countries or Regions：所有可用 storefront
- Start Date：今天或正式上架日
- End Date：如果 ASC 允許 no end date，就選 no end date；如果必填，先依你的 launch / experiment 週期設定
- Type：`Free`
- Duration：`1 Week`
- Price：`Free`

注意：同一個 subscription group 內，每個使用者通常只能領一次 introductory offer。所以不要同時對月付與年付都設免費試用，首發只放年付即可。

## Review Screenshot

這不是 App Store 截圖，是 IAP / subscription review screenshot，只給 Apple 審核看，不會顯示在商店頁。

之後要補一張 paywall 截圖，畫面需要清楚顯示：

- `SideProfit Pro`
- 月付 `US$4.99/month`
- 年付 `US$29.99/year`
- 年付 `7-day free trial`
- Pro 權益：unlimited projects、time cost、cross-project insights、export
- Restore purchases
- Privacy Policy / Terms of Use
- 自動續訂說明

目前可以先建立產品，但送審前這張 review screenshot 要補上。

## 建立步驟

1. App Store Connect → Apps → `SideProfit`。
2. 側邊欄 → `Monetization` → `Subscriptions`。
3. 建立 `SideProfit Pro` subscription group。
4. 在 group 內新增 `SideProfit Pro Monthly`。
5. 填 Product ID：`com.sideprofit.pro.monthly`。
6. 選 duration：`1 Month`。
7. 設價格：`US$4.99`，確認台灣 storefront 約 `NT$150`。
8. 加入四種 localization 的 display name / description。
9. 不設定 introductory offer。
10. 新增 `SideProfit Pro Yearly`。
11. 填 Product ID：`com.sideprofit.pro.yearly`。
12. 選 duration：`1 Year`。
13. 設價格：`US$29.99`，確認台灣 storefront 約 `NT$990`。
14. 加入四種 localization 的 display name / description。
15. 對年付設定 introductory offer：`Free` + `1 Week`。
16. 編輯 subscription order / level，月付與年付放同一個 level，年付排在月付上方。
17. 暫時不要提交審核，直到 StoreKit 2 串接與 review screenshot 都完成。

## App 內送審前必修

- `PaywallView` 年付價格從 `US$39.99` 改成 `US$29.99`。
- StoreKit 2 用 product IDs 讀產品：
  - `com.sideprofit.pro.monthly`
  - `com.sideprofit.pro.yearly`
- 購買成功後更新 entitlement。
- Restore purchases 要呼叫 `AppStore.sync()` 或等效流程。
- Paywall 必須清楚顯示免費試用多久，以及試用後會收多少錢。
- App Store Server Notifications / 後端同步可以之後補，但至少 client-side StoreKit entitlement 要能正常恢復。

## 不建議現在建立

先不要建立 lifetime / non-consumable：

- `com.sideprofit.pro.lifetime`

原因：V1 還是 manual-first，且 cloud sync / future features 有持續成本。等 launch 後看訂閱轉換與留存，再決定是否加 founder lifetime。

## 官方文件依據

- Apple auto-renewable subscription setup: https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/
- Apple auto-renewable subscription properties: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/auto-renewable-subscription-information/
- Apple required subscription fields: https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/
- Apple introductory offers: https://developer.apple.com/help/app-store-connect/manage-subscriptions/set-up-introductory-offers-for-auto-renewable-subscriptions/
- Apple IAP display name / description / review screenshot fields: https://developer.apple.com/help/app-store-connect/reference/in-app-purchase-information
