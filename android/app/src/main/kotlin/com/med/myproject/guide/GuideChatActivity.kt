package com.med.myproject.guide

import android.annotation.SuppressLint
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.speech.RecognizerIntent
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import org.json.JSONObject

/**
 * 引導途中的對話視窗：從下方滑出的半透明畫面，Chrome 留在後面。
 *
 * 長輩可以打字或用語音：問問題、說遇到的困難，或修改需求（換科別、換時間…）。
 * 關閉後，無障礙服務會用新的目標和對話內容重新判斷下一步。
 */
class GuideChatActivity : Activity() {

    companion object {
        private const val REQUEST_SPEECH = 41
        private const val GREETING =
            "有什麼想問的，或想改掛別的科、別的時間，都可以跟我說。\n可以打字，也可以按麥克風用說的。"

        // 與醫療早報一致的配色（Flutter Colors.blue / blue[50] / blue[100] / grey[100] / blueGrey）
        private const val BLUE = "#FF2196F3"
        private const val BLUE_50 = "#FFE3F2FD"
        private const val BLUE_100 = "#FFBBDEFB"
        private const val GREY_100 = "#FFF5F5F5"
        private const val BLUE_GREY = "#FF607D8B"
        private val QUICK_REPLIES = listOf("我找不到要按的地方", "我想改掛別的科", "這一頁在做什麼？")
    }

    private val api = GuideApiClient()
    private val density by lazy { resources.displayMetrics.density }

    private lateinit var messageList: LinearLayout
    private lateinit var scrollView: ScrollView
    private lateinit var input: EditText
    private lateinit var sendButton: TextView
    private lateinit var goalView: TextView
    private var typingBubble: View? = null
    private var sending = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (!GuideSession.isRunning) {
            finish()
            return
        }
        setContentView(buildLayout())

        addBubble(GuideSession.ChatMessage("assistant", GREETING), save = false)
        GuideSession.chat.forEach { addBubble(it, save = false) }
        updateGoalView()
    }

    /** 正在用語音輸入：這時候畫面被語音視窗蓋住，不要把自己關掉。 */
    private var awaitingSpeech = false

    override fun onStop() {
        super.onStop()
        // 長輩按主畫面鍵或切到別的 App：關掉對話，讓引導繼續（對話紀錄保留在 GuideSession）
        if (!awaitingSpeech && !isChangingConfigurations && !isFinishing) finish()
    }

    override fun onDestroy() {
        api.shutdown()
        if (isFinishing) GuideAccessibilityService.instance?.onChatClosed()
        super.onDestroy()
    }

    // ───────────────────────── 送出訊息 ─────────────────────────

    private fun send(rawText: String) {
        val text = rawText.trim()
        if (text.isEmpty() || sending) return

        // 先取對話紀錄（不含這一句），再把這一句加進去
        val body = JSONObject()
            .put("goal", GuideSession.goal)
            .put("chat", GuideSession.chatJson())
            .put("message", PrivacyMasker.mask(text))
        GuideSession.lastScreen?.let { body.put("screen", it) }

        addBubble(GuideSession.ChatMessage("user", text), save = true)
        input.setText("")
        setSending(true)

        api.requestChat(GuideSession.backendUrl, body) { result ->
            if (isFinishing || isDestroyed) return@requestChat
            setSending(false)
            result
                .onSuccess { reply ->
                    addBubble(GuideSession.ChatMessage("assistant", reply.reply), save = true)
                    reply.newGoal?.let { goal ->
                        GuideSession.updateGoal(goal)
                        updateGoalView()
                        addBubble(GuideSession.ChatMessage("system", "✔ 已更新目標：$goal"), save = true)
                    }
                }
                .onFailure {
                    val detail = it.message.orEmpty()
                    val message = when {
                        detail.startsWith("HTTP 429") -> "AI 助手現在太忙了，請等幾秒再送一次。"
                        detail.startsWith("HTTP 5") -> "AI 助手暫時出了點問題，請稍後再試。"
                        else -> "暫時連不上 AI 助手，請檢查網路後再試。"
                    }
                    addBubble(GuideSession.ChatMessage("system", message), save = false)
                }
        }
    }

    private fun setSending(value: Boolean) {
        sending = value
        sendButton.alpha = if (value) 0.5f else 1f
        if (value) {
            typingBubble = addBubble(GuideSession.ChatMessage("assistant", "正在想怎麼回答您…"), save = false)
        } else {
            typingBubble?.let { messageList.removeView(it) }
            typingBubble = null
        }
    }

    // ───────────────────────── 語音輸入 ─────────────────────────

    @Suppress("DEPRECATION")
    private fun startVoiceInput() {
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE, "zh-TW")
            .putExtra(RecognizerIntent.EXTRA_PROMPT, "請說出您的問題")
        try {
            awaitingSpeech = true
            startActivityForResult(intent, REQUEST_SPEECH)
        } catch (e: ActivityNotFoundException) {
            awaitingSpeech = false
            Toast.makeText(this, "這支手機沒有語音輸入功能，請用打字的", Toast.LENGTH_LONG).show()
        }
    }

    @Deprecated("Deprecated in Java")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SPEECH) return
        awaitingSpeech = false
        if (resultCode != RESULT_OK) return
        val spoken = data?.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)?.firstOrNull()
        if (!spoken.isNullOrBlank()) send(spoken)
    }

    // ───────────────────────── 畫面 ─────────────────────────

    private fun updateGoalView() {
        goalView.text = "目前目標：${GuideSession.goal}"
    }

    private fun addBubble(message: GuideSession.ChatMessage, save: Boolean): View {
        if (save) GuideSession.addChat(message)

        val isUser = message.role == "user"
        val isSystem = message.role == "system"
        val bubble = TextView(this).apply {
            text = message.text
            setTextSize(TypedValue.COMPLEX_UNIT_SP, if (isSystem) 14f else 17f)
            setTextColor(
                Color.parseColor(
                    when {
                        isUser -> "#FFFFFFFF"
                        isSystem -> BLUE_GREY
                        else -> "#DE000000"
                    },
                ),
            )
            setLineSpacing(0f, 1.3f)
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = rounded(
                when {
                    isUser -> BLUE
                    isSystem -> BLUE_50
                    else -> GREY_100
                },
                12,
            )
        }
        val params = LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply {
            topMargin = dp(8)
            gravity = when {
                isUser -> Gravity.END
                isSystem -> Gravity.CENTER_HORIZONTAL
                else -> Gravity.START
            }
            if (isUser) marginStart = dp(48) else marginEnd = dp(48)
        }
        messageList.addView(bubble, params)
        scrollView.post { scrollView.fullScroll(View.FOCUS_DOWN) }
        return bubble
    }

    @SuppressLint("SetTextI18n")
    private fun buildLayout(): View {
        // 外層：半透明遮罩，點空白處關閉
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.parseColor("#66000000"))
            setOnClickListener { finish() }
        }

        val panel = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(12), dp(16), dp(12))
            background = GradientDrawable().apply {
                setColor(Color.WHITE)
                cornerRadii = floatArrayOf(
                    dp(12).toFloat(), dp(12).toFloat(), dp(12).toFloat(), dp(12).toFloat(),
                    0f, 0f, 0f, 0f,
                )
            }
            isClickable = true // 避免點面板時觸發外層的關閉
        }
        root.addView(
            panel,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                (resources.displayMetrics.heightPixels * 0.72f).toInt(),
                Gravity.BOTTOM,
            ),
        )

        // 標題列
        val header = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        header.addView(
            TextView(this).apply {
                text = "問 AI 就醫夥伴"
                setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(Color.BLACK)
            },
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f),
        )
        header.addView(textButton("關閉", "#FFF44336") { finish() })
        panel.addView(header)

        goalView = TextView(this).apply {
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            setTextColor(Color.parseColor(BLUE_GREY))
            setPadding(dp(8), dp(4), dp(8), dp(4))
            background = rounded(BLUE_50, 4)
        }
        panel.addView(goalView)

        // 對話內容
        messageList = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, 0, 0, dp(8))
        }
        scrollView = ScrollView(this).apply {
            isFillViewport = true
            addView(messageList)
        }
        panel.addView(scrollView, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f))

        // 快速提問
        val quickRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        QUICK_REPLIES.forEach { text ->
            quickRow.addView(
                TextView(this).apply {
                    this.text = text
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
                    setTextColor(Color.parseColor(BLUE))
                    typeface = Typeface.DEFAULT_BOLD
                    setPadding(dp(10), dp(6), dp(10), dp(6))
                    background = rounded(BLUE_100, 4)
                    setOnClickListener { send(text) }
                },
                LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                ).apply { marginEnd = dp(8) },
            )
        }
        panel.addView(
            HorizontalScrollView(this).apply {
                isHorizontalScrollBarEnabled = false
                setPadding(0, dp(4), 0, dp(8))
                addView(quickRow)
            },
        )

        // 輸入列
        val inputRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        inputRow.addView(
            textButton("語音", BLUE) { startVoiceInput() }.apply { contentDescription = "用說的" },
        )
        input = EditText(this).apply {
            hint = "輸入問題或想改的地方…"
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(Color.WHITE)
                setStroke(dp(1), Color.parseColor("#FF9E9E9E"))
            }
            maxLines = 3
            imeOptions = EditorInfo.IME_ACTION_SEND
            setSingleLine(false)
            setOnEditorActionListener { _, actionId, _ ->
                if (actionId == EditorInfo.IME_ACTION_SEND) {
                    send(text.toString())
                    true
                } else {
                    false
                }
            }
        }
        inputRow.addView(
            input,
            LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                marginStart = dp(8)
                marginEnd = dp(8)
            },
        )
        sendButton = textButton("送出", BLUE) { send(input.text.toString()) }
        inputRow.addView(sendButton)
        panel.addView(inputRow)

        return root
    }

    /** 文字按鈕（同醫療早報的 IconButton：無底色，只有顏色文字）。 */
    private fun textButton(label: String, color: String, onClick: () -> Unit) = TextView(this).apply {
        text = label
        setTextColor(Color.parseColor(color))
        setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
        typeface = Typeface.DEFAULT_BOLD
        gravity = Gravity.CENTER
        setPadding(dp(10), dp(10), dp(10), dp(10))
        setOnClickListener { onClick() }
    }

    private fun rounded(color: String, radiusDp: Int) = GradientDrawable().apply {
        cornerRadius = dp(radiusDp).toFloat()
        setColor(Color.parseColor(color))
    }

    private fun dp(value: Int): Int = (value * density).toInt()
}
