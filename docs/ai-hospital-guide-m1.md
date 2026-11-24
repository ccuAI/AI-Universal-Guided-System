# AI 就醫夥伴：里程碑 1 程式架構

> 目標：**開啟權限 → 開 Chrome → 讀到畫面清單 → 送給 AI → 在 AI 指定的按鈕上畫框**，並能隨著長輩的操作自動進行到下一步。
> 平台：只做 Android（minSdk 24，主要在 Android 13 以上的實機測試），瀏覽器先只支援 Chrome。

---

## 1. 整體架構

```
┌──────────────────────── Flutter（Dart） ────────────────────────┐
│ hospital_helper.dart                                            │
│   ├─ PermissionGuidePage  授權引導（受限設定 → 開啟無障礙服務）  │
│   └─ GoalInputPage        輸入醫院、科別、日期 → 開始引導        │
│ guide_channel.dart        MethodChannel 包裝                    │
└───────────────┬─────────────────────────────────────────────────┘
                │ MethodChannel "com.med.myproject/guide"
┌───────────────▼──────────────── Android（Kotlin） ──────────────┐
│ MainActivity            註冊 channel、開啟 Chrome、開設定頁      │
│ GuideSession (object)   目前的目標、步驟紀錄、開/關狀態          │
│ GuideAccessibilityService                                       │
│   ├─ ScreenReader       走訪畫面節點 → 精簡清單 + 遮蔽個資       │
│   ├─ GuideApiClient     呼叫後端 /guide/next                     │
│   └─ OverlayController  懸浮層：畫框、提示泡泡、「停止引導」鈕   │
└───────────────┬─────────────────────────────────────────────────┘
                │ HTTPS POST（JSON）
┌───────────────▼──────── 後端 backfront/guide-server ────────────┐
│ POST /guide/next  →  Gemini（OpenAI 相容介面，JSON 輸出）        │
│ GUIDE_AI_API_KEY 只放在 guide-server/.env                        │
└─────────────────────────────────────────────────────────────────┘
```

**設計決策：由 Kotlin 服務直接呼叫後端，不經過 Flutter。**
長輩在操作 Chrome 時，我們的 App 在背景，Flutter 引擎可能被暫停或回收。無障礙服務是獨立執行的元件，只要它自己能讀畫面、打 API、畫懸浮層，整個引導迴圈就不依賴 Flutter。Flutter 只負責「授權」和「開始」這兩個畫面。

---

## 2. 引導迴圈（Kotlin 服務內）

```
收到無障礙事件（Chrome 畫面變化／點擊／捲動）
   │  debounce 800ms（等畫面穩定）
   ▼
ScreenReader 讀取畫面 → 節點清單
   │  算出清單的 hash，跟上一次一樣就跳過（避免重複打 AI）
   ▼
GuideApiClient 送出 {目標, 歷史步驟, 畫面清單}
   ▼
後端回傳 {action, target_id, message}
   ▼
OverlayController 依 target_id 找到節點的螢幕座標 → 畫框 + 顯示提示
   │
   └─ 長輩點擊 → 產生新事件 → 回到最上面
```

- 正在等 AI 回應時，懸浮層顯示「正在幫你看畫面…」。
- 畫面只是捲動（座標改變，但 hash 不變）時：**不打 AI**，只要用同一個 `target_id` 重新找座標、更新框的位置。
- 收到 `done` 就顯示「掛號完成 🎉」並結束；收到 `need_user` 就提示這一步要長輩自己完成（例如驗證碼）。

---

## 3. 資料格式

### 3.1 畫面節點清單（App → 後端）

```json
{
  "goal": "掛台中榮總 骨科 下週一上午",
  "history": [
    { "message": "請點「網路掛號」", "target_text": "網路掛號" }
  ],
  "screen": {
    "package": "com.android.chrome",
    "url": "https://…",
    "nodes": [
      { "id": 0, "role": "button", "text": "網路掛號", "clickable": true },
      { "id": 1, "role": "input",  "text": "", "hint": "身分證字號", "editable": true },
      { "id": 2, "role": "text",   "text": "骨科" }
    ]
  }
}
```

ScreenReader 的規則：
- 只收錄**看得見**的節點（`isVisibleToUser`，而且邊界在螢幕範圍內），並且要符合以下其中一項：可點擊、可輸入、有文字或 contentDescription。
- `role` 從 `className` 對應出來（Button / EditText / CheckBox / Spinner…），其他一律當 `text`。
- 最多送 **150 個節點**，每段文字最多 80 字，控制大小和費用。
- `url`：從 Chrome 網址列節點 `com.android.chrome:id/url_bar` 讀取（讀不到就留空）。
- Kotlin 端保留 `id → AccessibilityNodeInfo / Rect` 的對照表，這個對照表**不送出去**。

### 3.2 個資遮蔽（送出前，在 App 端完成）

| 類型 | 規則 | 替換成 |
|---|---|---|
| 身分證字號 | `[A-Z][12]\d{8}` | `[身分證]` |
| 手機號碼 | `09\d{2}-?\d{3}-?\d{3}` | `[電話]` |
| 已輸入欄位的內容 | 所有 editable 節點的 `text` | 只送 `"filled": true/false` |

### 3.3 AI 回應（後端 → App）

```json
{
  "action": "tap",
  "target_id": 0,
  "message": "請點這個「網路掛號」按鈕",
  "confidence": 0.86
}
```

`action` 的可能值：`tap`、`input`（提示要填什麼）、`scroll`（目標不在畫面上，提示往下滑）、`wait`、`need_user`、`done`。
`confidence` 低於 0.5 時，提示文字前面加「我不太確定，」，讓長輩可以找家人確認。

---

## 4. 要新增或修改的檔案

### Android
| 檔案 | 內容 |
|---|---|
| `android/app/src/main/AndroidManifest.xml` | 註冊 `<service>`（`BIND_ACCESSIBILITY_SERVICE`），加上 `<queries>` Chrome 套件 |
| `android/app/src/main/res/xml/guide_accessibility_config.xml` | `packageNames="com.android.chrome"`、`canRetrieveWindowContent="true"`、事件類型、`flagReportViewIds\|flagRetrieveInteractiveWindows` |
| `android/app/src/main/res/values/guide_strings.xml` | 無障礙服務的名稱和說明（獨立檔案，避免和組員衝突） |
| `android/app/src/debug/res/xml/guide_network_security_config.xml` | **只給 debug 用**：允許以 http 連到 `127.0.0.1`、`10.0.2.2` |
| `android/app/src/debug/AndroidManifest.xml` | 套用上面的網路設定（只影響 debug 版） |
| `kotlin/com/med/myproject/MainActivity.kt` | 只加一行 `GuideChannel.register(...)` |
| `kotlin/com/med/myproject/guide/GuideChannel.kt` | MethodChannel 的實作 |
| `kotlin/com/med/myproject/guide/GuideSession.kt` | 單例，存放目標、歷史、後端網址、`isRunning` |
| `kotlin/com/med/myproject/guide/GuideAccessibilityService.kt` | 接收事件、debounce、迴圈控制 |
| `kotlin/com/med/myproject/guide/ScreenReader.kt` | 走訪節點、遮蔽、產生 JSON |
| `kotlin/com/med/myproject/guide/GuideApiClient.kt` | `HttpURLConnection` 加協程（不另外引入 OkHttp） |
| `kotlin/com/med/myproject/guide/OverlayController.kt` | `TYPE_ACCESSIBILITY_OVERLAY`：一層全螢幕、不可觸控的畫框層，加一個可觸控的小型「停止引導」按鈕 |

### Flutter
| 檔案 | 內容 |
|---|---|
| `lib/guide_channel.dart` | `isServiceEnabled()`、`openAccessibilitySettings()`、`openAppDetails()`、`startGuide(goal, url)`、`stopGuide()` |
| `lib/hospital_helper.dart` | 改寫成授權引導頁加目標輸入頁；用 `WidgetsBindingObserver` 在長輩從設定頁回來時重新檢查權限 |

### 後端
| 檔案 | 內容 |
|---|---|
| `backfront/guide-server/server.js` | 獨立的伺服器（port 3001），`GET /health`、`POST /guide/next`；用 `json_object` 模式加上伺服器端格式檢查（Gemini 對 `json_schema` 支援不一致） |
| `backfront/guide-server/package.json` | `express`、`dotenv`（直接用 Node 內建的 fetch 呼叫 AI） |
| `backfront/guide-server/.env.example` | `GUIDE_AI_BASE_URL`（預設 Gemini）、`GUIDE_AI_API_KEY`、`GUIDE_AI_MODEL`、`GUIDE_PORT=3001` |

> 因為是多人專案：引導功能使用**自己的 AI 金鑰（預設 Gemini 免費額度）和 .env**，和 `backfront/Server.js`、`lib/API.dart`（醫療早報）完全不相通。

---

## 5. MethodChannel 介面

| 方法 | 參數 | 回傳 | 說明 |
|---|---|---|---|
| `isServiceEnabled` | – | `bool` | 檢查 `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES` 是否包含本服務 |
| `openAccessibilitySettings` | – | – | `Settings.ACTION_ACCESSIBILITY_SETTINGS` |
| `openAppDetails` | – | – | `ACTION_APPLICATION_DETAILS_SETTINGS`（給「允許受限設定」用） |
| `startGuide` | `goal`, `url`, `backendUrl` | `bool` | 寫入 GuideSession，然後用 `setPackage("com.android.chrome")` 開網址；沒有 Chrome 就改用預設瀏覽器，並提示引導可能不準 |
| `stopGuide` | – | – | 清除懸浮層和 session |

---

## 6. 授權引導畫面流程（Flutter）

1. 說明頁：用大字和圖示說明「為什麼需要這個權限、我們會讀什麼、不會讀什麼」（Google Play 要求的明顯揭露，也是對長輩的基本尊重）。
2. **Android 13 以上**：先引導到「應用程式資訊 → 右上角 ⋮ → 允許受限設定」，附上示意圖。
3. 引導到「無障礙 → 已安裝的應用程式 → AI 就醫夥伴 → 開啟」。
4. 回到 App 時自動檢查，成功就顯示 ✅ 並進到目標輸入頁。

---

## 7. 開發與測試環境

- 後端在電腦上跑 `backfront/guide-server`（port 3001），手機透過 USB 執行 `adb reverse tcp:3001 tcp:3001`，App 連到 `http://127.0.0.1:3001`。只有 debug 版允許 cleartext（設定在 `android/app/src/debug/`）。
- 測試機：Android 13 以上的實機（模擬器也可以，但要裝 Chrome）。
- 驗收情境：選 **1 家醫院**的網路掛號頁，從首頁一路被引導到「確認掛號」之前停下來（M1 不真的送出掛號）。
- 除錯：Kotlin 用 `Log.d("Guide", …)` 印出每一輪送出的節點清單和 AI 回應，方便調整 prompt。

---

## 8. 建議的實作順序

1. **服務骨架**：Manifest、config xml、空的 Service，確認能在系統設定裡看到並開啟。
2. **ScreenReader**：在 Chrome 開任一網頁，用 Logcat 確認讀得到按鈕文字和座標。
3. **OverlayController**：先寫死「在第一個可點擊的節點上畫框」，確認座標對得上（要注意狀態列的偏移）。
4. **MethodChannel 和 Flutter 授權頁**：權限檢查、開設定、`startGuide` 開 Chrome。
5. **後端 `/guide/next`** 和 prompt。
6. **串成完整迴圈**：debounce、hash 去重、等待提示、`done`／`need_user`。
7. 在選定的醫院網站實測，修正 prompt 和節點過濾規則。

---

## 9. M1 不做（之後的里程碑）

- 語音輸入和語音播報（TTS）
- 截圖加視覺模型的備案（需要 API 30 以上的 `takeScreenshot`）
- 熱門醫院的固定步驟範本
- 自動填入資料、自動點擊
- Samsung 瀏覽器等其他瀏覽器

---

## 10. 開始前要先處理的既有問題

- `pubspec.yaml` 把 `.env` 列為 asset，但檔案不存在，**現在專案應該建置不過**。要先補上 `.env`，或把它從 assets 拿掉。
- `AndroidManifest.xml` 裡 LINE 的 scheme 是 `line3rdp.2012160109`，但程式裡 `LineSDK.setup('2012349789')` 用的 Channel ID 不一樣，要確認哪一個才對。這跟 M1 無關，但會影響登入。

---

## 11. 已加入：引導途中的對話（M1 之後）

控制列多了綠色的「**對話**」按鈕。按下後，從下方滑出半透明的對話視窗（`GuideChatActivity`），Chrome 留在後面。

- **可以做的事**：打字或按 🎤 用說的；也有快速提問：「我找不到要按的地方」「我想改掛別的科」「這一頁在做什麼？」。
- **修改需求**：AI 判斷長輩想改醫院、科別或時間時，會回傳 `new_goal`，App 更新 `GuideSession.goal`，畫面上顯示「✔ 已更新目標」。
- **問問題**：打開對話當下，會把 Chrome 的畫面清單一起送出（`GuideSession.lastScreen`），AI 能用畫面上的文字描述位置。
- **關閉對話後**：服務立刻用新的目標加上對話紀錄（`/guide/next` 的 `chat` 欄位）重新判斷下一步，並重新畫框。
- **隱私**：使用者的話在送出前遮蔽身分證字號和電話；伺服器 log 不記錄對話內容。
- **其他**：對話視窗開著時，引導會暫停（不讀畫面、不畫框）。按主畫面鍵離開時，對話視窗會自動關閉，對話紀錄保留到停止引導為止。
- **醫療安全**：聽起來是緊急狀況時，AI 會請長輩立刻撥打 119。

| 檔案 | 內容 |
|---|---|
| `guide/GuideChatActivity.kt` | 對話視窗：文字、語音、快速提問 |
| `res/values/guide_styles.xml` | 對話視窗的半透明樣式 |
| `AndroidManifest.xml` | 註冊 `GuideChatActivity`（獨立 task，關閉後回到 Chrome） |
| `backfront/guide-server/server.js` | 新增 `POST /guide/chat` |

