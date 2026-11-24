package com.med.myproject.guide

import org.json.JSONArray
import org.json.JSONObject

/**
 * AI 就醫夥伴：目前這一次掛號引導的狀態。
 *
 * 由 Flutter（透過 GuideChannel）開始／結束，由 GuideAccessibilityService 讀取。
 * 全部只在主執行緒存取。
 */
object GuideSession {

    data class Step(val message: String, val targetLabel: String, val page: String = "")

    /** 對話視窗裡的一則訊息。role："user"、"assistant"，或只在畫面上顯示的 "system"。 */
    data class ChatMessage(val role: String, val text: String)

    private const val MAX_HISTORY = 8
    private const val MAX_CHAT = 30
    private const val MAX_CHAT_SENT = 10

    var isRunning = false
        private set

    /** AI 回報 done 之後設為 true，之後不再呼叫 AI，直到使用者停止或重新開始。 */
    var isCompleted = false

    var goal = ""
        private set

    var backendUrl = ""
        private set

    /** 雲端伺服器的通行碼（沒有設定就是空字串）。 */
    var accessToken = ""
        private set

    /** 每次開始或停止都會加 1，用來丟棄過期的 AI 回應。 */
    var generation = 0
        private set

    private val history = ArrayList<Step>()

    private val chatMessages = ArrayList<ChatMessage>()
    val chat: List<ChatMessage> get() = chatMessages

    /** 打開對話視窗時，Chrome 當下的畫面（給 AI 回答「要按哪裡」用）。 */
    var lastScreen: JSONObject? = null

    /**
     * 引導結束、帶使用者回 App 的原因（例如 "switch_hospital"）。
     * Flutter 回到前景時讀取一次（GuideChannel.consumeReturnReason）就清掉；stop() 不會清掉它。
     */
    var returnReason: String? = null

    fun start(goal: String, backendUrl: String, accessToken: String = "") {
        this.goal = goal
        this.backendUrl = backendUrl.trimEnd('/')
        this.accessToken = accessToken.trim()
        history.clear()
        chatMessages.clear()
        lastScreen = null
        isCompleted = false
        isRunning = true
        generation++
    }

    fun stop() {
        isRunning = false
        isCompleted = false
        history.clear()
        chatMessages.clear()
        lastScreen = null
        generation++
    }

    /** 長輩在對話中修改了需求。 */
    fun updateGoal(newGoal: String) {
        goal = newGoal
        isCompleted = false
        history.clear() // 舊的步驟紀錄可能誤導 AI
    }

    fun addChat(message: ChatMessage) {
        chatMessages.add(message)
        while (chatMessages.size > MAX_CHAT) chatMessages.removeAt(0)
    }

    /** 送給 AI 的對話紀錄：不含 system 提示，使用者的話先遮蔽個資。 */
    fun chatJson(): JSONArray = JSONArray().apply {
        chatMessages
            .filter { it.role == "user" || it.role == "assistant" }
            .takeLast(MAX_CHAT_SENT)
            .forEach {
                val text = if (it.role == "user") PrivacyMasker.mask(it.text) else it.text
                put(JSONObject().put("role", it.role).put("text", text))
            }
    }

    fun addStep(step: Step) {
        history.add(step)
        while (history.size > MAX_HISTORY) history.removeAt(0)
    }

    fun historyJson(): JSONArray = JSONArray().apply {
        history.forEach {
            val step = JSONObject().put("message", it.message).put("target_text", it.targetLabel)
            if (it.page.isNotEmpty()) step.put("page", it.page)
            put(step)
        }
    }
}
