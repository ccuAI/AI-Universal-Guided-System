# AI 就醫夥伴：引導伺服器

這是 App「AI 就醫夥伴」掛號畫面引導專用的後端，**和 `backfront/Server.js`、App 內醫療早報用的 `lib/API.dart` 完全分開**：用自己的 `.env`、自己的金鑰、自己的 port（3001）。

預設使用 **Google Gemini 免費額度**。任何 OpenAI 相容的服務（OpenAI、Groq…）都能用，只要改 `.env` 的 `GUIDE_AI_BASE_URL`、`GUIDE_AI_API_KEY`、`GUIDE_AI_MODEL`。

## 申請 Gemini 金鑰（免費）

1. 用 Google 帳號登入 https://aistudio.google.com/apikey
2. 按「Create API key」（建立 API 金鑰），複製產生的金鑰
3. 貼到 `.env` 的 `GUIDE_AI_API_KEY=` 後面

免費額度有每分鐘／每天的次數限制（以 Google 官網公告為準）；遇到限制時伺服器會自動等 3 秒重試一次。免費方案送出的內容 Google 可能用來改善產品，App 已在送出前遮蔽身分證字號、電話與輸入框內容。

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

## API

| 方法 | 路徑 | 說明 |
|---|---|---|
| GET | `/health` | App 按「開始引導」前會先檢查這個 |
| POST | `/guide/next` | 送入 `{ goal, history, chat, screen: { url, nodes } }`，回傳 `{ action, target_id, message, confidence }` |
| POST | `/guide/chat` | 引導途中的對話。送入 `{ goal, chat, message, screen }`，回傳 `{ reply, new_goal }`；`new_goal` 不是 null 代表長輩修改了需求 |

`action` 的可能值：`tap`、`input`、`scroll`、`wait`、`need_user`、`done`。完整格式請看 `docs/ai-hospital-guide-m1.md`。

Log 只會記錄網域、元素數量和 AI 的指示；對話只記錄字數和修改後的目標，不會記錄完整網址、畫面內容和對話內容。
