package com.med.myproject.guide

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.accessibility.AccessibilityEvent
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
    )

    private val handler = Handler(Looper.getMainLooper())
    private val api = GuideApiClient()
    private var overlay: OverlayController? = null

    private var currentTarget: TargetRef? = null
    private var lastSignature: Int? = null
    private var lastUrl = ""
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
        currentTarget = null
        lastSignature = null
        lastUrl = ""
        lastAiAt = 0L
        requestInFlight = false
        pendingRefresh = false
        userActed = false
        lastFailed = false
        chatOpen = false
    }

    // ───────────────────────── 事件處理 ─────────────────────────

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event == null || !GuideSession.isRunning) return
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
        if (!GuideSession.isRunning || requestInFlight || chatOpen) return
        val target = currentTarget ?: return
        val snapshot = readChromeScreen() ?: return
        val node = findTarget(snapshot, target)
        if (node != null) {
            showTargetOrHint(node, target.message)
        } else {
            overlay?.showMessage(target.message)
        }
    }

    /** 目標在畫面上就畫框；在畫面外就提示往哪邊滑，滑到看得見時會自動畫框。 */
    private fun showTargetOrHint(node: ScreenNode, message: String) {
        val name = node.label.ifEmpty { node.hint }.ifEmpty { "要按的地方" }
        when (node.offscreen) {
            null -> overlay?.showTarget(node.bounds, message)
            "above" -> overlay?.showMessage("⬆ 請往上滑一點，找到「$name」")
            else -> overlay?.showMessage("⬇ 請往下滑一點，找到「$name」")
        }
    }

    private fun refresh(force: Boolean) {
        if (!GuideSession.isRunning || chatOpen) return
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
        val targetNode = target?.let { findTarget(snapshot, it) }
        val urlChanged = snapshot.url.isNotEmpty() && snapshot.url != lastUrl
        val targetGone = target != null && targetNode == null
        val noTargetAndChanged = target == null && snapshot.signature != lastSignature

        val needAi = if (lastFailed) {
            force || userActed || urlChanged
        } else {
            force || userActed || urlChanged || targetGone || noTargetAndChanged
        }
        if (!needAi) {
            if (target != null && targetNode != null) showTargetOrHint(targetNode, target.message)
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

        askAi(snapshot)
    }

    // ───────────────────────── 問 AI ─────────────────────────

    private fun askAi(snapshot: ScreenSnapshot) {
        requestInFlight = true
        userActed = false
        lastAiAt = SystemClock.uptimeMillis()
        lastSignature = snapshot.signature
        lastUrl = snapshot.url
        currentTarget = null
        overlay?.showMessage("正在幫你看畫面…")

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
                    // 不自動重試，避免網路有問題時一直送；使用者按「重看」、換頁或有操作時再試
                    val detail = it.message.orEmpty()
                    overlay?.showMessage(
                        when {
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
        val message = prefix + action.message.ifBlank { "請稍等一下" }
        val node = action.targetId?.let { id -> snapshot.nodes.firstOrNull { it.id == id } }

        GuideSession.addStep(
            GuideSession.Step(action.message, node?.let { it.label.ifEmpty { it.hint } }.orEmpty()),
        )

        when (action.action) {
            "done" -> {
                GuideSession.isCompleted = true
                overlay?.showMessage(message.ifBlank { "掛號完成了！" })
            }

            "scroll" -> overlay?.showMessage("⬇ $message")

            "wait" -> {
                overlay?.showMessage(message)
                lastSignature = null // 讓 2 秒後的重讀一定會再問一次 AI
                schedule(refreshRunnable, 2_000L)
            }

            else -> { // tap、input、need_user
                if (node != null) {
                    currentTarget = TargetRef(
                        role = node.role,
                        label = node.label.ifEmpty { node.hint },
                        ordinal = ordinalOf(snapshot, node),
                        message = message,
                    )
                    showTargetOrHint(node, message)
                } else {
                    overlay?.showMessage(message)
                }
            }
        }
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
        return matches.getOrNull(target.ordinal) ?: matches.firstOrNull()
    }
}
