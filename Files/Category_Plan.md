# 分類系統規劃 — DevCal / IndieProfit

**版本**：v1.3 定稿（拍板：不做 Seed Catalog、抽成入帳時跳 dialog）
**日期**：2026-05-21
**作者**：Kenny + Claude
**狀態**：已拍板，可進入實作 session
**Scope**：**v1 第一版上線必做**。本文件不再有「v2 才做」的項目 — 行動清單裡的全部都得在上線前完成。

---

## 1. 目的

新增支出/收入時的「分類」選擇，是 DevCal 最高頻的互動之一。本文件規劃：

1. 鎖定大分類（`TransactionCategory`）的最終清單，避免之後反覆改 enum。
2. 為每個大分類列出推薦的子項目（`CategoryItem`），讓使用者一進來就能感受到「這個 app 懂我」。
3. 整理 Logo 採集清單，Kenny 可以按優先級去 [simpleicons.org](https://simpleicons.org)（CC0、單色 SVG）下載。
4. 統一 `BrandIconRegistry` 的命名與資產規範，避免之後加 logo 時混亂。

---

## 2. 現有架構（快速複習）

```
TransactionCategory  (enum, 寫死)
   └── CategoryItem  (使用者建立的子項目, 可共用或專案內)
         ├── brandIconKey   →  BrandIconRegistry.image(...)   ← 優先
         ├── fallbackIconName →  Phosphor 圖示                ← 次之
         └── (都沒有)        →  大分類的預設圖示              ← 最後
```

**設計原則**：

- **大分類固定**：不開放使用者新增大分類，維持資料庫一致性與報表分群可預期。
- **子項目自由**：使用者可以在任何大分類下新增子項目（共用 or 專案內）。
- **品牌 logo 優先**：常見服務（ChatGPT、Stripe...）顯示真實 logo，提升質感。
- **Phosphor 補位**：冷門服務或一次性支出，使用者自選 Phosphor 圖示即可。

---

## 3. 目前已註冊的 Brand Keys（15 個，無需再找）

來自 [BrandIconRegistry.swift:25-41](DevCal/DevCal/Core/Theme/BrandIconRegistry.swift#L25-L41)：

| Key | 顯示名 | 資產狀態 |
|---|---|---|
| `openai` | OpenAI | 已有（`OpenAIIcon`） |
| `apple` | Apple | 已有（`AppStoreIcon`） |
| `google` | Google | 已有（`GooglePlayIcon`） |
| `anthropic` | Anthropic | **註冊但無資產** |
| `cursor` | Cursor | **註冊但無資產** |
| `github` | GitHub | **註冊但無資產** |
| `vercel` | Vercel | **註冊但無資產** |
| `supabase` | Supabase | **註冊但無資產** |
| `stripe` | Stripe | **註冊但無資產** |
| `cloudflare` | Cloudflare | **註冊但無資產** |
| `figma` | Figma | **註冊但無資產** |
| `notion` | Notion | **註冊但無資產** |
| `vultr` | Vultr | **註冊但無資產** |
| `hetzner` | Hetzner | **註冊但無資產** |
| `amazon` | Amazon | **註冊但無資產** |

→ **這 15 個是第一波要補資產的目標。**

---

## 4. 樹狀圖：大分類 → 推薦子項目

> 標註 `[已註冊]` 的 key 已在 BrandIconRegistry 裡；`[新增]` 是建議補進去的。
> 沒標的就是 Phosphor 圖示即可，不需要 logo。

### 收入（5 個大分類）

```
收入
├── 應用銷售 (appSales)              icon: device-mobile
│   ├── App Store           [已註冊: apple]
│   ├── Google Play         [已註冊: google]
│   ├── Gumroad             [新增: gumroad]
│   ├── Lemon Squeezy       [新增: lemonsqueezy]
│   ├── Paddle              [新增: paddle]
│   └── Polar               [新增: polar]
│
├── 訂閱收入 (subscriptions)         icon: arrows-clockwise
│   ├── RevenueCat          [新增: revenuecat]
│   ├── Stripe              [已註冊: stripe]
│   ├── Substack            [新增: substack]
│   ├── Patreon             [新增: patreon]
│   └── Ko-fi               [新增: kofi]
│
├── 廣告收入 (adRevenue)             icon: megaphone
│   ├── AdMob               [新增: admob]
│   ├── AppLovin            [新增: applovin]
│   ├── Unity Ads           [新增: unity]
│   ├── Google AdSense      [已註冊: google]（共用）
│   └── Meta Audience Network [新增: meta]
│
├── 贊助 (sponsorship)               icon: heart
│   ├── GitHub Sponsors     [已註冊: github]（共用）
│   ├── Patreon             [新增: patreon]（共用）
│   ├── Ko-fi               [新增: kofi]（共用）
│   ├── Buy Me a Coffee     [新增: buymeacoffee]
│   └── Open Collective     [新增: opencollective]
│
└── 其他收入 (otherIncome)           icon: plus-circle
    （使用者自由命名 + Phosphor 圖示）
```

### 支出（13 個大分類）

```
支出
├── 伺服器 (server)                  icon: hard-drives
│   ├── AWS                 [新增: aws]
│   ├── Google Cloud        [已註冊: google]
│   ├── Vercel              [已註冊: vercel]
│   ├── Netlify             [新增: netlify]
│   ├── Cloudflare          [已註冊: cloudflare]
│   ├── DigitalOcean        [新增: digitalocean]
│   ├── Vultr               [已註冊: vultr]
│   ├── Hetzner             [已註冊: hetzner]
│   ├── Linode              [新增: linode]（Akamai 也可）
│   ├── Fly.io              [新增: flydotio]
│   ├── Railway             [新增: railway]
│   └── Render              [新增: render]
│
├── 第三方 API (api)                 icon: network
│   ├── OpenAI              [已註冊: openai]
│   ├── Anthropic           [已註冊: anthropic]
│   ├── Google Gemini       [已註冊: google]
│   ├── Mistral             [新增: mistral]
│   ├── Replicate           [新增: replicate]
│   ├── ElevenLabs          [新增: elevenlabs]
│   ├── Resend              [新增: resend]
│   ├── Twilio              [新增: twilio]
│   ├── Mapbox              [新增: mapbox]
│   ├── Algolia             [新增: algolia]
│   └── Stripe API          [已註冊: stripe]
│
├── Apple 平台費 (appStoreFee)       icon: AppStoreIcon
│   ├── Apple Developer Program ($99/yr) [已註冊: apple]
│   └── App Store 抽成      [已註冊: apple]
│
├── Google 平台費 (googlePlayFee)    icon: GooglePlayIcon
│   ├── Google Play Console ($25 一次性) [已註冊: google]
│   └── Google Play 抽成    [已註冊: google]
│
├── 網域 (domain)                    icon: globe
│   ├── Namecheap           [新增: namecheap]
│   ├── Cloudflare Registrar [已註冊: cloudflare]
│   ├── Porkbun             [新增: porkbun]
│   ├── GoDaddy             [新增: godaddy]
│   └── Hover               [新增: hover]
│
├── 設計 (design)                    icon: paint-brush
│   ├── Figma               [已註冊: figma]
│   ├── Framer              [新增: framer]
│   ├── Adobe CC            [新增: adobe]
│   ├── Sketch              [新增: sketch]
│   ├── Pixelmator Pro      [新增: pixelmator]
│   └── Affinity            [新增: affinity]
│
├── 廣告投放 (advertising)           icon: speaker-high
│   ├── Apple Search Ads    [已註冊: apple]
│   ├── Meta Ads            [新增: meta]
│   ├── Google Ads          [已註冊: google]
│   ├── X Ads               [新增: x]（Twitter 改名）
│   ├── Reddit Ads          [新增: reddit]
│   ├── TikTok Ads          [新增: tiktok]
│   └── LinkedIn Ads        [新增: linkedin]
│
├── 外包 (outsourcing)               icon: users
│   ├── Upwork              [新增: upwork]
│   ├── Fiverr              [新增: fiverr]
│   ├── Toptal              [新增: toptal]
│   ├── Contra              [新增: contra]
│   └── Freelancer          [新增: freelancer]
│
├── 軟體 (software)                  icon: app-window
│   ├── Notion              [已註冊: notion]
│   ├── Linear              [新增: linear]
│   ├── Raycast Pro         [新增: raycast]
│   ├── 1Password           [新增: 1password]
│   ├── Setapp              [新增: setapp]
│   ├── iCloud+             [已註冊: apple]
│   ├── Google One          [已註冊: google]
│   ├── Dropbox             [新增: dropbox]
│   ├── Bear / Obsidian     [新增: obsidian]
│   ├── Things / TickTick   [新增: ticktick]
│   ├── Screen Studio       [新增: screenstudio]
│   ├── Descript            [新增: descript]
│   ├── CleanShot X         [新增: cleanshot]
│   └── Bartender / Magnet  （多半 Phosphor 即可）
│
├── AI 工具 (aiTools)                icon: OpenAIIcon
│   ├── ChatGPT Plus        [已註冊: openai]
│   ├── Claude Pro          [已註冊: anthropic]
│   ├── Cursor              [已註冊: cursor]
│   ├── GitHub Copilot      [已註冊: github]
│   ├── Windsurf            [新增: windsurf]
│   ├── Perplexity          [新增: perplexity]
│   ├── Midjourney          [新增: midjourney]
│   ├── Runway              [新增: runway]
│   ├── Suno                [新增: suno]
│   └── ElevenLabs          [新增: elevenlabs]
│
├── 測試設備 (testingDevices)        icon: devices
│   ├── iPhone              [已註冊: apple]
│   ├── iPad                [已註冊: apple]
│   ├── Android 手機        [新增: android]
│   ├── BrowserStack        [新增: browserstack]
│   └── Sauce Labs          [新增: saucelabs]
│
├── 開發工具 (devTools)              icon: wrench
│   ├── GitHub              [已註冊: github]
│   ├── GitLab              [新增: gitlab]
│   ├── Sentry              [新增: sentry]
│   ├── PostHog             [新增: posthog]
│   ├── Mixpanel            [新增: mixpanel]
│   ├── Amplitude           [新增: amplitude]
│   ├── RevenueCat          [新增: revenuecat]
│   ├── Superwall           [新增: superwall]
│   ├── Firebase            [新增: firebase]
│   ├── Supabase            [已註冊: supabase]
│   └── App Store Connect   [已註冊: apple]
│
└── 其他支出 (otherExpense)          icon: dots-three-circle
    （使用者自由命名 + Phosphor 圖示）
```

---

## 5. 建議考慮新增的大分類（可選）

以下是目前歸在「其他支出」或「開發工具」、但量大到可能值得獨立的：

| 候選分類 | 為什麼 | 取捨建議 |
|---|---|---|
| **分析工具** (analytics) | PostHog/Mixpanel/Amplitude 量很大，目前塞在 devTools | **不獨立**。Indie 通常只用 1-2 個，併在 devTools 即可。 |
| **行銷 / Newsletter** (marketing) | ConvertKit、Beehiiv、ButtonDown 與「廣告投放」不太一樣 | **可考慮**。Newsletter 是長期固定支出，但放在 devTools 也行。先不新增。 |
| **ASO 工具** (asoTools) | AppFollow、SensorTower 等 | **不獨立**。併在 devTools。 |
| **學習** (learning) | 課程、書、會議票（WWDC、Stripe Sessions） | **可考慮**。但 Indie 通常一年幾次，併在 otherExpense 即可。 |
| **法務 / 會計** (legal) | Iubenda（隱私政策）、TaxJar | **不獨立**。併在 otherExpense。 |
| **內容創作** (content) | Screen Studio、Descript、ScreenFlow、OBS | **不獨立**。已併入新增的 `software`（軟體）分類。 |

**v1 確認新增的分類**：

| Key | 顯示名 | icon | 定位 |
|---|---|---|---|
| `software` | 軟體 | `app-window` | 一般軟體訂閱 / 買斷的 catch-all。design / aiTools / devTools 是明確領域軟體，這個分類收容其他（生產力、工作流、內容創作、雲端儲存等）。 |

**分類之間的分界邏輯（避免重複）**：
- `design` → 純設計工具（Figma、Sketch、Affinity）。
- `aiTools` → 對話/生成式 AI（ChatGPT、Claude、Midjourney）。Cursor / Copilot 也歸這裡，因為核心價值是 AI。
- `devTools` → 寫 code / 部署 / 監控 / SDK 相關（GitHub、Sentry、Firebase、RevenueCat）。
- `software` → 不屬於上面三類的軟體（Notion、Raycast、1Password、Screen Studio）。

**結論**：v1 大分類數量從 17 → **18**（5 收入 + 13 支出）。其餘候選分類維持不獨立。

---

## 6. Logo 採集清單（按優先級）

> **來源**：[simpleicons.org](https://simpleicons.org)（CC0、單色 SVG，可直接 template render）。
> **檔名規範**：`Brand_<KeyCamelCase>.svg`（例：`Brand_RevenueCat.svg`）。
> **Assets.xcassets 設定**：Render As = **Template Image**、Single Scale、勾 **Preserve Vector Data**。

### P0：核心 13 個（已註冊但缺資產，必補）

| Key | 顯示名 | simpleicons slug |
|---|---|---|
| `anthropic` | Anthropic | anthropic |
| `cursor` | Cursor | cursor |
| `github` | GitHub | github |
| `vercel` | Vercel | vercel |
| `supabase` | Supabase | supabase |
| `stripe` | Stripe | stripe |
| `cloudflare` | Cloudflare | cloudflare |
| `figma` | Figma | figma |
| `notion` | Notion | notion |
| `vultr` | Vultr | vultr |
| `hetzner` | Hetzner | hetzner |
| `amazon` | Amazon | amazon |
| （`openai`/`apple`/`google` 已有） | — | — |

### P1：高頻 Indie 服務（強烈建議補）

| Key | 顯示名 | simpleicons slug | 出現分類 |
|---|---|---|---|
| `revenuecat` | RevenueCat | revenuecat | devTools, subscriptions |
| `firebase` | Firebase | firebase | devTools |
| `sentry` | Sentry | sentry | devTools |
| `posthog` | PostHog | posthog | devTools |
| `linear` | Linear | linear | software |
| `raycast` | Raycast | raycast | software |
| `1password` | 1Password | 1password | software |
| `obsidian` | Obsidian | obsidian | software |
| `setapp` | Setapp | setapp | software |
| `framer` | Framer | framer | design |
| `gumroad` | Gumroad | gumroad | appSales |
| `lemonsqueezy` | Lemon Squeezy | lemonsqueezy | appSales |
| `paddle` | Paddle | paddle | appSales |
| `polar` | Polar | polar | appSales |
| `patreon` | Patreon | patreon | sponsorship, subscriptions |
| `kofi` | Ko-fi | kofi | sponsorship |
| `buymeacoffee` | Buy Me a Coffee | buymeacoffee | sponsorship |
| `superwall` | Superwall | superwall | devTools |
| `meta` | Meta | meta | advertising, adRevenue |
| `windsurf` | Windsurf | windsurf | aiTools |
| `perplexity` | Perplexity | perplexity | aiTools |

### P2：雲端 / 伺服器類（次優先）

| Key | 顯示名 | simpleicons slug |
|---|---|---|
| `aws` | AWS | amazonwebservices（或 aws） |
| `digitalocean` | DigitalOcean | digitalocean |
| `linode` | Linode | linode |
| `flydotio` | Fly.io | flydotio |
| `railway` | Railway | railway |
| `render` | Render | render |
| `netlify` | Netlify | netlify |
| `mapbox` | Mapbox | mapbox |
| `algolia` | Algolia | algolia |
| `twilio` | Twilio | twilio |
| `resend` | Resend | resend |
| `elevenlabs` | ElevenLabs | elevenlabs |
| `mistral` | Mistral | mistralai |
| `replicate` | Replicate | replicate |

### P3：廣告 / 設計 / 平台（補完用）

| Key | 顯示名 | simpleicons slug |
|---|---|---|
| `x` | X (Twitter) | x |
| `reddit` | Reddit | reddit |
| `tiktok` | TikTok | tiktok |
| `linkedin` | LinkedIn | linkedin |
| `admob` | AdMob | googleadmob（或併 google） |
| `applovin` | AppLovin | applovin |
| `unity` | Unity | unity |
| `adobe` | Adobe | adobe |
| `sketch` | Sketch | sketch |
| `pixelmator` | Pixelmator Pro | pixelmator |
| `affinity` | Affinity | affinity |
| `substack` | Substack | substack |
| `opencollective` | Open Collective | opencollective |
| `namecheap` | Namecheap | namecheap |
| `porkbun` | Porkbun | porkbun |
| `godaddy` | GoDaddy | godaddy |
| `gitlab` | GitLab | gitlab |
| `mixpanel` | Mixpanel | mixpanel |
| `amplitude` | Amplitude | amplitude |
| `upwork` | Upwork | upwork |
| `fiverr` | Fiverr | fiverr |
| `toptal` | Toptal | toptal |
| `android` | Android | android |
| `browserstack` | BrowserStack | browserstack |
| `midjourney` | Midjourney | midjourney |
| `runway` | Runway | runwayml |
| `suno` | Suno | suno |
| `dropbox` | Dropbox | dropbox |
| `ticktick` | TickTick | ticktick |
| `screenstudio` | Screen Studio | screenstudio |
| `descript` | Descript | descript |
| `cleanshot` | CleanShot X | cleanshot |

---

## 7. 命名規範（不要忘）

- **brandIconKey**：全小寫、無空格、無連字符（例：`lemonsqueezy`、`buymeacoffee`）。一旦定下來不要再改，這是 SwiftData 的儲存值。
- **顯示名稱**：在 `BrandIconRegistry.displayName(for:)` 裡新增 case，使用品牌官方拼寫（例：`Ko-fi`、`Lemon Squeezy`、`Buy Me a Coffee`）。
- **資產檔名**：`Brand_<KeyCamelCase>`（例：`Brand_LemonSqueezy`、`Brand_BuyMeACoffee`）。aliases() 預設會走這個規則，新增單字大寫即可，不需要每個都改 alias。
- **特例**：`openai`/`apple`/`google` 已經有舊資產名（`OpenAIIcon`/`AppStoreIcon`/`GooglePlayIcon`），不要動，alias 已經處理好。

---

## 8. 常見服務 = Brand Icon Library（不做 Seed Catalog）

**拍板**：v1 **不做**「從常見服務挑選」預設選單。常見服務的價值由 `BrandIconRegistry` 體現 — 使用者建立子項目時：

1. 自己輸入名稱（例：「ChatGPT Plus」）。
2. 開 IconPickerView，**Brand 區**列出所有已註冊的 brand icons（按分類相關度排序更好），點 OpenAI logo 即帶 `brandIconKey = "openai"`。
3. **Phosphor 區**列出萬用符號當 fallback。
4. 自己輸入金額 + 計費週期。

**為什麼這樣最好**：
- 不污染 DB（不 seed 不用的服務）。
- 不擋路（不強迫使用者進「從常見挑」流程）。
- icon library 越完整，使用者越覺得「app 懂我」。
- 工程量小：只要 BrandIconRegistry + Assets + IconPickerView 兩個分區就好。

**對 IconPickerView 的要求**（如目前不支援要改）：
- 分兩個 section：**Brand**（從 `BrandIconRegistry.knownKeys` 拉、且有資產的）+ **符號**（Phosphor）。
- 可搜尋（打 "open" 就出 OpenAI / Open Collective + Phosphor 含 "open" 的）。
- Brand row 顯示 logo + displayName，選擇後寫入 `brandIconKey`、清掉 `fallbackIconName`。
- Phosphor row 反之。

→ **這是上線必做的 UX 層面工作**。Logo 補齊（§6）+ IconPickerView 分區是同一件事。

---

## 9. 行動清單

### Kenny 端（上線前必完成）
- [ ] **P0（13 個）**：從 simpleicons.org 下載 SVG，必補。
- [ ] **P1（22 個）**：從 simpleicons.org 下載，必補。
- [ ] **P2（14 個）**：上線前最後一波，補完。
- [ ] **P3（28 個）**：上線前最後一波，補完。
- [ ] 把所有 SVG 拖進 Assets.xcassets，命名 `Brand_<Camel>`，設為 Template + Preserve Vector Data。

### Claude 端（下個 session 進入實作）
- [ ] 新增 `software` 大分類進 `TransactionCategory`，icon = `app-window`，displayName「Software」。
- [ ] `BrandIconRegistry.knownKeys` 補上所有 P0~P3 的 key（依 Kenny 補資產進度同步補 key）。
- [ ] `BrandIconRegistry.displayName(for:)` 補對應 case。
- [ ] **IconPickerView 改造**：分 Brand / Phosphor 兩個 section（§8），加搜尋。
- [ ] **平台抽成 dialog**：實作 §10 描述的流程。
- [ ] 更新 CLAUDE.md 註記資產來源（simpleicons.org / CC0）。

---

## 10. 連動議題

- **多幣別（v1 必做）**：獨立規劃文件 → [Multi_Currency_Plan.md](./Multi_Currency_Plan.md)。將會新增 `CategoryItem.originalCurrencyCode`、移除 `Project.currencyCode`、新增 `ExchangeRateService`。**同一個分支實作**（schema 一起遷移最乾淨）。
- **平台抽成自動計算（v1 必做）**：使用者在 AddTransactionView 儲存類型為「應用銷售」(`appSales`) 或「訂閱收入」(`subscriptions`) 的 income 時，跳 **systemAlert**（**不要用 `.confirmationDialog`**，遵循 [[feedback-no-brand-tint-in-alerts]]）：
  - 標題：「同時記一筆平台抽成？」
  - 內容：「Apple/Google 通常會收取 30%（小型企業 15%）。」
  - 三顆按鈕：「記 30%」、「記 15%」、「跳過」。Cancel 用 `Theme.primaryText`，「記」是主要 action。
  - 確認後自動建立配對的支出 Transaction：`categoryRaw = appStoreFee` 或 `googlePlayFee`、`originalAmount = income.originalAmount × percent`、`originalCurrencyCode = income.originalCurrencyCode`、`sourceItemName = "平台抽成"`、`note` 帶上「來自：[income 名稱]」。
  - **不存 `autoFeePercent` 在 model 上**，每次都問。
  - Apple vs Google 怎麼分？看 income 的 sourceCategoryItemID 對應的 CategoryItem 的 `brandIconKey`（apple / google）或 sourceItemName 字串判斷；判不到就**先跳一個前置 systemAlert 讓使用者選 Apple/Google**，再跳百分比那一個（或合併成一個含 4 顆按鈕的 alert）。
- **CSV 匯入歷史資料（上線後 v1.x）**：第一波核心使用者請求才做。需要設計分類映射 UI。**不是 v1 上線必做**。
