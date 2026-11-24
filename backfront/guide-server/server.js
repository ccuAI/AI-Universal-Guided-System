// AI 就醫夥伴：掛號引導後端
//
// 與 backfront/Server.js、App 內的 lib/API.dart 完全分開：
// 自己的 .env、自己的 AI 金鑰（GUIDE_AI_API_KEY）、自己的 port（預設 3001）。
//
// 預設使用 Google Gemini（免費額度）。任何「OpenAI 相容」的服務都能用，
// 只要在 .env 改 GUIDE_AI_BASE_URL、GUIDE_AI_API_KEY、GUIDE_AI_MODEL：
//   Gemini : https://generativelanguage.googleapis.com/v1beta/openai
//   OpenAI : https://api.openai.com/v1
//   Groq   : https://api.groq.com/openai/v1
//
// POST /guide/next  收到「目標 + 畫面元素清單」，回傳下一步要框哪個元素、要對長輩說什麼。
// POST /guide/chat  引導途中的對話：回答長輩的問題，需要時回傳修改後的目標（new_goal）。

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const express = require('express');

const PORT = Number(process.env.GUIDE_PORT) || 3001;
const BASE_URL = (process.env.GUIDE_AI_BASE_URL || 'https://generativelanguage.googleapis.com/v1beta/openai')
  .replace(/\/+$/, '');
const API_KEY = process.env.GUIDE_AI_API_KEY;
const MODEL = process.env.GUIDE_AI_MODEL || 'gemini-3.1-flash-lite';
// 思考程度（none / low / medium / high）：越低回應越快。留空則不送，用模型預設值。
const REASONING_EFFORT = (process.env.GUIDE_AI_REASONING_EFFORT || '').trim();

if (!API_KEY) {
  console.error('缺少 GUIDE_AI_API_KEY：請複製 .env.example 成 .env 並填入你自己的金鑰（Gemini 金鑰可到 Google AI Studio 免費申請）。');
  process.exit(1);
}

const ACTIONS = ['tap', 'input', 'scroll', 'wait', 'need_user', 'done'];
const MAX_NODES = 240;
const MAX_HISTORY = 8;
const MAX_MESSAGE = 100;
const MAX_CHAT = 10;
const MAX_REPLY = 200;
const MAX_GOAL = 120;
const RATE_LIMIT_RETRY_MS = 3_000;

const SYSTEM_PROMPT = `你是「AI 就醫夥伴」，在手機的 Chrome 上一步一步引導台灣的長輩完成醫院網路掛號。

你會收到 JSON：
- today：今天的日期與星期（台灣時間），用來換算「下週一」「明天」這類時間
- goal：長輩想掛的醫院、科別、時間
- history：之前給過的指示（由舊到新）
- url、title：目前的網址和網頁標題（可能是空的）
- nodes：這個網頁的元素，依網頁上的順序排列。id 是編號；role 是 button / link / input / select / checkbox / radio / text；
  text 是顯示的文字；input 只會給 hint（欄位提示）和 filled（是否已經填了），不會給內容。
  沒有 offscreen 的元素在畫面上看得到；offscreen 是 "above" / "below" 的元素在畫面上方／下方，要捲動才看得到。
- chat：長輩在引導過程中跟你的對話（可能是空的）。裡面提到的困難或需求要考慮進去，
  例如長輩說「找不到按鈕」，就給更清楚的位置描述。

你只能回覆一個 JSON 物件，不要有其他文字，格式如下：
{"action": "tap", "target_id": 3, "message": "請點這個『網路掛號』", "confidence": 0.9}

規則：
0. 【最重要】先看懂「這一頁在要求做什麼」（看 title、標題文字和選項），照網站目前這一步走。
   每家醫院的掛號順序不同：有的先選科別，有的先選日期、時段，再選醫師（醫師旁邊才會寫科別）。
   goal 裡的資訊如果「整頁（包含 offscreen 元素）都沒有」，代表要到後面的步驟才會出現，
   不要叫長輩捲動去找；先完成這一頁要選的東西。
1. 每次只給「一個」最該做的下一步。target_id 必須是 nodes 裡存在的 id；沒有目標時填 null。
   要點的元素如果在 offscreen，一樣可以用 tap 指定它（App 會自動提示往哪邊滑）。
   只有在整頁都找不到該做的事、或要找的東西確定在畫面外時，才用 scroll。
2. message 用口語、親切、簡短的繁體中文（一般 30 字以內；列出選項時可到 80 字）。不要用英文或專業術語。
   稱呼一律用「您」，不要用阿公、阿嬤、伯伯、先生、小姐等會假設年齡或性別的稱呼。
3. action 只能是以下其中一個：
   - tap：請長輩點某個按鈕或連結（必須有 target_id）
   - input：請長輩在某個欄位輸入資料（必須有 target_id），說明要填什麼，例如「請在這裡輸入您的身分證字號」。絕對不要自己寫出任何個人資料。
   - scroll：要找的東西不在畫面上，請長輩上下滑動（target_id 為 null）
   - wait：網頁還在載入，或暫時看不出下一步（target_id 為 null）
   - need_user：需要長輩自己或家人處理的步驟，例如驗證碼、登入、讀健保卡。最後的「確認／送出掛號」按鈕也用 need_user，
     並提醒長輩先檢查資料再自己按下；可以用 target_id 指出那個按鈕。
   - done：畫面已經顯示掛號成功或完成。
4. 在搜尋結果頁時，引導點進目標醫院「官方」的網路掛號頁，避開廣告和非官方網站。
5. 如果畫面和掛號無關或走錯了，引導回上一頁或回到醫院首頁。
6. 看到 [身分證]、[電話] 是已經遮蔽的個資，照常處理即可。
7. 如果 history 最後一步看起來已經完成（畫面已經變了），不要重複同一個指示。
8. 選科別、日期、時段、醫師時，不要替使用者做決定：
   - 只有在 goal「明確指定」而且這一頁「剛好只有一個」符合的選項時，才用 tap 指向它（日期要用 today 換算）。
   - 其他情況（goal 沒指定、指定得不夠明確、或有好幾個都符合）一律用 need_user、target_id 填 null，
     在 message 用文字「實際列出」可以選的項目名稱讓使用者自己選，例如：
     「可以選：上午診、下午診、夜診，請點您要的時段」、「骨科有蕭○○、王○○醫師，請點您要看的醫師」。
     只列出符合 goal 的項目（例如 goal 是骨科，就只列骨科醫師）。
     選項太多時列出前幾個並說「還有其他」。
   - goal 指定的日期或時段在這一頁沒有（例如額滿、沒開診），用 need_user 說明並列出還有哪些可以選。
10. 不要假設使用者的年齡、性別或身分。表單要填性別、年齡、生日、身分別（初診／複診）等資料時，
    用 input 或 need_user 請本人自己填寫或選擇，不要替他選。
9. confidence：你對這一步有多少把握（0 到 1 的數字）。`;

const CHAT_PROMPT = `你是「AI 就醫夥伴」，正在手機上一步一步引導台灣的長輩完成醫院網路掛號。
引導途中，長輩打開了對話視窗跟你說話：可能是提問、遇到困難，或想修改需求（換醫院、換科別、換時間…）。

你會收到 JSON：
- goal：目前的掛號目標
- chat：之前的對話（由舊到新，role 是 user 或 assistant）
- message：長輩這次說的話
- today：今天的日期與星期（台灣時間）
- screen：長輩打開對話前看到的網頁（url、title 和元素清單，可能是空的；offscreen 的元素要捲動才看得到）

你只能回覆一個 JSON 物件，不要有其他文字，格式如下：
{"reply": "好的，幫您改成掛內科。關掉對話後，我會帶您重新選科別。", "new_goal": "醫院：光田綜合醫院，科別：內科"}

規則：
1. reply 用口語、親切、簡短的繁體中文（80 字以內），不要用英文或專業術語。
   稱呼一律用「您」，不要用阿公、阿嬤、伯伯、先生、小姐等會假設年齡或性別的稱呼，也不要假設使用者的年齡、性別或身分。
   有好幾個選項時，用文字列出來讓使用者自己選，不要替他決定。
2. 長輩想修改需求時，new_goal 填「修改後完整的目標」：沒改到的部分照原本的 goal 保留，
   格式和 goal 一樣（例如「醫院：…，科別：…，時間：…」）。沒有修改時 new_goal 填 null。
3. 長輩問「要按哪裡、找不到」時，用畫面上看得到的文字和大概位置說明（例如「畫面中間偏下、寫著『下一步』的藍色按鈕」），
   不要說元素的 id。並告訴長輩關掉對話後，橘色框會指出位置。
4. 長輩問醫療問題時，可以給簡單的一般說明，但要提醒以醫師判斷為準；如果聽起來是緊急狀況（胸痛、呼吸困難、意識不清、大量出血等），
   請長輩立刻撥打 119，不要繼續掛號。
5. 不要詢問或重複任何個人資料（身分證字號、電話、生日等）。看到 [身分證]、[電話] 是已經遮蔽的個資。
6. 不知道答案時就老實說，並建議請家人或打電話給醫院詢問。`;

const app = express();
app.use(express.json({ limit: '300kb' }));

app.get('/health', (req, res) => {
  res.json({ ok: true, model: MODEL, provider: hostOf(BASE_URL) });
});

app.post('/guide/next', async (req, res) => {
  const { goal, history, screen } = req.body ?? {};
  if (typeof goal !== 'string' || !goal.trim() || !screen || !Array.isArray(screen.nodes)) {
    return res.status(400).json({ error: 'bad_request' });
  }

  const nodes = screen.nodes.slice(0, MAX_NODES);
  const ids = new Set(nodes.map((n) => n.id));
  const userContent = JSON.stringify({
    today: todayInTaiwan(),
    goal: goal.trim(),
    history: Array.isArray(history) ? history.slice(-MAX_HISTORY) : [],
    chat: cleanChat(req.body.chat),
    url: typeof screen.url === 'string' ? screen.url : '',
    title: typeof screen.title === 'string' ? screen.title : '',
    nodes,
  });

  try {
    const aiRes = await callAiWithRetry(SYSTEM_PROMPT, userContent);
    if (!aiRes.ok) {
      const detail = await aiRes.text();
      console.error(`[guide] AI 錯誤 ${aiRes.status}: ${detail.slice(0, 300)}`);
      return res.status(aiRes.status === 429 ? 429 : 502).json({ error: aiRes.status === 429 ? 'rate_limited' : 'ai_error' });
    }

    const data = await aiRes.json();
    const content = data?.choices?.[0]?.message?.content ?? '';
    const step = sanitize(parseJson(content), ids);
    console.log(
      `[guide] ${hostOf(screen.url)} nodes=${nodes.length}（畫面外 ${nodes.filter((n) => n.offscreen).length}）→ ${step.action}` +
        ` #${step.target_id ?? '-'} (${step.confidence.toFixed(2)}) ${step.message}`,
    );
    res.json(step);
  } catch (err) {
    console.error(`[guide] 失敗: ${err.message}`);
    res.status(502).json({ error: 'ai_unavailable' });
  }
});

app.post('/guide/chat', async (req, res) => {
  const { goal, message, screen } = req.body ?? {};
  if (typeof goal !== 'string' || !goal.trim() || typeof message !== 'string' || !message.trim()) {
    return res.status(400).json({ error: 'bad_request' });
  }

  const userContent = JSON.stringify({
    today: todayInTaiwan(),
    goal: goal.trim(),
    chat: cleanChat(req.body.chat),
    message: message.trim().slice(0, 500),
    screen: {
      url: typeof screen?.url === 'string' ? screen.url : '',
      title: typeof screen?.title === 'string' ? screen.title : '',
      nodes: Array.isArray(screen?.nodes) ? screen.nodes.slice(0, MAX_NODES) : [],
    },
  });

  try {
    const aiRes = await callAiWithRetry(CHAT_PROMPT, userContent);
    if (!aiRes.ok) {
      const detail = await aiRes.text();
      console.error(`[chat] AI 錯誤 ${aiRes.status}: ${detail.slice(0, 300)}`);
      return res.status(aiRes.status === 429 ? 429 : 502).json({ error: aiRes.status === 429 ? 'rate_limited' : 'ai_error' });
    }

    const data = await aiRes.json();
    const parsed = parseJson(data?.choices?.[0]?.message?.content ?? '');
    const reply = String(parsed.reply ?? '').trim().slice(0, MAX_REPLY) || '不好意思，我沒聽清楚，可以再說一次嗎？';
    let newGoal = typeof parsed.new_goal === 'string' ? parsed.new_goal.trim().slice(0, MAX_GOAL) : null;
    if (!newGoal || newGoal === goal.trim()) newGoal = null;

    // log 不記錄對話內容（可能含個資），只記長度與是否改了目標
    console.log(`[chat] 訊息 ${message.trim().length} 字 → 回覆 ${reply.length} 字${newGoal ? `，目標改為：${newGoal}` : ''}`);
    res.json({ reply, new_goal: newGoal });
  } catch (err) {
    console.error(`[chat] 失敗: ${err.message}`);
    res.status(502).json({ error: 'ai_unavailable' });
  }
});

/** 台灣時間的今天，例如「2026-11-24（星期二）」。 */
function todayInTaiwan() {
  const now = new Date();
  const date = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Taipei' }).format(now);
  const weekday = new Intl.DateTimeFormat('zh-TW', { timeZone: 'Asia/Taipei', weekday: 'long' }).format(now);
  return `${date}（${weekday}）`;
}

/** 只留最近的對話、限制長度、角色只允許 user / assistant。 */
function cleanChat(chat) {
  if (!Array.isArray(chat)) return [];
  return chat
    .filter((m) => m && (m.role === 'user' || m.role === 'assistant') && typeof m.text === 'string')
    .slice(-MAX_CHAT)
    .map((m) => ({ role: m.role, text: m.text.slice(0, 500) }));
}

async function callAiWithRetry(systemPrompt, userContent) {
  let aiRes = await callAi(systemPrompt, userContent);
  if (aiRes.status === 429 || aiRes.status === 503) {
    // 429：免費額度的每分鐘次數限制；503：模型暫時塞車。等一下再試一次
    console.warn(`[guide] AI 暫時無法服務（${aiRes.status}），稍後重試一次`);
    await sleep(RATE_LIMIT_RETRY_MS);
    aiRes = await callAi(systemPrompt, userContent);
  }
  return aiRes;
}

function callAi(systemPrompt, userContent) {
  return fetch(`${BASE_URL}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${API_KEY}`,
    },
    body: JSON.stringify({
      model: MODEL,
      temperature: 0.2,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userContent },
      ],
      // json_object 各家 OpenAI 相容服務都支援（Gemini 對 json_schema 支援不一致）
      response_format: { type: 'json_object' },
      ...(REASONING_EFFORT ? { reasoning_effort: REASONING_EFFORT } : {}),
    }),
    signal: AbortSignal.timeout(25_000),
  });
}

/** 解析 AI 回覆；容忍外面包了 ```json ``` 或多餘文字。 */
function parseJson(text) {
  const cleaned = String(text).replace(/```(?:json)?/gi, '').trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    const start = cleaned.indexOf('{');
    const end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(cleaned.slice(start, end + 1));
      } catch {
        /* 落到下面 */
      }
    }
    console.warn(`[guide] 無法解析 AI 回覆：${cleaned.slice(0, 200)}`);
    return {};
  }
}

/** 確保回傳格式正確、target_id 真的存在於畫面上。 */
function sanitize(step, ids) {
  let action = ACTIONS.includes(step.action) ? step.action : 'wait';
  const rawId = typeof step.target_id === 'string' ? Number(step.target_id) : step.target_id;
  let targetId = Number.isInteger(rawId) && ids.has(rawId) ? rawId : null;
  if ((action === 'tap' || action === 'input') && targetId === null) action = 'wait';
  if (action === 'scroll' || action === 'wait') targetId = null;

  const message = String(step.message ?? '').trim().slice(0, MAX_MESSAGE) || '請稍等一下';
  const confidence = Math.min(1, Math.max(0, Number(step.confidence) || 0));
  return { action, target_id: targetId, message, confidence };
}

/** log 只記錄網域，不記完整網址（可能含個資參數）。 */
function hostOf(url) {
  try {
    return new URL(url.startsWith('http') ? url : `https://${url}`).host;
  } catch {
    return '(no url)';
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** 啟動時實際問一次 AI，確認金鑰、模型都能用；只顯示提醒，不影響啟動。 */
async function checkModel() {
  try {
    const t0 = Date.now();
    const r = await callAi(SYSTEM_PROMPT, '{"goal":"測試","nodes":[{"id":0,"role":"button","text":"網路掛號","clickable":true}]}');
    const body = await r.text();
    if (r.ok) {
      console.log(`✓ 金鑰有效，模型「${MODEL}」可用（回應 ${Date.now() - t0}ms）`);
      return;
    }
    console.warn(`⚠ AI 測試失敗（HTTP ${r.status}）：${body.slice(0, 300)}`);
    if (r.status === 404) await suggestModels();
  } catch (err) {
    console.warn(`⚠ AI 測試失敗：${err.message}`);
  }
}

async function suggestModels() {
  try {
    const r = await fetch(`${BASE_URL}/models`, {
      headers: { Authorization: `Bearer ${API_KEY}` },
      signal: AbortSignal.timeout(10_000),
    });
    if (!r.ok) return;
    const names = ((await r.json()).data ?? []).map((m) => String(m.id).replace(/^models\//, ''));
    const flash = names.filter((n) => /flash/.test(n) && !/tts|image|audio|live/.test(n));
    console.warn(`  可以把 .env 的 GUIDE_AI_MODEL 改成其中一個：${flash.join(', ')}`);
  } catch {
    /* 忽略 */
  }
}

app.listen(PORT, () => {
  console.log(`AI 就醫夥伴引導伺服器已啟動：http://localhost:${PORT}（${hostOf(BASE_URL)} / ${MODEL}）`);
  checkModel();
});
