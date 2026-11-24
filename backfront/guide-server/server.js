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

// Cloud Run 等雲端平台會用 PORT 指定埠號；本機開發用 GUIDE_PORT（預設 3001）
const PORT = Number(process.env.PORT || process.env.GUIDE_PORT) || 3001;

// ── 放到雲端時的保護（網址是公開的）──
// 通行碼（選填）：有設定時，App 必須在 X-Guide-Token 標頭帶上相同的值
const ACCESS_TOKEN = (process.env.GUIDE_ACCESS_TOKEN || '').trim();
// 每支手機（IP）每 10 分鐘最多幾次、全部加起來每天最多幾次
const RATE_LIMIT_PER_10MIN = Number(process.env.GUIDE_RATE_LIMIT) || 120;
const DAILY_LIMIT = Number(process.env.GUIDE_DAILY_LIMIT) || 2000;
const BASE_URL = (process.env.GUIDE_AI_BASE_URL || 'https://generativelanguage.googleapis.com/v1beta/openai')
  .replace(/\/+$/, '');
const API_KEY = process.env.GUIDE_AI_API_KEY;
const MODEL = process.env.GUIDE_AI_MODEL || 'gemini-3.1-flash-lite';
// 思考程度（none / low / medium / high）：越低回應越快。留空則不送，用模型預設值。
const REASONING_EFFORT = (process.env.GUIDE_AI_REASONING_EFFORT || '').trim();

// 塞車（503）、額度用完（429）、模型下架（404）或逾時時，依序改用下一個模型。
// 同一家（同一把金鑰）的備援模型：逗號分隔；用 Gemini 時沒設定就用預設清單。
const IS_GEMINI = BASE_URL.includes('generativelanguage.googleapis.com');
const DEFAULT_GEMINI_FALLBACKS = 'gemini-3.5-flash-lite,gemini-flash-lite-latest,gemini-flash-latest';
const FALLBACK_MODELS = splitList(process.env.GUIDE_AI_FALLBACK_MODELS ?? (IS_GEMINI ? DEFAULT_GEMINI_FALLBACKS : ''));
// 第二家服務（選填，例如 Groq）：三個都有填才會使用
const BACKUP_BASE_URL = (process.env.GUIDE_AI_BACKUP_BASE_URL || '').trim().replace(/\/+$/, '');
const BACKUP_API_KEY = (process.env.GUIDE_AI_BACKUP_API_KEY || '').trim();
const BACKUP_MODELS = splitList(process.env.GUIDE_AI_BACKUP_MODELS || '');

const CANDIDATES = buildCandidates();
const COOLDOWN_MS = 60_000;     // 失敗的模型休息 1 分鐘，這段期間直接跳過
const TOTAL_BUDGET_MS = 26_000; // App 最多等 30 秒，整條備援要在這之前結束
const PER_TRY_MS = 12_000;      // 有備援時，每個模型最多等 12 秒
const cooldownUntil = new Map();

function splitList(text) {
  return String(text).split(',').map((x) => x.trim()).filter(Boolean);
}

function buildCandidates() {
  const list = [];
  const add = (baseUrl, apiKey, model) => {
    if (!model || list.some((c) => c.baseUrl === baseUrl && c.model === model)) return;
    list.push({ baseUrl, apiKey, model, label: `${hostOf(baseUrl)} / ${model}` });
  };
  add(BASE_URL, API_KEY, MODEL);
  FALLBACK_MODELS.forEach((m) => add(BASE_URL, API_KEY, m));
  if (BACKUP_BASE_URL && BACKUP_API_KEY) BACKUP_MODELS.forEach((m) => add(BACKUP_BASE_URL, BACKUP_API_KEY, m));
  return list;
}

if (!API_KEY) {
  console.error('缺少 GUIDE_AI_API_KEY：請複製 .env.example 成 .env 並填入你自己的金鑰（Gemini 金鑰可到 Google AI Studio 免費申請）。');
  process.exit(1);
}

const ACTIONS = ['tap', 'input', 'scroll', 'wait', 'need_user', 'done'];
const MAX_NODES = 650;
const MAX_HISTORY = 8;
const MAX_MESSAGE = 100;
const MAX_SUMMARY = 100;
const MAX_CHAT = 10;
const MAX_REPLY = 200;
const MAX_GOAL = 120;
const RATE_LIMIT_RETRY_MS = 3_000;

const SYSTEM_PROMPT = `你是「AI 就醫夥伴」，在手機的 Chrome 上一步一步引導台灣的長輩完成醫院網路掛號。

你會收到 JSON：
- today：今天的日期與星期（台灣時間），用來換算「下週一」「明天」這類時間
- goal：長輩想掛的醫院、科別、時間
- history：之前經過的每一頁（page 是當時這一頁的摘要）和給過的指示（由舊到新），可以從這裡知道前面已經選了什麼
- url、title：目前的網址和網頁標題（可能是空的）
- nodes：這個網頁的元素，依網頁上的順序排列。id 是編號；role 是 button / link / input / select / checkbox / radio / text；
  text 是顯示的文字；input 只會給 hint（欄位提示）和 filled（是否已經填了），不會給內容。
  沒有 offscreen 的元素在畫面上看得到；offscreen 是 "above" / "below" 的元素在畫面上方／下方，要捲動才看得到；
  "unknown" 表示不在畫面上，但不確定在上方還是下方（請使用者上下滑動找）。
- chat：長輩在引導過程中跟你的對話（可能是空的）。裡面提到的困難或需求要考慮進去，
  例如長輩說「找不到按鈕」，就給更清楚的位置描述。

你只能回覆一個 JSON 物件，不要有其他文字，格式如下（page_summary 一定要放第一個）：
{"page_summary": "選擇看診日期：可選 11/25～12/3，週日休診", "action": "tap", "target_id": 3, "focus_id": null, "message": "請點「11/30 (一)」", "confidence": 0.9}

做法：先讀完「整個網頁」（包含 offscreen 的元素），確認這一頁的資訊，寫進 page_summary；再根據這些資訊決定下一步。
- page_summary：用一兩句繁體中文（80 字以內）說明「這一頁在要求做什麼」和「跟掛號有關的重要資訊」，
  例如可選的日期範圍、有哪些時段或醫師。
  網頁上的「休診、額滿、停診、截止時間」和「※、注意、提醒」開頭的注意事項一定要寫進去（例如「11/29 休診；初診請帶健保卡」）。
  只寫網頁上真的有的資訊，不要猜；不要只重複下一步的指示。

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
4. 在 Google 等搜尋結果頁時，先看完整頁的結果，引導點進目標醫院「官方網站」的網路掛號頁：
   - 真正的搜尋結果連結，文字裡通常會有網站名稱或網址（例如「cych.org.tw › …」「https://…」）。
   - 「相關搜尋」「其他人也搜尋了」「更多問題」裡的項目只會再搜尋一次，不要點。
   - 避開廣告（標示「贊助」「廣告」）和非官方網站。
   - 如果 history 顯示已經在搜尋頁之間來回好幾次，請直接選最像官方網站的結果。
5. 如果畫面和掛號無關或走錯了，引導回上一頁或回到醫院首頁。
6. 看到 [身分證]、[電話] 是已經遮蔽的個資，照常處理即可。
7. 如果 history 最後一步看起來已經完成（畫面已經變了），不要重複同一個指示。
8. 【有多個選項時讓使用者自己選】選院區、科別、日期、時段、醫師等有好幾個選項時，不要替使用者做決定：
   - 只有在使用者「自己說過」要哪一個時，才用 tap 指向它。「自己說過」只算兩種：
     (1) goal 裡有寫（一開始輸入的）；(2) chat 裡使用者（role 為 user）親口說過，例如「我要掛黃○○醫師」「改成下午」。
     而且這一頁要「剛好只有一個」符合的選項（日期要用 today 換算）。
   - 不能因為某個選項看起來比較好、比較早、比較近，或是網頁預設、第一個，就替使用者選。
   - 其他情況（沒說過、說得不夠明確、或有好幾個都符合）一律用 need_user、target_id 填 null，
     在 message 用文字「實際列出」可以選的項目名稱讓使用者自己選，例如：
     「可以選：上午診、下午診、夜診，請點您要的時段」、「骨科有蕭○○、王○○醫師，請點您要看的醫師」。
     只列出符合 goal 的項目（例如 goal 是骨科，就只列骨科醫師）。
     選項太多時列出前幾個並說「還有其他」。
   - 用 need_user 時，只要網頁上有可以選的項目（日期、區間、時段、醫師），focus_id 就「一定要」填其中最相關的一個的 id
     （例如你列出的第一個選項）。這只用來告訴 App 選項在網頁的哪裡、提示使用者往哪邊滑，不代表替他選。
     用 scroll 時，focus_id 也填要找的東西的 id。真的沒有可選的項目才填 null。
   - 某個時段額滿時，要再看同一天的其他時段（上午、下午、夜間）還有沒有「可以點」的醫師，有的話列出來；
     都沒有才建議改其他日期，並指出日期或區間選項的位置（focus_id）。
   - goal 指定的日期或時段在這一頁沒有（例如額滿、沒開診），用 need_user 說明並列出還有哪些可以選。
9. 【表單先填完再送出】頁面上有要填的欄位（input 的 filled 為 false，例如身分證、病歷號、生日、電話、驗證碼）時：
    - 一次只指向「第一個還沒填的欄位」，用 input 或 need_user（target_id 指向那個欄位），說明要填什麼。
    - 所有欄位都填好（filled 都是 true）之後，才指向送出／確認／下一步按鈕，並提醒先檢查資料。
    - 搜尋框（例如「搜尋」「關鍵字」）不算要填的欄位。
10. 不要假設使用者的年齡、性別或身分。表單要填性別、年齡、生日、身分別（初診／複診）等資料時，
    用 input 或 need_user 請本人自己填寫或選擇，不要替他選。
11. confidence：你對這一步有多少把握（0 到 1 的數字）。`;

const CHAT_PROMPT = `你是「AI 就醫夥伴」，正在手機上一步一步引導台灣的長輩完成醫院網路掛號。
引導途中，長輩打開了對話視窗跟你說話：可能是提問、遇到困難，或想修改需求（換醫院、換科別、換時間…）。

你會收到 JSON：
- goal：目前的掛號目標
- chat：之前的對話（由舊到新，role 是 user 或 assistant）
- message：長輩這次說的話
- today：今天的日期與星期（台灣時間）
- screen：長輩打開對話前看到的網頁（url、title 和元素清單，可能是空的；offscreen 的元素要捲動才看得到）

你只能回覆一個 JSON 物件，不要有其他文字，格式如下：
{"reply": "好的，幫您改成掛內科。關掉對話後，我會帶您重新選科別。", "new_goal": "醫院：光田綜合醫院，科別：內科", "switch_hospital": false}

規則：
1. reply 用口語、親切、簡短的繁體中文（80 字以內），不要用英文或專業術語。
   稱呼一律用「您」，不要用阿公、阿嬤、伯伯、先生、小姐等會假設年齡或性別的稱呼，也不要假設使用者的年齡、性別或身分。
   有好幾個選項時，用文字列出來讓使用者自己選，不要替他決定。
2. 長輩想修改需求、或說出自己的選擇時（例如「我要掛黃○○醫師」「改成下午」「選沙鹿院區」），
   new_goal 填「修改後完整的目標」，把選擇加進去（例如「…，醫師：黃○○」「…，院區：沙鹿」）；沒改到的部分照原本的 goal 保留，
   格式和 goal 一樣（例如「醫院：…，科別：…，時間：…」）。沒有修改時 new_goal 填 null。
   【換醫院】只有長輩「明確說要換另一家醫院」時（例如「我要改掛榮總」「不要這家醫院了，換別家」），
   才把 switch_hospital 填 true、new_goal 填 null，reply 告訴他「好的，我現在帶您回到 App 重新選擇醫院」。
   App 會自動帶他回去，不要叫他關掉對話視窗或自己操作。
   其他情況 switch_hospital 一律填 false。拒絕某個科別、院區、醫師、時段（例如「我沒有要選內科部」「不要這個醫師」），
   或抱怨你舉的例子，都「不是」換醫院。
   【拒絕某個選項】長輩說不要某個選項時：switch_hospital 填 false；new_goal 填 null（goal 原本就指定了那個選項時，才把它從 new_goal 拿掉）；
   reply 先道歉說明那只是舉例、不會替他選，再請他說出想要的，或列出其他可以選的項目。
3. 長輩問「要按哪裡、找不到」時，用畫面上看得到的文字和大概位置說明（例如「畫面中間偏下、寫著『下一步』的藍色按鈕」），
   不要說元素的 id。並告訴長輩關掉對話後，橘色框會指出位置。
4. 長輩問醫療問題時，可以給簡單的一般說明，但要提醒以醫師判斷為準；如果聽起來是緊急狀況（胸痛、呼吸困難、意識不清、大量出血等），
   請長輩立刻撥打 119，不要繼續掛號。
5. 不要詢問或重複任何個人資料（身分證字號、電話、生日等）。看到 [身分證]、[電話] 是已經遮蔽的個資。
6. 不知道答案時就老實說，並建議請家人或打電話給醫院詢問。`;

const app = express();
app.set('trust proxy', true); // Cloud Run 在代理後面，才能拿到真正的手機 IP
app.use(express.json({ limit: '300kb' }));

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    model: MODEL,
    provider: hostOf(BASE_URL),
    fallbacks: CANDIDATES.slice(1).map((c) => c.label),
    token_required: Boolean(ACCESS_TOKEN),
  });
});

// 通行碼與次數限制：只保護會花到 AI 額度的 /guide/*
const ipHits = new Map(); // ip -> [時間戳記…]
let dailyCount = 0;
let dailyDate = '';
app.use('/guide', (req, res, next) => {
  if (ACCESS_TOKEN && req.get('X-Guide-Token') !== ACCESS_TOKEN) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  const today = todayInTaiwan();
  if (today !== dailyDate) {
    dailyDate = today;
    dailyCount = 0;
  }
  if (dailyCount >= DAILY_LIMIT) {
    console.warn(`[limit] 今天已達上限 ${DAILY_LIMIT} 次`);
    return res.status(429).json({ error: 'daily_limit' });
  }

  const now = Date.now();
  const ip = req.ip || 'unknown';
  const recent = (ipHits.get(ip) || []).filter((t) => now - t < 10 * 60_000);
  if (recent.length >= RATE_LIMIT_PER_10MIN) {
    console.warn('[limit] 單一裝置請求太頻繁');
    return res.status(429).json({ error: 'rate_limited' });
  }
  recent.push(now);
  ipHits.set(ip, recent);
  if (ipHits.size > 5_000) ipHits.clear(); // 避免記憶體一直長大

  dailyCount++;
  next();
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
      `[guide] ${hostOf(screen.url)} nodes=${nodes.length}（畫面外 ${nodes.filter((n) => n.offscreen).length}）` +
        `\n        這一頁：${step.page_summary || '-'}` +
        `\n        → ${step.action} #${step.target_id ?? '-'} (${step.confidence.toFixed(2)}) ${step.message}`,
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
    let reply = String(parsed.reply ?? '').trim().slice(0, MAX_REPLY) || '不好意思，我沒聽清楚，可以再說一次嗎？';
    let newGoal = typeof parsed.new_goal === 'string' ? parsed.new_goal.trim().slice(0, MAX_GOAL) : null;
    if (!newGoal || newGoal === goal.trim()) newGoal = null;

    // 換醫院：會把使用者帶離引導，所以要同時符合「AI 判斷要換」和「長輩這句話真的在講換醫院」才算；
    // 新目標裡的醫院明顯是另一家（不是同一家的寫法差異，例如台／臺、全名／簡稱）也算。
    const aiSaysSwitch = parsed.switch_hospital === true || parsed.switch_hospital === 'true';
    const oldHospital = hospitalOf(goal);
    const newHospital = newGoal ? hospitalOf(newGoal) : '';
    const goalHospitalChanged = Boolean(newHospital && oldHospital && !sameHospital(newHospital, oldHospital));
    const switchHospital = (aiSaysSwitch || goalHospitalChanged) && mentionsHospitalChange(message);
    if ((aiSaysSwitch || goalHospitalChanged) && !switchHospital) {
      console.warn('[chat] AI 判斷要換醫院，但訊息沒有提到換醫院，忽略');
      // 醫院名稱被 AI 改寫（例如簡稱改全名）時，保留原本的醫院
      if (goalHospitalChanged) newGoal = newGoal.replace(newHospital, oldHospital);
      if (/App|重新選擇醫院|換醫院/.test(reply)) {
        reply = '不好意思，我會繼續在這家醫院幫您。剛剛提到的只是舉例，不會替您選。請告訴我您想要哪一個，或直接點畫面上您要的項目。';
      }
    }
    if (switchHospital) newGoal = null;

    // log 不記錄對話內容（可能含個資），只記長度與是否改了目標
    console.log(
      `[chat] 訊息 ${message.trim().length} 字 → 回覆 ${reply.length} 字` +
        `${newGoal ? `，目標改為：${newGoal}` : ''}${switchHospital ? '，要換醫院（回 App 重新選擇）' : ''}`,
    );
    res.json({ reply, new_goal: newGoal, switch_hospital: switchHospital });
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

/** 從「醫院：…，科別：…」取出醫院名稱（去掉空白），取不到就回傳空字串。 */
function hospitalOf(goal) {
  const m = String(goal).match(/醫院[：:]\s*([^，,；;\n]+)/);
  return m ? m[1].replace(/\s+/g, '') : '';
}

/** 同一家醫院的不同寫法（台／臺、全名包含簡稱）都當作同一家。 */
function sameHospital(a, b) {
  const norm = (s) => s.replace(/台/g, '臺').replace(/[()（）]/g, '');
  const x = norm(a);
  const y = norm(b);
  return x === y || x.includes(y) || y.includes(x);
}

/** 長輩這句話是不是在講換醫院（院區、科別、醫師等不算）。 */
function mentionsHospitalChange(message) {
  const text = String(message).replace(/院區|分院區/g, '');
  return /醫院|診所|醫學中心|附醫|榮總|長庚|馬偕|慈濟|國泰|亞東|新光|奇美|彰基|秀傳|光田|童綜合|中山附|中國附|成大|台大|臺大|換一家|換家|別家|另一家|其他家/.test(text);
}

/** 只留最近的對話、限制長度、角色只允許 user / assistant。 */
function cleanChat(chat) {
  if (!Array.isArray(chat)) return [];
  return chat
    .filter((m) => m && (m.role === 'user' || m.role === 'assistant') && typeof m.text === 'string')
    .slice(-MAX_CHAT)
    .map((m) => ({ role: m.role, text: m.text.slice(0, 500) }));
}

/**
 * 依序嘗試候選模型，回傳第一個成功的回應。
 * 全部失敗時回傳最後一個錯誤（呼叫端照原本的方式處理 !ok）。
 */
async function callAiWithRetry(systemPrompt, userContent) {
  // 只有一個模型時，維持原本的做法：塞車就等 3 秒再試一次
  if (CANDIDATES.length === 1) {
    const only = CANDIDATES[0];
    let aiRes = await callAi(only, systemPrompt, userContent, 25_000);
    if (aiRes.status === 429 || aiRes.status === 503) {
      console.warn(`[ai] AI 暫時無法服務（${aiRes.status}），稍後重試一次`);
      await sleep(RATE_LIMIT_RETRY_MS);
      aiRes = await callAi(only, systemPrompt, userContent, 25_000);
    }
    return aiRes;
  }

  const start = Date.now();
  const now = Date.now();
  const ready = CANDIDATES.filter((c) => (cooldownUntil.get(c.label) || 0) <= now);
  const order = ready.length > 0 ? ready : CANDIDATES; // 全部都在休息就照樣再試一輪
  let lastStatus = 503;
  let lastDetail = '';

  for (const c of order) {
    const remaining = TOTAL_BUDGET_MS - (Date.now() - start);
    if (remaining < 2_000) break;
    try {
      const aiRes = await callAi(c, systemPrompt, userContent, Math.min(PER_TRY_MS, remaining));
      if (aiRes.ok) {
        if (c !== CANDIDATES[0]) console.log(`[ai] 主要模型無法使用，這次改用備援：${c.label}`);
        return aiRes;
      }
      lastStatus = aiRes.status;
      lastDetail = (await aiRes.text()).slice(0, 300);
      coolDown(c, `HTTP ${aiRes.status}`);
    } catch (err) {
      lastStatus = 504;
      lastDetail = err.message;
      coolDown(c, err.name === 'TimeoutError' ? '逾時' : err.message);
    }
  }
  return new Response(lastDetail || 'all models unavailable', { status: lastStatus === 429 ? 429 : 503 });
}

function coolDown(candidate, reason) {
  cooldownUntil.set(candidate.label, Date.now() + COOLDOWN_MS);
  console.warn(`[ai] ${candidate.label} 無法使用（${reason}），先休息 1 分鐘，改試下一個`);
}

function callAi(candidate, systemPrompt, userContent, timeoutMs) {
  return fetch(`${candidate.baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${candidate.apiKey}`,
    },
    body: JSON.stringify({
      model: candidate.model,
      temperature: 0.2,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userContent },
      ],
      // json_object 各家 OpenAI 相容服務都支援（Gemini 對 json_schema 支援不一致）
      response_format: { type: 'json_object' },
      ...(REASONING_EFFORT && candidate.baseUrl === BASE_URL ? { reasoning_effort: REASONING_EFFORT } : {}),
    }),
    signal: AbortSignal.timeout(timeoutMs),
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
  const pageSummary = String(step.page_summary ?? '').trim().slice(0, MAX_SUMMARY);
  const rawFocus = typeof step.focus_id === 'string' ? Number(step.focus_id) : step.focus_id;
  const focusId = targetId === null && Number.isInteger(rawFocus) && ids.has(rawFocus) ? rawFocus : null;
  return { page_summary: pageSummary, action, target_id: targetId, focus_id: focusId, message, confidence };
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

/** 啟動時把每個候選模型都實際問一次，確認能不能用；只顯示提醒，不影響啟動。 */
async function checkModel() {
  const probe = '{"goal":"測試","nodes":[{"id":0,"role":"button","text":"網路掛號","clickable":true}]}';
  const results = await Promise.all(
    CANDIDATES.map(async (c, i) => {
      const tag = i === 0 ? '主要' : `備援 ${i}`;
      const t0 = Date.now();
      try {
        const r = await callAi(c, SYSTEM_PROMPT, probe, 25_000);
        const body = await r.text();
        if (r.ok) return { ok: true, line: `✓ ${tag}：${c.label} 可用（回應 ${Date.now() - t0}ms）` };
        return { ok: false, status: r.status, line: `⚠ ${tag}：${c.label} 目前無法使用（HTTP ${r.status}）${r.status === 404 ? '：找不到這個模型' : ''}` };
      } catch (err) {
        return { ok: false, line: `⚠ ${tag}：${c.label} 目前無法使用（${err.message}）` };
      }
    }),
  );
  results.forEach((r) => (r.ok ? console.log(r.line) : console.warn(r.line)));
  if (!results.some((r) => r.ok)) console.warn('⚠ 所有模型目前都無法使用，請檢查金鑰，或稍後再試（免費版可能在塞車）');
  if (results[0] && results[0].status === 404) await suggestModels();
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
  console.log(`AI 就醫夥伴引導伺服器已啟動：http://localhost:${PORT}`);
  console.log(`使用順序：${CANDIDATES.map((c) => c.label).join(' → ')}`);
  console.log(`保護：通行碼${ACCESS_TOKEN ? '已設定' : '未設定'}；每台裝置每 10 分鐘 ${RATE_LIMIT_PER_10MIN} 次；每天最多 ${DAILY_LIMIT} 次`);
  checkModel();
});
