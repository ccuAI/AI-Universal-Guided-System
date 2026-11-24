# AI 就醫夥伴：引導伺服器

這是 App「AI 就醫夥伴」掛號畫面引導專用的後端，**和 `backfront/Server.js`、App 內醫療早報用的 `lib/API.dart` 完全分開**：用自己的 `.env`、自己的金鑰、自己的 port（3001）。

預設使用 **Google Gemini 免費額度**。任何 OpenAI 相容的服務（OpenAI、Groq…）都能用，只要改 `.env` 的 `GUIDE_AI_BASE_URL`、`GUIDE_AI_API_KEY`、`GUIDE_AI_MODEL`。

## 申請 Gemini 金鑰（免費）

1. 用 Google 帳號登入 https://aistudio.google.com/apikey
2. 按「Create API key」（建立 API 金鑰），複製產生的金鑰
3. 貼到 `.env` 的 `GUIDE_AI_API_KEY=` 後面

免費額度有每分鐘／每天的次數限制（以 Google 官網公告為準）；遇到限制或塞車時伺服器會自動改用備援模型（見下方「自動備援」）。免費方案送出的內容 Google 可能用來改善產品，App 已在送出前遮蔽身分證字號、電話與輸入框內容。

## 自動備援（免費模型塞車時）

主要模型遇到塞車（503）、額度用完（429）、模型下架（404）或逾時時，伺服器會**依序改用下一個模型**，失敗的模型先休息 1 分鐘再試。整條備援會在 26 秒內結束（App 最多等 30 秒）。

- 用 Gemini 時預設的順序：`gemini-3.1-flash-lite` → `gemini-3.5-flash-lite` → `gemini-flash-lite-latest` → `gemini-flash-latest`（同一把金鑰，不用另外設定）
- 自訂順序：在 `.env` 設定 `GUIDE_AI_FALLBACK_MODELS=模型1,模型2`；留空（`GUIDE_AI_FALLBACK_MODELS=`）就關閉備援
- 第二家服務（選填，例如 Groq 免費方案）：設定 `GUIDE_AI_BACKUP_BASE_URL`、`GUIDE_AI_BACKUP_API_KEY`、`GUIDE_AI_BACKUP_MODELS`

啟動時會列出「使用順序」，並逐一測試每個模型能不能用；用到備援時，log 會顯示 `[ai] 主要模型無法使用，這次改用備援：…`。

## 啟動

需要 Node.js 18 以上。

```powershell
cd backfront/guide-server
npm install
copy .env.example .env   # 然後打開 .env，填入你自己的 GUIDE_AI_API_KEY
npm start
```

看到 `AI 就醫夥伴引導伺服器已啟動：http://localhost:3001` 和 `✓ 金鑰有效，模型「…」可用` 就代表成功。

如果出現「找不到模型」的提醒，照提示把 `.env` 的 `GUIDE_AI_MODEL` 改成列出的其中一個名稱（Google 會不定期更新模型名稱）。

## 讓手機連到電腦上的伺服器

- **實機（USB 連接）**：執行下面這行之後，App 預設的 `http://127.0.0.1:3001` 就能用。
  ```powershell
  adb reverse tcp:3001 tcp:3001
  ```
- **模擬器**：在 App「進階設定」把網址改成 `http://10.0.2.2:3001`。

debug 版才允許 http，設定在 `android/app/src/debug/res/xml/guide_network_security_config.xml`。正式上線時請改用 https。

## 部署到 Google Cloud Run（組員安裝 App 就能直接用）

部署之後，App 連到雲端的 `https://…run.app`，不需要電腦、不用接 USB、組員也不用自己申請金鑰。

> ⚠ **金鑰安全**：Cloud Run 的專案需要開啟帳單。**不要在同一個專案裡申請 Gemini 金鑰**，否則 Gemini 可能變成依用量收費。
> 用原本在 AI Studio 申請的免費金鑰即可（它屬於另一個沒有帳單的專案）。

### 第一次部署

1. 到 https://console.cloud.google.com 建立一個專案，記下「專案 ID」，並依畫面指示**連結帳單帳戶**（Cloud Run 有免費額度，小量使用通常不會收費）。
   建議到「帳單 → 預算與快訊」設定一個小額預算（例如 NT$100）提醒。
2. 安裝 Google Cloud CLI：https://cloud.google.com/sdk/docs/install ，裝好後**重開 PowerShell**，執行並登入：
   ```powershell
   gcloud auth login
   ```
3. （建議）在 `.env` 設定通行碼 `GUIDE_ACCESS_TOKEN=自己想一串英數字`
4. 在 `backfront/guide-server` 資料夾執行（第一次會詢問是否啟用 Cloud Run / Cloud Build 等服務，都回答 `y`）：
   ```powershell
   .\deploy-cloudrun.ps1 -Project 你的專案ID
   ```
   如果出現「無法執行指令碼」，先執行 `Set-ExecutionPolicy -Scope Process Bypass` 再執行一次。
5. 完成後會顯示網址（例如 `https://ai-hospital-guide-xxxx.asia-east1.run.app`）。用瀏覽器打開 `網址/health`，看到 `{"ok":true…}` 就成功了。
6. 把網址填到 `lib/hospital_helper.dart` 的 `_defaultBackendUrl`；有設通行碼的話也填到 `_defaultAccessToken`，重新安裝 App。

### 之後更新

改了 `server.js` 或 `.env` 之後，再執行一次 `.\deploy-cloudrun.ps1 -Project 你的專案ID` 就會更新，網址不變。

### 保護與費用

- `.env` 不會被上傳（見 `.gcloudignore`），金鑰用 Cloud Run 的環境變數保存。
- 限制：每台裝置每 10 分鐘 120 次、每天全部 2,000 次（可用 `GUIDE_RATE_LIMIT`、`GUIDE_DAILY_LIMIT` 調整）；最多 1 台機器（`--max-instances 1`）。
- 沒人使用時會自動關機（`--min-instances 0`），不收費；閒置後第一次使用要多等幾秒喚醒。
- 通行碼會寫在 App 裡，GitHub 如果是公開的，別人也看得到；它只是基本防護，主要還是靠次數上限。

## API

| 方法 | 路徑 | 說明 |
|---|---|---|
| GET | `/health` | App 按「開始引導」前會先檢查這個 |
| POST | `/guide/next` | 送入 `{ goal, history, chat, screen: { url, nodes } }`，回傳 `{ action, target_id, message, confidence }` |
| POST | `/guide/chat` | 引導途中的對話。送入 `{ goal, chat, message, screen }`，回傳 `{ reply, new_goal }`；`new_goal` 不是 null 代表長輩修改了需求 |

`action` 的可能值：`tap`、`input`、`scroll`、`wait`、`need_user`、`done`。完整格式請看 `docs/ai-hospital-guide-m1.md`。

Log 只會記錄網域、元素數量和 AI 的指示；對話只記錄字數和修改後的目標，不會記錄完整網址、畫面內容和對話內容。
