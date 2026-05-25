# 多幣別系統規劃 — DevCal / IndieProfit

**版本**：v1.2 定稿（拍板：永遠用今日匯率、幣別選項擴至 15 種、不做 snapshot）
**日期**：2026-05-21
**作者**：Kenny + Claude
**狀態**：已拍板，可進入實作 session
**Scope**：**v1 第一版上線必做**。本規劃裡的全部 schema 變動、UI 改動、ExchangeRateService 都必須上線前完成。
**相關文件**：[Category_Plan.md](./Category_Plan.md)（同一個分支實作）

---

## 1. 目的與核心需求

Kenny 的需求（2026-05-21）：

1. **設定中的幣別**改名為「顯示幣別」(display currency) — 整個 app 的金額用這個顯示。
2. **新增專案時的幣別欄位拿掉** — 專案不再綁定幣別。
3. **新增支出/收入時，使用者選「本次的原始幣別」**，預設帶入顯示幣別。
4. **資料儲存記下「原始幣別 + 原始金額」** — 顯示時即時換算。
5. **顯示幣別更換時，過去交易不重算**，永遠以原始為準，顯示時用當下匯率轉。

**範例**：顯示幣別 = TWD。使用者新增「ChatGPT Plus $20 USD/月」訂閱。資料庫存 `20.0 + "USD"`，UI 顯示 `NT$640`（用當天匯率），原始 `$20` 也要看得到當輔助資訊。

---

## 2. 設計原則（這幾條決定了後面所有架構）

1. **原始永遠存** — `(amount, currencyCode)` 是 source of truth，不可丟。
2. **轉換永不存** — 不在資料庫存「轉成顯示幣別後的金額」。每次 UI render 即時 convert。
3. **永遠用今日匯率**（拍板）— v1 不做歷史 snapshot。Transaction 只存 `originalAmount` + `originalCurrencyCode`，顯示時用 ExchangeRateService 的當前匯率轉。**接受過去交易的顯示值會隨匯率波動的 trade-off**，並用「原始幣別細字」在 UI 上輔助說明。
4. **沒網路也要能用** — 匯率表快取本地，過期顯示警示，但不能擋使用者操作。
5. **單一匯率來源** — 全 app 共用一個 `ExchangeRateService`，避免散落各處硬編匯率。

---

## 3. 現況快照

### 目前的幣別痕跡

| 位置 | 現況 | 處置 |
|---|---|---|
| `@AppStorage("defaultCurrency")` (SettingsView:18) | `"TWD"`，picker 列 8 種 | **保留並改名概念**：UI 顯示「顯示幣別」 |
| `Project.currencyCode` (Project.swift:14) | 每個專案綁一個幣別 | **移除欄位**（Schema 遷移） |
| `Transaction` | 沒有幣別欄位（隱含繼承 project） | **新增**：`originalAmount` + `originalCurrencyCode` |
| `CategoryItem.totalAmount` | 沒有幣別欄位 | **新增**：`originalCurrencyCode` |
| `TimeLog.hourlyRate` | 沒有幣別欄位 | **新增**：`hourlyCurrencyCode` |
| `Project.goalAmount` | 沒有幣別欄位 | **新增**：`goalCurrencyCode` |
| `CurrencyFormatter` | 接收 `currencyCode: String` | 不動，本來就是純 formatter |
| AddProjectView | 有幣別 picker | **移除** |
| AddTransactionView / CategoryItemEditView / AddTimeLogView / SetGoalView | 沒幣別 picker | **新增**，預設帶 displayCurrency |

### 受影響的 view（grep 結果）

只要含 `project.currencyCode` 的都要改成 displayCurrency（除了我們刻意顯示「原始」的地方）：

- ProjectDashboardView、TransactionsListView、TransactionRow、CategoryPickerView、CategoryItemEditView
- TimeCostView、AddTimeLogView
- ProjectAnalyticsView、InsightsView
- SharedExpensesView、SharedExpenseEditView、ProjectCard、SetGoalView

→ 全 app 顯示金額的地方都會碰到，**一次改完別分批**。

---

## 4. 資料模型變動

### 4.1 Project（移除欄位）

```diff
@Model
final class Project {
-   var currencyCode: String = "TWD"

    var goalAmount: Double? = nil
+   /// 設定 goal 時使用的幣別，回頭顯示時做轉換。沒設 goal 則為 nil。
+   var goalCurrencyCode: String? = nil

    ...
}
```

**理由**：專案不再綁定幣別。Goal 仍然要記原始幣別，否則改顯示幣別後目標數字會「變」。

### 4.2 Transaction（新增兩個欄位 + 改名）

```diff
@Model
final class Transaction {
-   var amount: Double = 0
+   /// 使用者輸入時的原始金額，永不改寫。
+   var originalAmount: Double = 0
+   /// 使用者輸入時選的幣別，例如 "USD"。永不改寫。
+   var originalCurrencyCode: String = "TWD"

    ...
}
```

**`amount` 直接改名為 `originalAmount`**，趁 v1 還沒上線清乾淨。`signedAmount` 改成回傳「原始幣別下的有號值」，UI 顯示時才換算。

**為什麼選「永遠用今日匯率」而不是 snapshot**（拍板）：
- 簡單。schema 沒 snapshot 欄位、沒 nil 處理、沒 fallback 邏輯。
- Trade-off：使用者上個月記了 `$20 USD`，當時顯示 `NT$640`，下個月可能變 `NT$630`。
- 緩解：TransactionRow 永遠顯示原始幣別細字（`$20 USD`），使用者一眼看出是匯率變動而非資料變動。
- 若未來需要會計準確度（報稅、季度結算），再升級到 snapshot 即可，schema 只是多加一個欄位、不會 breaking。

### 4.3 CategoryItem（新增一個欄位）

```diff
@Model
final class CategoryItem {
    var totalAmount: Double = 0
+   /// 建立時使用的幣別。訂閱項目每次扣款用這個建 Transaction，
+   /// 不會跟著使用者後來改顯示幣別而動。
+   var originalCurrencyCode: String = "TWD"

    ...
}
```

`amount(for project:)` 邏輯不動 — 它回傳的就是「原始幣別下的金額」，UI 端負責轉換。

**訂閱排程器產生 Transaction 時**：用 CategoryItem 的 `originalCurrencyCode` 寫入新 Transaction。

### 4.4 TimeLog（新增一個欄位）

```diff
@Model
final class TimeLog {
    var hourlyRate: Double = 0
+   /// 設定時薪時使用的幣別。
+   var hourlyCurrencyCode: String = "TWD"

    ...
}
```

`laborCost = hours * hourlyRate` 一樣回傳「原始幣別下的成本」，UI 端換算。

### 4.5 預設值來源

新增 Transaction / CategoryItem / TimeLog / Goal 時的幣別預設值，**統一從 `@AppStorage("defaultCurrency")` 讀取**。建議封裝成 helper：

```swift
enum DisplayCurrency {
    @AppStorage("defaultCurrency") static var code: String = "TWD"  // 概念示意
}
```

實際上要做成 `@Environment` 注入或 observable，方便預覽，但先靠 `@AppStorage` 直接 read 也行。

---

## 5. 匯率服務（ExchangeRateService）

### 5.1 API 選型

| 方案 | 免費額度 | 需要 Key | 授權 | v1 適合？ |
|---|---|---|---|---|
| **Frankfurter** (frankfurter.dev) | 無限制（合理使用） | 否 | 資料來源 ECB，free | **✓ 推薦** |
| Open Exchange Rates | 1000/月 free | 是 | 免費方案受限 | 可選 |
| ExchangeRate-API | 1500/月 free | 是 | 免費方案受限 | 可選 |
| Apple `ExchangeRate` framework | — | — | 不存在 | × |

**v1 用 Frankfurter**：`https://api.frankfurter.dev/v1/latest?base=USD`，回傳一個 base 對所有其他幣別的 map，一次拉完。

**ECB 限制**：只支援主要法幣（USD/EUR/JPY/GBP/CNY/HKD/KRW/TWD/SGD 等 30+），對 indie 完全夠用。沒有加密貨幣，但 v1 不需要。

### 5.2 服務介面

```swift
@MainActor @Observable
final class ExchangeRateService {
    static let shared = ExchangeRateService()

    /// 以 USD 為 base 的匯率表。例：rates["TWD"] = 32.45。
    /// 從 UserDefaults 載入，背景刷新。
    private(set) var rates: [String: Double] = [:]
    private(set) var lastUpdated: Date? = nil
    private(set) var isFetching: Bool = false
    private(set) var lastError: String? = nil

    /// 唯一的換算入口。同幣別回原值。表中查不到任一個幣別回 nil（caller UI 顯示 "—"）。
    /// 用法：fx.convert(transaction.originalAmount, from: transaction.originalCurrencyCode, to: displayCurrency)
    func convert(_ amount: Double, from: String, to: String) -> Double?

    /// 拉一次最新匯率。app 啟動、進前景、設定中按手動刷新時呼叫。
    func refresh() async

    /// 是否已超過 24 小時沒更新（UI 顯示警示用）。
    var isStale: Bool { ... }
}
```

**單一 API**：因為不做 snapshot，全 app（Transaction、CategoryItem、Goal、TimeLog）都用同一個 `convert(...)`。

### 5.3 快取與刷新策略

- **啟動**：先讀 UserDefaults 裡的 rates（即使過期），UI 馬上有東西可顯示。
- **背景刷新**：app 啟動 + 進前景時，如果 `lastUpdated` 距今超過 6 小時就 refresh。
- **手動刷新**：設定中放一顆「立即更新匯率」按鈕。
- **失敗處理**：保留舊 rates、`lastError` 記下原因、UI 顯示「匯率可能過期」橫幅。
- **儲存格式**：`UserDefaults.standard.set(data, forKey: "exchangeRates.v1")`，存 JSON。

### 5.4 一致性陷阱

**Aggregation 必須在原始幣別之外的層級換算**：

```swift
// ✗ 錯誤：transactions 可能有混合幣別，直接 sum 是垃圾數字
var totalIncome: Double {
    (transactions ?? []).filter { $0.type == .income }.reduce(0) { $0 + $1.originalAmount }
}

// ✓ 正確：每筆先換算到 displayCurrency 再加總
func totalIncome(in displayCode: String, fx: ExchangeRateService) -> Double {
    (transactions ?? [])
        .filter { $0.type == .income }
        .reduce(0) { sum, t in
            sum + (fx.convert(t.originalAmount, from: t.originalCurrencyCode, to: displayCode) ?? 0)
        }
}
```

→ **Project 的 `totalIncome` / `totalExpenses` / `netProfit` 等 computed properties 都要改簽名**，或者改成在 view 層計算。Claude 實作時要特別注意。

---

## 6. UI 變動清單（依畫面）

### 6.1 SettingsView
- 「Default currency」標籤改為「顯示幣別」，註腳補一句「所有金額會以此幣別顯示。每筆交易仍然以原始幣別儲存。」
- 新增區塊「匯率」：顯示 `lastUpdated`、「立即更新」按鈕、失敗訊息（如有）。

### 6.2 AddProjectView
- **拿掉幣別 picker**。
- 不需要替代品（goal 之後在 SetGoalView 設）。

### 6.3 SetGoalView
- 新增幣別 picker，預設帶 displayCurrency。
- 儲存到 `Project.goalCurrencyCode`。

### 6.4 AddTransactionView
- 在金額輸入欄旁邊加幣別 picker（或下拉），預設 displayCurrency。
- 儲存到 `Transaction.originalCurrencyCode`。
- 預覽行（optional）：「≈ NT$640」即時顯示換算後的值。

### 6.5 CategoryItemEditView
- 同上：金額旁加幣別 picker，預設 displayCurrency。
- 儲存到 `CategoryItem.originalCurrencyCode`。

### 6.6 AddTimeLogView
- 時薪旁加幣別 picker。
- 儲存到 `TimeLog.hourlyCurrencyCode`。

### 6.7 顯示金額的所有 view（清單見 §3）
- 全部改成 `convert(originalAmount, from: originalCurrency, to: displayCurrency)`。
- **顯示規範見 §7**。

---

## 7. 顯示規範

### 7.1 主數字 vs 原始輔助

| 場景 | 主數字 | 是否顯示原始 |
|---|---|---|
| Dashboard hero ring（總收入/支出） | displayCurrency 換算後 | 否（會是混合幣別的加總，顯示原始無意義） |
| TransactionRow / CategoryItem row | displayCurrency 換算後 | **是**，第二行細字顯示 `$20 USD` |
| AddTransactionView 預覽 | 原始 + 「≈ NT$640」 | 兩個都顯示 |
| TimeCostView 卡片 | displayCurrency | 否 |
| 設定中 Goal 卡片 | displayCurrency | 是（如果與 display 不同），細字 `目標：$10,000 USD` |

### 7.2 當匯率拿不到時

- 主數字顯示 `—`，附小字「匯率不可用」。
- 原始幣別行照常顯示（這個永遠存在 DB 裡，不依賴網路）。

### 7.3 匯率過期警示

- 全 app 頂部偶爾出現一條 banner（Dashboard 即可）：「匯率最後更新於 X 天前 · 立即刷新」。
- 超過 7 天就 banner 換成更顯眼的紅黃配色。

---

## 8. 邊界情況

| 情況 | 處置 |
|---|---|
| 新增交易時離線 | 允許輸入儲存，原始幣別永遠存得進 DB。顯示時若無匯率快取則顯示 `—`，有快取就用快取（過期會 banner 提醒）。 |
| 過去交易顯示值會隨匯率波動 | **預期行為**。TransactionRow 永遠顯示原始幣別細字（`$20 USD`），使用者一眼看出是匯率變動。會 §11 之後升級到 snapshot。 |
| 訂閱項目跨多月扣款 | 每次扣款建 Transaction 時，照 CategoryItem 的 originalCurrencyCode 寫入。每筆獨立。 |
| 共用支出拆攤 | 拆攤在「原始幣別下」算（例：$30 USD 平均分給 3 個專案 = 每專案 $10 USD）。各專案在自己 dashboard 上轉成 displayCurrency。 |
| 使用者改顯示幣別 | 所有畫面下次 render 時自然轉新幣別。原始幣別不變、Goal 不變（原始幣別保留）。 |
| 兩筆原始幣別不同的交易加總 | 各自用今日匯率轉到 displayCurrency 後加總。 |
| 平台抽成 dialog 觸發時 | 用 income 的 `originalCurrencyCode` 計算抽成金額，建立的支出 Transaction 沿用同一個 originalCurrencyCode（不轉幣別）。 |

---

## 9. 遷移策略

由於 v1 還沒上線、Firebase 也還沒接，**直接做 destructive schema 變動最乾淨**：

1. 修改 model（Project / Transaction / CategoryItem / TimeLog）。
2. SwiftData migration plan：給新欄位預設值
   - `Transaction.originalCurrencyCode` 預設 `"TWD"`（或讀當下 displayCurrency 也行）。
   - 同理 CategoryItem / TimeLog。
3. SeedData.swift 更新：seed 出來的範例資料補上幣別欄位。
4. 把 `Project.currencyCode` 從 model 拿掉。如果之前裝過 dev build 的 device 會直接遷移失敗 → **建議 Kenny 把模擬器 app 砍掉重灌**（記憶中 Kenny 同時開 Xcode，會涉及 build DB，這部分要他手動處理）。

**如果哪天上線後才要做**：另寫 migration script 把 `project.currencyCode` 複製到所有 child transaction，再下一版才真正移除欄位。但 v1 階段不必。

---

## 10. 行動清單

### Phase A — 後端（Models + Service）
- [ ] 新增 `ExchangeRateService`（@Observable, singleton），含 Frankfurter API client、UserDefaults 快取、`convert(_:from:to:)`、`refresh()`、`isStale`。
- [ ] 改 `Transaction`：`amount` → `originalAmount`，新增 `originalCurrencyCode`。
- [ ] 改 `CategoryItem`：新增 `originalCurrencyCode`。
- [ ] 改 `TimeLog`：新增 `hourlyCurrencyCode`。
- [ ] 改 `Project`：移除 `currencyCode`，新增 `goalCurrencyCode`。
- [ ] Project 上的 `totalIncome` / `totalExpenses` / `netProfit` / `netThisMonth` 改成接收 `(displayCode, fx)` 參數的 method，用今日匯率即時轉。
- [ ] `signedAmount` 同理或改名為 `signedOriginalAmount`。
- [ ] SeedData 更新。
- [ ] SettingsView.currencyOptions 從 8 種擴充為 15 種：`["TWD", "USD", "JPY", "EUR", "GBP", "CNY", "HKD", "KRW", "SGD", "AUD", "CAD", "CHF", "INR", "THB", "MYR"]`。
- [ ] App 首次啟動：`@AppStorage("defaultCurrency")` 預設值改成讀 `Locale.current.currency?.identifier`（fallback "TWD"），讓非台灣使用者開箱即用。

### Phase B — 表單（Inputs）
- [ ] SettingsView：標籤改名 + 新增「匯率」區塊與手動刷新按鈕。
- [ ] AddProjectView：移除幣別 picker。
- [ ] AddTransactionView：新增幣別 picker（金額旁），預設 displayCurrency，即時顯示 ≈ 換算值。
- [ ] CategoryItemEditView：同上。
- [ ] AddTimeLogView：時薪旁加幣別 picker。
- [ ] SetGoalView：新增幣別 picker。

### Phase C — 顯示（Outputs）
- [ ] ProjectDashboardView / ProjectCard：用 displayCurrency。
- [ ] TransactionsListView / TransactionRow：主數字 displayCurrency、原始幣別細字第二行。
- [ ] CategoryPickerView / ItemRow：金額用 displayCurrency。
- [ ] TimeCostView / AddTimeLogView 顯示部分：用 displayCurrency。
- [ ] ProjectAnalyticsView / InsightsView：用 displayCurrency。
- [ ] SharedExpensesView / SharedExpenseEditView：用 displayCurrency，原始細字。
- [ ] Dashboard 頂部加「匯率過期」banner（如 stale）。

### Phase D — 收尾
- [ ] 訂閱排程器（SubscriptionScheduler）：產生 Transaction 時帶上 CategoryItem 的 originalCurrencyCode。
- [ ] 測試：切換 displayCurrency 時所有畫面數字正確刷新。
- [ ] 測試：離線時 UI 不 crash，原始幣別仍可看，匯率拿不到時顯示 `—`。
- [ ] 測試：15 種幣別的 picker 顯示與儲存。
- [ ] 字串：新增「匯率」「顯示幣別」「原始金額」相關繁中字串，遵循 zh-first 慣例。

---

## 11. 上線後才考慮的（明確不在 v1）

- **歷史匯率 snapshot**：v1 拍板用今日匯率，未來若有會計準確度需求（報稅、季度結算），加 `Transaction.originalToUsdRate` 欄位、建立時 snapshot 即可，schema 不會 breaking。
- **手動覆寫匯率**：使用者可以手動指定「我這筆就是用 X 匯率」。
- **加密貨幣**：BTC/ETH 收款（如果有讀者用 Ko-fi crypto tier）。需要不同 API 來源。
- **匯率波動分析**：「你這個月的 net 因匯率波動少了 5%」這類洞察。
- **多 base 緩存**：目前 Frankfurter 一次拉一個 base（USD），其他用三角換算。若精度成問題再拉多個 base。
- **CSV 匯入歷史對帳**（與 Category_Plan 連動）：需要分類映射 + 匯率回填邏輯，工程量大。

---

## 12. 對 Category_Plan.md 的影響

- §10 第一條（多幣別 TODO）改成 → 「已有獨立規劃文件，見 [Multi_Currency_Plan.md](./Multi_Currency_Plan.md)」。
- CategoryItem 將新增 `originalCurrencyCode` 欄位 — 不影響 Category enum / Logo 規劃，仍可獨立進行。
- 兩個任務建議**同一個分支實作**（schema 一起遷移最乾淨），但 PR 可以分兩個。
