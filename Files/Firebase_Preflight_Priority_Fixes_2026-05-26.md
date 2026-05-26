# Firebase 前優先修復清單

檢查日期：2026-05-26  
基準 commit：`cf24764 docs: lock Phase 1 decisions (Apple-only, no email, local-delete only)`  
目的：在下午接 Firebase Auth / Firestore 前，確認哪些架構問題需要先修，避免把遠端同步接到不穩定的本地寫入流程上。

## 結論

Claude 這輪改動有把資料層往正確方向推進：`Core/Data/Repositories`、DTO、`SyncServicing`、`PendingSyncOperation` 都已經出現，這是 Firestore-ready 架構需要的骨架。

但現在還不建議直接開始接 Firestore DB。Auth 可以先接，因為 `AuthService` 已經是邊界；資料庫同步前，至少要先處理 P0 與 P1，否則會出現「本機看起來正常、遠端漏資料或乾淨 checkout 不能 build」的問題。

## 目前 worktree 狀態

目前仍有未提交檔案：

- `DevCal/DevCal/Core/Localization/Localizable.xcstrings`
- `DevCal/DevCal/Features/Splash/SplashView.swift`
- `DevCal/DevCal/ShipSwift/SWUtil/SWDateExtension.swift`
- `DevCal/DevCal/Core/UX/AppReviewPrompt.swift`（untracked）
- `DevCal/DevCal/Core/UX/InAppBrowser.swift`（untracked）

這代表現在的本機狀態和 `HEAD` 不完全一致。Firebase 前要先決定這些改動要保留、提交，還是拆出去，不然之後 debug 會很難分辨是 Firebase 問題還是本機未提交狀態問題。

## P0：先修，否則會影響 build / 可重現性

### 1. `HEAD` 已引用 untracked UX 檔案

問題位置：

- `DevCal/DevCal/DevCalApp.swift:25` 使用 `AppReviewPrompter`
- `DevCal/DevCal/DevCalApp.swift:124` 呼叫 `.inAppBrowser()`
- `DevCal/DevCal/DevCalApp.swift:125` 呼叫 `.appReviewPrompt(appReviewPrompter)`
- `DevCal/DevCal/Features/Projects/AddProjectView.swift:19`
- `DevCal/DevCal/Features/TimeCost/AddTimeLogView.swift:13`
- `DevCal/DevCal/Features/Transactions/AddTransactionView.swift:27`
- `DevCal/DevCal/Features/Settings/SettingsView.swift:261`

但這兩個實作檔目前沒有被 git 追蹤：

- `DevCal/DevCal/Core/UX/AppReviewPrompt.swift`
- `DevCal/DevCal/Core/UX/InAppBrowser.swift`

風險：

- 本機會因為檔案存在而 build 成功。
- 乾淨 checkout、CI、另一台機器會缺檔，導致編譯失敗。
- 之後接 Firebase 時，很容易把「環境不可重現」誤判成 Firebase 設定問題。

建議修法：

- 如果這兩個 UX 功能要保留：把兩個檔案納入版本控制。
- 如果只是實驗功能：先移除所有呼叫點，讓 `HEAD` 回到乾淨可 build。

驗收方式：

- `git ls-files DevCal/DevCal/Core/UX/AppReviewPrompt.swift DevCal/DevCal/Core/UX/InAppBrowser.swift` 有輸出兩個檔案，或程式碼不再引用它們。
- 乾淨 checkout 後 `xcodebuild` 可以成功。

### 2. Recurring scheduler 會繞過 sync queue

問題位置：

- `DevCal/DevCal/Core/Data/Repositories/TransactionUseCase.swift:182-187`
- `DevCal/DevCal/Features/Settings/SharedExpenseEditView.swift:458-462`
- `DevCal/DevCal/Core/Services/SubscriptionScheduler.swift:67-84`
- `DevCal/DevCal/Core/Services/SubscriptionScheduler.swift:126-147`

目前流程：

- `TransactionUseCase.saveSubscription(...)` 先透過 `CategoryItemRepository` 建立 recurring item。
- 接著直接呼叫 `SubscriptionScheduler.runDueCheck(...)`。
- `SubscriptionScheduler` 內部直接 `context.insert(txn)`、修改 `item.nextDueDate`、修改 `project.breakevenReachedAt`，最後 `try? context.save()`。

風險：

- `CategoryItem` 建立會 enqueue sync，但 scheduler 自己產生的 `Transaction` 不會 enqueue。
- `CategoryItem.nextDueDate` 被推進後不會 enqueue。
- `Project` 的 break-even stamp 被更新後不會 enqueue。
- App 本機資料看起來正確，但 Firestore 會漏 recurring 產生的交易與狀態更新。
- `try? context.save()` 會吞掉 save error，Firebase 接上後會更難追錯。

建議修法：

- 讓 scheduler 也走資料層邊界，不要只直接碰 `ModelContext`。
- 最小改法：`SubscriptionScheduler.runDueCheck` 注入 `SyncServicing`，每次產生交易、推進 item、更新 project 時 enqueue 對應 DTO。
- 較乾淨改法：把 recurring catch-up 流程搬進 data/use-case 層，scheduler 只負責判斷 due items，實際寫入由 repository/use case 完成。
- 移除 scheduler 內的 `try? context.save()`，改成 throwing flow，讓呼叫端顯示或記錄錯誤。

驗收方式：

- recurring item 到期時，至少會產生這些 pending operations：
  - generated `Transaction`
  - updated `CategoryItem`
  - touched `Project`（如果 break-even 狀態有變）
- `rg "try\\? context\\.save" DevCal/DevCal/Core/Services/SubscriptionScheduler.swift` 沒有結果。
- 加一個 repository/use-case 測試，使用 `NoopSyncService.recentlyEnqueued` 驗證 enqueue 數量與 entity kind。

## P1：Firestore DB 前應該修

### 3. Features 裡仍有直接 SwiftData 寫入點

問題位置：

- `DevCal/DevCal/Features/Dashboard/ProjectDashboardView.swift:150-153`
- `DevCal/DevCal/Features/Transactions/CategoryItemEditView.swift:204-247`
- `DevCal/DevCal/Features/Milestones/MilestonesView.swift:184-189`
- `DevCal/DevCal/Features/Milestones/MilestonesView.swift:230-240`

目前這些 view 還在直接呼叫：

- `context.insert(...)`
- `context.delete(...)`
- `try? context.save()`

風險：

- 這些寫入不會 enqueue `PendingSyncOperation`。
- Firestore 接上後，使用者某些操作只會存在本機。
- UI 層同時負責表單、商業流程、資料寫入與錯誤處理，之後同步、衝突解決、離線 queue 都會變難。

建議修法：

- `ProjectDashboardView.deleteProject()` 改走 `ProjectRepository.deleteProject(...)`。
- `CategoryItemEditView.save/deleteItem()` 改走 `CategoryItemRepository`。
- `MilestonesView` 補 `MilestoneRepository`，或明確決定 manual milestones 是 local-only；如果 Firestore 需要同步，就必須走 repository。

驗收方式：

- `rg "context\\.insert|context\\.delete|try\\? context\\.save" DevCal/DevCal/Features` 只剩下刻意保留且有註解說明 local-only 的地方。
- 刪除 project、建立/修改/刪除 category item、建立/刪除 manual milestone 都會 enqueue sync operation。

### 4. recurring deterministic id 目前吃使用者當下 timezone

問題位置：

- `DevCal/DevCal/Core/Services/SubscriptionScheduler.swift:28-40`

目前 `deterministicTransactionID(...)` 預設使用 `Calendar.current`。如果同一個 due date 在不同裝置、不同時區被跑 scheduler，`yyyyMMdd` 有機會不一致，導致 Firestore 上出現重複交易或 dedupe 失效。

建議修法：

- 使用固定 UTC Gregorian calendar。
- 或把 due date 建模成不含時間與時區的 day key，再用同一個 day key 產生 deterministic id。

驗收方式：

- 加單元測試：同一個 due date 在 Taipei / Los Angeles timezone 下產生相同 deterministic id。
- Firestore path 或 document id 對 recurring transaction 使用這個穩定 id。

## P2：可順手修，但不阻擋 Firebase Auth

### 5. `AuthView` 有一個 Swift warning

問題位置：

- `DevCal/DevCal/Features/Auth/AuthView.swift:86`

目前：

```swift
var conjunction = AttributedString(" 和 ")
```

建議改成：

```swift
let conjunction = AttributedString(" 和 ")
```

這不是架構阻擋點，但修掉可以讓 build warning 更乾淨。

### 6. localization 變更很大，接 Firebase 前要獨立驗證

目前 `Localizable.xcstrings` 有大量 diff。這不一定是問題，但它和 Firebase 無關，建議不要跟 Firebase commit 混在一起。

建議驗證：

- `jq empty DevCal/DevCal/Core/Localization/Localizable.xcstrings`
- `xcrun xcstringstool compile --dry-run --output-directory /tmp/DevCalStringCheck DevCal/DevCal/Core/Localization/Localizable.xcstrings`
- Firebase 相關 commit 不要同時包含大量文案整理，除非是必要變更。

## 建議修復順序

1. 先處理 untracked UX 檔案，確保 `HEAD` 可以乾淨 build。
2. 修 scheduler sync gap，因為這是 Firestore DB 最容易漏資料的地方。
3. 把剩下的 Feature direct writes 移到 repository。
4. 固定 recurring deterministic id 的 timezone 行為。
5. 清 warning、驗證 localization，保持 Firebase commit 乾淨。

## Firebase 接入建議

可以先做：

- Firebase Auth / Apple Sign In wiring。
- Auth state 與本地使用者狀態整合。
- 使用 `NoopSyncService` 保持 DB local-only。

先不要做：

- 直接把 Firestore 寫入塞進 view。
- 直接讓 view 呼叫 Firebase SDK。
- 在 scheduler direct write 還沒收斂前開啟 Firestore DB sync。

判斷標準：

- Auth 可以先接，因為登入是清楚的 service boundary。
- Firestore DB 要等 repository / scheduler / feature direct writes 收斂後再接，否則會把遠端同步綁在不完整的寫入路徑上。
