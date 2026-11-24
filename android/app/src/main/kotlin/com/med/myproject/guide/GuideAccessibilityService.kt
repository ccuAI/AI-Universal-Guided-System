package com.med.myproject.guide

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.graphics.Rect
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONObject

/**
 * AI 就醫夥伴：在 Chrome 上做掛號引導的無障礙服務。
 *
 * 只有在 Flutter 端按下「開始引導」（GuideSession.isRunning）而且前景是 Chrome 時，
 * 才會讀取畫面；其他 App 的事件只用來「把引導框藏起來」，不會讀取內容。
 *
 * 迴圈：事件 → 等畫面穩定 → 讀取畫面 → 需要時問 AI → 畫框 → 等使用者操作…
 */
class GuideAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "Guide"
        const val CHROME_PACKAGE = "com.android.chrome"
        private const val SYSTEM_UI_PACKAGE = "com.android.systemui"

        private const val SETTLE_DELAY_MS = 800L      // 畫面變化後等多久再讀
        private const val TYPING_DELAY_MS = 2_000L    // 使用者打字時等久一點
        private const val SCROLL_DELAY_MS = 150L      // 捲動只重新對齊框，可以快
        private const val MIN_AI_INTERVAL_MS = 1_500L // 兩次 AI 呼叫的最短間隔
        private const val LOW_CONFIDENCE = 0.5
        private const val CHAT_TIP = "不知道選哪個，可以按「對話」跟我說"

        // 表單還沒填完不要框送出按鈕
        private val SUBMIT_WORDS = Regex("送出|確認|確定|下一步|登入|提交|完成|submit|ok", RegexOption.IGNORE_CASE)
        private val FORM_FIELD_WORDS = Regex("身分證|居留證|證號|病歷|生日|出生|電話|手機|姓名|驗證碼|號碼|帳號|密碼")
        private val SEARCH_WORDS = Regex("搜尋|關鍵字|search", RegexOption.IGNORE_CASE)

        // 進入新網頁時先自動往下捲、讀完整頁再問 AI（有些手機的 Chrome 只提供畫面上的元素）
        private const val MAX_SCAN_SCREENS = 20       // 安全上限：一般網頁捲到底就會停
        private const val SCAN_SETTLE_MS = 450L       // 每捲一次等網頁畫好
        private const val SCAN_BACK_STEP_MS = 120L    // 捲回原位時每一步的間隔
        private const val MAX_PAGE_NODES = 600
        private const val BOTTOM_SAME_RATIO = 0.9     // 捲完畫面內容幾乎沒變，就當作已經到底
        private const val SAME_PAGE_RATIO = 0.6       // 畫面上的元素有幾成是已知的，就算同一頁
        private const val CACHE_REUSE_RATIO = 0.85    // 畫面上的元素有幾成在快取裡，才沿用整頁內容不重新捲動

        /** 給 GuideChannel 通知開始／停止用；服務沒開啟時為 null。 */
        @Volatile
        var instance: GuideAccessibilityService? = null
            private set
    }

    /** 目前框住的目標：靠「角色 + 文字 + 第幾個同名元素」在新畫面裡重新找到它。 */
    private data class TargetRef(
        val role: String,
        val label: String,
        val ordinal: Int,
        val message: String,
        /** AI 指定時目標在畫面外（"above" / "below"），用來提示往哪邊滑。 */
        val offscreen: String? = null,
        /** 只標示「選項在哪裡」：看得到時不畫框（不替使用者選），看不到時提示往哪邊滑。 */
        val focusOnly: Boolean = false,
    )

    private val handler = Handler(Looper.getMainLooper())
    private val api = GuideApiClient()
    private var overlay: OverlayController? = null

    private var currentTarget: TargetRef? = null
    private var lastUrl = ""

    /** 上次交給 AI 的整頁內容（角色|文字）：用來判斷使用者是不是還在同一頁。 */
    private var knownPageKeys: Set<String> = emptySet()

    /** 正在自動捲動讀整頁：這段期間忽略事件。 */
    private var scanning = false

    /** 下一次讀畫面一定要問 AI（例如 AI 說網頁還在載入）。 */
    private var forceNextAi = false

    /** 上次「從頭捲到尾」讀到的整頁內容：同一頁再問 AI 時直接沿用，不重新捲動。 */
    private var pageCache: ScreenSnapshot? = null

    private var lastAiAt = 0L
    private var requestInFlight = false
    private var pendingRefresh = false

    /** 對話視窗開著：不讀畫面、不畫框。 */
    private var chatOpen = false

    /** 上一次 AI 請求失敗：之後只在使用者按「重看」、換頁或有操作時才重試，避免一直打 API。 */
    private var lastFailed = false

    /** 使用者有操作（點擊、輸入、選取），代表可能完成了這一步。 */
    private var userActed = false

    private val refreshRunnable = Runnable { refresh(force = false) }
    private val forceRefreshRunnable = Runnable { refresh(force = true) }
    private val relocateRunnable = Runnable { relocateOnly() }

    // ───────────────────────── 生命週期 ─────────────────────────

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        overlay = OverlayController(
            service = this,
            onStop = { stopFromOverlay() },
            onRetry = { refresh(force = true) },
            onChat = { openChat() },
        )
        Log.d(TAG, "無障礙服務已連線")
        if (GuideSession.isRunning) onSessionStarted()
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        overlay?.removeAll()
        overlay = null
        api.shutdown()
        if (instance === this) instance = null
        super.onDestroy()
    }

    // ───────────────────────── 給 GuideChannel 呼叫 ─────────────────────────

    fun onSessionStarted() {
        resetState()
        overlay?.showControls()
        overlay?.showMessage("準備開始引導，請稍等…")
        handler.postDelayed(refreshRunnable, 1_500L)
    }

    fun onSessionStopped() {
        resetState()
        overlay?.removeAll()
    }

    /** 打開對話視窗：先記下 Chrome 目前的畫面，讓 AI 能回答「要按哪裡」。 */
    private fun openChat() {
        if (!GuideSession.isRunning || chatOpen) return
        GuideSession.lastScreen = readChromeScreen()?.toJson()
        chatOpen = true
        handler.removeCallbacks(refreshRunnable)
        handler.removeCallbacks(relocateRunnable)
        handler.removeCallbacks(forceRefreshRunnable)
        overlay?.removeAll()

        val intent = Intent(this, GuideChatActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
        } catch (e: Exception) {
            Log.w(TAG, "無法打開對話視窗", e)
            chatOpen = false
            overlay?.showControls()
            overlay?.showMessage("對話視窗打不開，請再試一次")
        }
    }

    /** 對話視窗關閉：用（可能更新過的）目標和對話內容重新判斷下一步。 */
    fun onChatClosed() {
        chatOpen = false
        if (!GuideSession.isRunning) return
        currentTarget = null
        lastFailed = false
        overlay?.showControls()
        overlay?.setPageSummary("")
        overlay?.showMessage("好的，我重新看一下畫面…")
        handler.removeCallbacks(forceRefreshRunnable)
        handler.postDelayed(forceRefreshRunnable, 700L)
    }

    private fun stopFromOverlay() {
        GuideSession.stop()
        onSessionStopped()
    }

    private fun resetState() {
        handler.removeCallbacksAndMessages(null)
        overlay?.setPageSummary("")
        currentTarget = null
        lastUrl = ""
        knownPageKeys = emptySet()
        scanning = false
        forceNextAi = false
        pageCache = null
        lastAiAt = 0L
        requestInFlight = false
        pendingRefresh = false
        userActed = false
        lastFailed = false
        chatOpen = false
    }

    // ───────────────────────── 事件處理 ─────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !GuideSession.isRunning || scanning) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg == packageName) return // 自己的懸浮層

        if (pkg != CHROME_PACKAGE) {
            // 離開 Chrome：只把框藏起來，不讀取其他 App 的內容
            if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED &&
                pkg != SYSTEM_UI_PACKAGE
            ) {
                handler.removeCallbacks(refreshRunnable)
                handler.removeCallbacks(relocateRunnable)
                overlay?.hideHighlight()
            }
            return
        }

        when (event.eventType) {
            AccessibilityEvent.TYPE_VIEW_SCROLLED -> schedule(relocateRunnable, SCROLL_DELAY_MS)

            AccessibilityEvent.TYPE_VIEW_TEXT_CHANGED -> {
                userActed = true
                schedule(refreshRunnable, TYPING_DELAY_MS)
            }

            AccessibilityEvent.TYPE_VIEW_CLICKED,
            AccessibilityEvent.TYPE_VIEW_SELECTED -> {
                userActed = true
                schedule(refreshRunnable, SETTLE_DELAY_MS)
            }

            else -> schedule(refreshRunnable, SETTLE_DELAY_MS)
        }
    }

    private fun schedule(runnable: Runnable, delayMs: Long) {
        handler.removeCallbacks(runnable)
        handler.postDelayed(runnable, delayMs)
    }

    // ───────────────────────── 讀畫面 ─────────────────────────

    private fun readChromeScreen(): ScreenSnapshot? {
        val root = rootInActiveWindow ?: return null
        try {
            if (root.packageName?.toString() != CHROME_PACKAGE) return null
            val metrics = resources.displayMetrics
            return ScreenReader.read(root, metrics.widthPixels, metrics.heightPixels)
        } finally {
            ScreenReader.recycleCompat(root)
        }
    }

    /** 捲動時只重新找目標的位置，不問 AI。 */
    private fun relocateOnly() {
        if (!GuideSession.isRunning || requestInFlight || chatOpen || scanning) return
        val target = currentTarget ?: return
        val snapshot = readChromeScreen() ?: return
        showTargetOrScrollHint(target, findTarget(snapshot, target), snapshot)
    }

    /** 目標看得到就畫框；看不到就依 AI 當時給的位置提示往哪邊滑。 */
    private fun showTargetOrScrollHint(target: TargetRef, node: ScreenNode?, current: ScreenSnapshot? = null) {
        if (node != null && node.offscreen == null) {
            // 看得到了：一般目標畫框；只是標示選項位置的就只顯示文字，讓使用者自己選
            if (target.focusOnly) overlay?.showMessage(target.message) else overlay?.showTarget(node.bounds, target.message)
            return
        }
        // 只是標示選項位置（讓使用者自己選）時，不寫出某一個選項的名稱，免得看起來像替他選了
        val name = if (target.focusOnly) "可以選的項目" else "「${target.label.ifEmpty { "要按的地方" }}」"
        // 方向：目前畫面上找得到就用它的位置；找不到就用整頁的順序重新判斷（捲動過也正確）
        val direction = node?.offscreen ?: current?.let { directionToTarget(it, target) } ?: target.offscreen
        val hint = when (direction) {
            "above" -> "⬆ 請往上滑，找到$name"
            "below" -> "⬇ 請往下滑，找到$name"
            else -> "請上下滑動，找到$name"
        }
        overlay?.showMessage("${target.message}\n$hint")
    }

    /** 送出、確認、下一步這類會把表單送出去的按鈕。 */
    private fun isSubmitLike(node: ScreenNode): Boolean =
        !node.editable && SUBMIT_WORDS.containsMatchIn(node.label)

    /** 表單上第一個還沒填的個人資料欄位（身分證、病歷號、生日、電話、驗證碼…），搜尋框不算。 */
    private fun firstEmptyFormField(snapshot: ScreenSnapshot): ScreenNode? =
        snapshot.nodes.firstOrNull {
            it.editable && !it.filled && FORM_FIELD_WORDS.containsMatchIn(it.hint) &&
                !SEARCH_WORDS.containsMatchIn(it.hint)
        }

    /** AI 沒給位置時，從訊息裡提到的選項名稱找出它在網頁上的位置。 */
    private fun guessFocus(message: String, snapshot: ScreenSnapshot): ScreenNode? =
        snapshot.nodes.firstOrNull { it.clickable && it.label.length >= 2 && message.contains(it.label) }
            ?: snapshot.nodes.firstOrNull { it.label.length >= 2 && message.contains(it.label) }


    private fun refresh(force: Boolean) {
        if (!GuideSession.isRunning || chatOpen || scanning) return
        if (GuideSession.isCompleted && !force) return

        val snapshot = readChromeScreen()
        if (snapshot == null) {
            if (force) overlay?.showMessage("請先回到 Chrome 的掛號網頁")
            return
        }
        overlay?.showControls()

        if (snapshot.visibleCount == 0) {
            // 網頁還在載入
            schedule(refreshRunnable, SETTLE_DELAY_MS)
            return
        }

        val target = currentTarget
        // 捲動時 Chrome 會把網址列藏起來（讀到空字串），所以兩邊都有網址才比較
        val urlChanged = snapshot.url.isNotEmpty() && lastUrl.isNotEmpty() && snapshot.url != lastUrl
        val samePage = isSamePage(snapshot)

        val needAi = if (lastFailed) {
            force || userActed || urlChanged
        } else {
            force || forceNextAi || userActed || urlChanged || !samePage
        }
        if (!needAi) {
            // 還在同一頁（只是捲動）：不重問 AI，只把框對到目標上
            if (target != null) showTargetOrScrollHint(target, findTarget(snapshot, target), snapshot)
            return
        }

        if (requestInFlight) {
            pendingRefresh = true
            return
        }

        val wait = MIN_AI_INTERVAL_MS - (SystemClock.uptimeMillis() - lastAiAt)
        if (wait > 0 && !force) {
            schedule(refreshRunnable, wait)
            return
        }

        if (snapshot.nodes.size == snapshot.visibleCount) {
            // Chrome 沒提供畫面外的元素：同一頁沿用先前讀到的整頁內容；新頁面（或按了重看）才從頭捲到尾讀一次
            val cache = pageCache
            if (!force && cache != null && canReuseCache(snapshot, cache)) {
                Log.d(TAG, "同一頁，沿用先前讀到的整頁內容，不重新捲動")
                askAi(mergeWithCache(snapshot, cache))
            } else {
                scanPageThenAsk(snapshot)
            }
        } else {
            askAi(snapshot)
        }
    }

    /**
     * 整頁快取是照網頁由上到下的順序排的。找出「目前畫面上看得到的元素」在快取裡的位置範圍，
     * 排在範圍之前的就在畫面上方、之後的就在下方。找不到參考點時回傳 null。
     */
    private fun visibleRangeInCache(current: ScreenSnapshot, cache: ScreenSnapshot): IntRange? {
        val visibleKeys = current.nodes.filter { it.offscreen == null && it.label.isNotEmpty() }.map { pageKey(it) }.toSet()
        val indices = cache.nodes.indices.filter { pageKey(cache.nodes[it]) in visibleKeys }
        return if (indices.isEmpty()) null else indices.first()..indices.last()
    }

    private fun positionByOrder(index: Int, range: IntRange?): String = when {
        range == null -> "unknown"
        index < range.first -> "above"
        index > range.last -> "below"
        else -> "unknown" // 夾在畫面範圍中間卻看不到（例如被收合），不確定方向
    }

    /** 目標不在畫面上時，用整頁快取的順序判斷現在該往上還是往下滑。 */
    private fun directionToTarget(current: ScreenSnapshot, target: TargetRef): String? {
        val cache = pageCache ?: return null
        val index = cache.nodes.indexOfFirst { sameKind(it, target.role, target.label) }
        if (index < 0) return null
        return positionByOrder(index, visibleRangeInCache(current, cache)).takeIf { it != "unknown" }
    }

    /** 網址沒變，而且目前畫面上的元素幾乎都在快取裡（只是填了資料、捲動），就算同一頁。 */
    private fun canReuseCache(current: ScreenSnapshot, cache: ScreenSnapshot): Boolean {
        if (current.url.isNotEmpty() && cache.url.isNotEmpty() && current.url != cache.url) return false
        val cachedKeys = cache.nodes.filter { it.label.isNotEmpty() }.map { pageKey(it) }.toSet()
        val keys = current.nodes.filter { it.offscreen == null && it.label.isNotEmpty() }.map { pageKey(it) }
        if (keys.isEmpty()) return true
        return keys.count { it in cachedKeys }.toDouble() / keys.size >= CACHE_REUSE_RATIO
    }

    /** 目前畫面（最新的填寫狀態和位置）＋ 快取裡現在看不到的部分（用網頁順序判斷在上方或下方）。 */
    private fun mergeWithCache(current: ScreenSnapshot, cache: ScreenSnapshot): ScreenSnapshot {
        val visibleKeys = current.nodes.filter { it.offscreen == null }.map { pageKey(it) }.toSet()
        val range = visibleRangeInCache(current, cache)
        val merged = ArrayList<ScreenNode>(current.nodes)
        cache.nodes.forEachIndexed { index, node ->
            if (merged.size >= MAX_PAGE_NODES) return@forEachIndexed
            if (pageKey(node) in visibleKeys) return@forEachIndexed
            merged.add(node.copy(id = merged.size, offscreen = positionByOrder(index, range), bounds = Rect()))
        }
        val url = current.url.ifEmpty { cache.url }
        val title = current.title.ifEmpty { cache.title }
        return ScreenSnapshot(current.packageName, url, title, merged)
    }

    /** 畫面上的元素有足夠比例出現在上次交給 AI 的整頁內容裡，就當作同一頁（只是捲動）。 */
    private fun isSamePage(snapshot: ScreenSnapshot): Boolean {
        if (knownPageKeys.isEmpty()) return false
        val keys = snapshot.nodes.filter { it.offscreen == null && it.label.isNotEmpty() }.map { pageKey(it) }
        if (keys.isEmpty()) return true
        return keys.count { it in knownPageKeys }.toDouble() / keys.size >= SAME_PAGE_RATIO
    }

    private fun pageKey(node: ScreenNode) = "${node.role}|${node.label}"

    // ───────────────────────── 自動捲動讀整頁 ─────────────────────────

    /**
     * 一直往下捲到網頁最底（最多 MAX_SCAN_SCREENS 個畫面），把每個畫面的元素收集起來（標記在下方），
     * 再捲回原本的位置，最後把整頁內容交給 AI。
     */
    private fun scanPageThenAsk(first: ScreenSnapshot) {
        val generation = GuideSession.generation
        scanning = true
        requestInFlight = true
        currentTarget = null
        overlay?.setPageSummary("")
        overlay?.showMessage("正在讀整個網頁，請稍等…")

        val screens = mutableListOf(first)
        var forwardCount = 0

        fun aborted() = generation != GuideSession.generation || !GuideSession.isRunning || chatOpen

        fun finish() {
            var remaining = forwardCount
            fun scrollBack() {
                if (aborted()) {
                    scanning = false
                    requestInFlight = false
                    return
                }
                if (remaining > 0 && scrollWeb(forward = false)) {
                    remaining--
                    handler.postDelayed({ scrollBack() }, SCAN_BACK_STEP_MS)
                    return
                }
                handler.postDelayed({
                    scanning = false
                    requestInFlight = false
                    if (aborted()) return@postDelayed
                    val merged = mergeScreens(screens)
                    pageCache = merged
                                askAi(merged)
                }, SCAN_SETTLE_MS)
            }
            scrollBack()
        }

        fun scanNext() {
            if (aborted()) {
                scanning = false
                requestInFlight = false
                return
            }
            if (forwardCount >= MAX_SCAN_SCREENS || !scrollWeb(forward = true)) {
                finish()
                return
            }
            forwardCount++
            handler.postDelayed({
                val screen = readChromeScreen()
                when {
                    screen == null -> finish()
                    isSameScreen(screens.last(), screen) -> {
                        // 捲了但畫面沒變：已經到底。這一次沒有真的移動，捲回時不用算
                        forwardCount--
                        finish()
                    }
                    else -> {
                        screens.add(screen)
                        if (screens.sumOf { it.visibleCount } >= MAX_PAGE_NODES) finish() else scanNext()
                    }
                }
            }, SCAN_SETTLE_MS)
        }

        scanNext()
    }

    /** 兩個畫面上看得到的元素幾乎一樣（位置也沒變），代表捲動沒有移動，也就是到底了。 */
    private fun isSameScreen(a: ScreenSnapshot, b: ScreenSnapshot): Boolean {
        val keysA = a.nodes.filter { it.offscreen == null }.map { "${pageKey(it)}@${it.bounds.top}" }
        val keysB = b.nodes.filter { it.offscreen == null }.map { "${pageKey(it)}@${it.bounds.top}" }
        if (keysB.isEmpty()) return true
        val setA = keysA.toSet()
        return keysB.count { it in setA }.toDouble() / keysB.size >= BOTTOM_SAME_RATIO
    }

    /** 第一個畫面保留原本座標；後面捲到的畫面標記為「在下方」，並去掉和上一個畫面重疊的部分。 */
    private fun mergeScreens(screens: List<ScreenSnapshot>): ScreenSnapshot {
        val first = screens.first()
        if (screens.size == 1) return first

        val overlapTop = (resources.displayMetrics.heightPixels * 0.35f).toInt()
        val merged = ArrayList<ScreenNode>(first.nodes)
        for (i in 1 until screens.size) {
            val previousKeys = screens[i - 1].nodes.map { pageKey(it) }.toSet()
            for (node in screens[i].nodes) {
                if (merged.size >= MAX_PAGE_NODES) break
                if (node.offscreen != null) continue
                // 畫面上方那一段通常和上一個畫面重疊
                if (node.bounds.top < overlapTop && pageKey(node) in previousKeys) continue
                merged.add(node.copy(id = merged.size, offscreen = "below", bounds = Rect()))
            }
        }
        val url = screens.map { it.url }.firstOrNull { it.isNotEmpty() }.orEmpty()
        val title = screens.map { it.title }.firstOrNull { it.isNotEmpty() }.orEmpty()
        return ScreenSnapshot(first.packageName, url, title, merged)
    }

    /** 對 Chrome 的網頁本體做一次「往下／往上捲一頁」。 */
    private fun scrollWeb(forward: Boolean): Boolean {
        val root = rootInActiveWindow ?: return false
        try {
            if (root.packageName?.toString() != CHROME_PACKAGE) return false
            val target = findScrollable(root) ?: return false
            val action = if (forward) {
                AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            } else {
                AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            }
            val ok = target.performAction(action)
            if (target !== root) ScreenReader.recycleCompat(target)
            return ok
        } finally {
            ScreenReader.recycleCompat(root)
        }
    }

    /** 找面積最大、可以捲動的網頁元素（略過 Chrome 自己的介面）。 */
    private fun findScrollable(root: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        var best: AccessibilityNodeInfo? = null
        var bestArea = 0L
        val queue = ArrayDeque<AccessibilityNodeInfo>()
        queue.addLast(root)
        var visited = 0
        while (queue.isNotEmpty() && visited < 3_000) {
            val node = queue.removeFirst()
            visited++
            var keep = false
            val viewId = node.viewIdResourceName.orEmpty()
            if (node.isScrollable && node.isVisibleToUser && !viewId.startsWith("com.android.chrome:id/")) {
                val r = Rect()
                node.getBoundsInScreen(r)
                val area = r.width().toLong() * r.height()
                if (area > bestArea) {
                    best?.let { if (it !== root) ScreenReader.recycleCompat(it) }
                    best = node
                    bestArea = area
                    keep = true
                }
            }
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.addLast(it) }
            if (!keep && node !== root) ScreenReader.recycleCompat(node)
        }
        queue.forEach { if (it !== root) ScreenReader.recycleCompat(it) }
        return best
    }

    // ───────────────────────── 問 AI ─────────────────────────

    private fun askAi(snapshot: ScreenSnapshot) {
        requestInFlight = true
        userActed = false
        forceNextAi = false
        lastAiAt = SystemClock.uptimeMillis()
        if (snapshot.url.isNotEmpty()) lastUrl = snapshot.url
        knownPageKeys = snapshot.nodes.filter { it.label.isNotEmpty() }.map { pageKey(it) }.toSet()
        currentTarget = null
        overlay?.setPageSummary("")
        overlay?.showMessage("正在讀這一頁的內容…")

        val generation = GuideSession.generation
        val body = JSONObject()
            .put("goal", GuideSession.goal)
            .put("history", GuideSession.historyJson())
            .put("chat", GuideSession.chatJson())
            .put("screen", snapshot.toJson())

        Log.d(
            TAG,
            "送出畫面：${snapshot.visibleCount} 個在畫面上、${snapshot.nodes.size - snapshot.visibleCount} 個在畫面外，" +
                "title=${snapshot.title}，url=${snapshot.url}",
        )

        api.requestNext(GuideSession.backendUrl, body) { result ->
            if (generation != GuideSession.generation || !GuideSession.isRunning) return@requestNext
            requestInFlight = false
            if (chatOpen) return@requestNext // 對話中不畫框；關閉對話後會重新判斷

            result
                .onSuccess {
                    lastFailed = false
                    handleAction(it, snapshot)
                }
                .onFailure {
                    Log.w(TAG, "AI 請求失敗", it)
                    lastFailed = true
                    knownPageKeys = emptySet()
                    // 不自動重試，避免網路有問題時一直送；使用者按「重看」、換頁或有操作時再試
                    val detail = it.message.orEmpty()
                    overlay?.showMessage(
                        when {
                            detail.startsWith("HTTP 401") -> "引導伺服器的通行碼不對，請回 App 的進階設定檢查"
                            detail.startsWith("HTTP 429") -> "AI 助手現在太忙了，請等幾秒再按「重看」"
                            detail.startsWith("HTTP 5") -> "AI 助手暫時出了點問題，請稍後按「重看」"
                            else -> "暫時連不上 AI 助手，請檢查網路後按「重看」"
                        },
                    )
                }

            if (pendingRefresh) {
                pendingRefresh = false
                schedule(refreshRunnable, 300L)
            }
        }
    }

    private fun handleAction(action: GuideAction, snapshot: ScreenSnapshot) {
        Log.d(TAG, "AI 回應：${action.action} #${action.targetId} ${action.message}")

        val prefix = if (action.confidence < LOW_CONFIDENCE) "我不太確定，" else ""
        val aiNode = action.targetId?.let { id -> snapshot.nodes.firstOrNull { it.id == id } }

        // 表單還沒填完，AI 卻想框送出按鈕：改框第一個還沒填的欄位，全部填完才框送出
        val emptyField = if (aiNode != null && action.action in setOf("tap", "need_user") && isSubmitLike(aiNode)) {
            firstEmptyFormField(snapshot)
        } else {
            null
        }
        val node = emptyField ?: aiNode
        val message = if (emptyField != null) {
            "請先在這裡填寫「${emptyField.hint.ifEmpty { "資料" }}」，全部填完我再告訴您按哪裡送出"
        } else {
            prefix + action.message.ifBlank { "請稍等一下" }
        }
        if (emptyField != null) Log.d(TAG, "表單還有空欄位，先框「${emptyField.hint}」而不是送出按鈕")

        GuideSession.addStep(
            GuideSession.Step(
                message = action.message,
                targetLabel = node?.let { it.label.ifEmpty { it.hint } }.orEmpty(),
                page = action.pageSummary,
            ),
        )
        // 先讓使用者看到「這一頁」的確認資訊，再看下一步要做什麼
        overlay?.setPageSummary(action.pageSummary)

        when (action.action) {
            "done" -> {
                GuideSession.isCompleted = true
                overlay?.showMessage(message.ifBlank { "掛號完成了！" })
            }

            "scroll" -> {
                val focus = focusNodeFor(action, snapshot)
                if (focus != null) showFocus(focus, "⬇ $message", snapshot) else overlay?.showMessage("⬇ $message")
            }

            "wait" -> {
                overlay?.showMessage(message)
                forceNextAi = true // 讓 2 秒後的重讀一定會再問一次 AI
                schedule(refreshRunnable, 2_000L)
            }

            else -> { // tap、input、need_user
                if (node != null) {
                    val ref = TargetRef(
                        role = node.role,
                        label = node.label.ifEmpty { node.hint },
                        ordinal = ordinalOf(snapshot, node),
                        message = message,
                        offscreen = node.offscreen,
                    )
                    currentTarget = ref
                    showTargetOrScrollHint(ref, node)
                } else {
                    // 讓使用者自己選（沒有指定目標）：提示選項在哪裡，但不框住任何一個
                    // 有好幾個選項時，提醒可以打開對話問 AI
                    val choiceMessage = if (action.action == "need_user") "$message\n$CHAT_TIP" else message
                    val focus = focusNodeFor(action, snapshot)
                    when {
                        focus != null -> showFocus(focus, choiceMessage, snapshot)
                        // AI 沒指出位置，但下面還有內容：至少提示往下滑看更多選項
                        snapshot.nodes.any { it.offscreen == "below" && it.clickable } ->
                            overlay?.showMessage("$choiceMessage\n⬇ 往下滑可以看到更多選項")
                        else -> overlay?.showMessage(choiceMessage)
                    }
                }
            }
        }
    }

    private fun focusNodeFor(action: GuideAction, snapshot: ScreenSnapshot): ScreenNode? =
        action.focusId?.let { id -> snapshot.nodes.firstOrNull { it.id == id } }
            ?: guessFocus(action.message, snapshot)

    private fun showFocus(focus: ScreenNode, message: String, snapshot: ScreenSnapshot) {
        val ref = TargetRef(
            role = focus.role,
            label = focus.label.ifEmpty { focus.hint },
            ordinal = ordinalOf(snapshot, focus),
            message = message,
            offscreen = focus.offscreen,
            focusOnly = true,
        )
        currentTarget = ref
        showTargetOrScrollHint(ref, focus)
    }

    // ───────────────────────── 找目標 ─────────────────────────

    private fun sameKind(node: ScreenNode, role: String, label: String) =
        node.role == role && node.label.ifEmpty { node.hint } == label

    private fun ordinalOf(snapshot: ScreenSnapshot, node: ScreenNode): Int {
        val label = node.label.ifEmpty { node.hint }
        return snapshot.nodes.filter { sameKind(it, node.role, label) }.indexOf(node).coerceAtLeast(0)
    }

    private fun findTarget(snapshot: ScreenSnapshot, target: TargetRef): ScreenNode? {
        val matches = snapshot.nodes.filter { sameKind(it, target.role, target.label) }
        // 目標原本在畫面外時，整頁和目前畫面的順序對不上，直接找看得到的那一個
        if (target.offscreen != null) return matches.firstOrNull { it.offscreen == null } ?: matches.firstOrNull()
        return matches.getOrNull(target.ordinal) ?: matches.firstOrNull()
    }
}
