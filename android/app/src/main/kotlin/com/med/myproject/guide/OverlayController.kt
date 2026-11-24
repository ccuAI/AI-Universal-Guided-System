package com.med.myproject.guide

import android.accessibilityservice.AccessibilityService
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.util.TypedValue
import android.view.GestureDetector
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * 在 Chrome 上方畫引導：
 * - 全螢幕、不攔截觸控的畫框層（HighlightView）：只畫橘色框
 * - 提示泡泡（獨立的小視窗）：可以拖曳移動、點兩下恢復自動擺放、可以暫時隱藏
 * - 可拖曳的小控制列：「對話」「重看」「隱藏提示」「停止」
 *
 * 使用 TYPE_ACCESSIBILITY_OVERLAY，不需要另外申請懸浮視窗權限。只能在主執行緒呼叫。
 */
class OverlayController(
    private val service: AccessibilityService,
    private val onStop: () -> Unit,
    private val onRetry: () -> Unit,
    private val onChat: () -> Unit,
) {
    private val windowManager = service.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val density = service.resources.displayMetrics.density

    private var highlightView: HighlightView? = null

    private var bubbleView: TextView? = null
    private var bubbleParams: WindowManager.LayoutParams? = null

    private var controlView: View? = null
    private var controlParams: WindowManager.LayoutParams? = null
    private var toggleButton: TextView? = null

    /** AI 對這一頁的摘要：目前不顯示在畫面上（只給 AI 參考）。 */
    private var pageSummary = ""

    /** 使用者按了「隱藏提示」。 */
    private var bubbleHidden = false

    /** 使用者拖曳過提示泡泡：之後的提示都留在他放的位置，點兩下才恢復自動擺放。 */
    private var bubbleMovedByUser = false

    private var lastAnchor: Rect? = null

    fun setPageSummary(summary: String) {
        pageSummary = summary.trim()
    }

    /** 框出目標並顯示提示。 */
    fun showTarget(bounds: Rect, message: String) {
        ensureHighlight().show(bounds)
        showBubble(compose(message), bounds)
    }

    /** 只顯示提示文字（沒有要框的目標）。 */
    fun showMessage(message: String) {
        highlightView?.clear()
        showBubble(compose(message), null)
    }

    /** 隱藏框和提示，但保留控制列（例如離開 Chrome 時）。 */
    fun hideHighlight() {
        highlightView?.clear()
        bubbleView?.visibility = View.GONE
    }

    fun showControls() {
        if (controlView != null) return
        val view = buildControlView()
        val params = baseParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dp(12)
            y = (service.resources.displayMetrics.heightPixels * 0.30f).toInt()
        }
        windowManager.addView(view, params)
        controlView = view
        controlParams = params
    }

    fun removeAll() {
        highlightView?.let {
            it.clear()
            runCatching { windowManager.removeView(it) }
        }
        bubbleView?.let { runCatching { windowManager.removeView(it) } }
        controlView?.let { runCatching { windowManager.removeView(it) } }
        highlightView = null
        bubbleView = null
        bubbleParams = null
        controlView = null
        controlParams = null
        toggleButton = null
        bubbleHidden = false
        bubbleMovedByUser = false
        lastAnchor = null
    }

    // ───────────────────────── 提示泡泡 ─────────────────────────

    /** 提示泡泡只顯示要做的操作（這一頁的摘要只給 AI 參考，不顯示）。 */
    private fun compose(text: String): CharSequence = text

    private fun showBubble(text: CharSequence, anchor: Rect?) {
        lastAnchor = anchor?.let { Rect(it) }
        val view = ensureBubble()
        view.text = text
        if (bubbleHidden || text.isEmpty()) {
            view.visibility = View.GONE
            return
        }
        view.visibility = View.VISIBLE
        if (!bubbleMovedByUser) placeBubble(view, anchor)
    }

    /** 自動擺放：有目標就放在框的下方（放不下就放上方），沒有目標就放在畫面下方。 */
    private fun placeBubble(view: TextView, anchor: Rect?) {
        val params = bubbleParams ?: return
        val metrics = service.resources.displayMetrics
        val screenW = metrics.widthPixels
        val screenH = metrics.heightPixels
        val margin = dp(16)
        val maxWidth = min(screenW - 2 * margin, dp(420))
        view.maxWidth = maxWidth
        view.measure(
            View.MeasureSpec.makeMeasureSpec(maxWidth, View.MeasureSpec.AT_MOST),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val w = view.measuredWidth
        val h = view.measuredHeight
        val gap = dp(20)

        val top = if (anchor != null) {
            val below = anchor.bottom + gap
            if (below + h < screenH - margin) below else anchor.top - gap - h
        } else {
            screenH - h - dp(150) // 避開 Chrome 底部工具列
        }
        val left = if (anchor != null) anchor.centerX() - w / 2 else (screenW - w) / 2

        params.x = left.coerceIn(margin, max(margin, screenW - w - margin))
        params.y = top.coerceIn(margin, max(margin, screenH - h - margin))
        runCatching { windowManager.updateViewLayout(view, params) }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun ensureBubble(): TextView {
        bubbleView?.let { return it }
        val view = TextView(service).apply {
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            typeface = Typeface.DEFAULT_BOLD
            setLineSpacing(0f, 1.15f)
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = GradientDrawable().apply {
                cornerRadius = dp(16).toFloat()
                setColor(Color.parseColor("#F2202A44"))
            }
            elevation = dp(6).toFloat()
            visibility = View.GONE
        }
        val params = baseParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        // 按住拖曳移動；點兩下恢復自動擺放
        val touchSlop = ViewConfiguration.get(service).scaledTouchSlop
        val doubleTap = GestureDetector(
            service,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onDoubleTap(e: MotionEvent): Boolean {
                    bubbleMovedByUser = false
                    placeBubble(view, lastAnchor)
                    return true
                }
            },
        )
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        var dragging = false
        view.setOnTouchListener { _, event ->
            doubleTap.onTouchEvent(event)
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    dragging = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - touchX
                    val dy = event.rawY - touchY
                    if (!dragging && (abs(dx) > touchSlop || abs(dy) > touchSlop)) dragging = true
                    if (dragging) {
                        params.x = startX + dx.toInt()
                        params.y = startY + dy.toInt()
                        runCatching { windowManager.updateViewLayout(view, params) }
                    }
                }
                MotionEvent.ACTION_UP -> if (dragging) bubbleMovedByUser = true
            }
            true
        }

        windowManager.addView(view, params)
        bubbleView = view
        bubbleParams = params
        bringControlsToFront()
        return view
    }

    private fun toggleBubble() {
        bubbleHidden = !bubbleHidden
        toggleButton?.text = if (bubbleHidden) "顯示提示" else "隱藏提示"
        bubbleView?.let { view ->
            if (bubbleHidden || view.text.isNullOrEmpty()) {
                view.visibility = View.GONE
            } else {
                view.visibility = View.VISIBLE
                if (!bubbleMovedByUser) placeBubble(view, lastAnchor)
            }
        }
    }

    // ───────────────────────── 畫框層 ─────────────────────────

    private fun ensureHighlight(): HighlightView {
        highlightView?.let { return it }
        val view = HighlightView(service)
        val params = baseParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
        ).apply { gravity = Gravity.TOP or Gravity.START }
        windowManager.addView(view, params)
        highlightView = view

        // 提示泡泡和控制列要蓋在畫框層上面：重新加入一次
        bubbleView?.let { bv ->
            runCatching { windowManager.removeView(bv) }
            windowManager.addView(bv, bubbleParams)
        }
        bringControlsToFront()
        return view
    }

    private fun bringControlsToFront() {
        controlView?.let { cv ->
            runCatching { windowManager.removeView(cv) }
            windowManager.addView(cv, controlParams)
        }
    }

    private fun baseParams(width: Int, height: Int, flags: Int) = WindowManager.LayoutParams(
        width,
        height,
        WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
        flags,
        PixelFormat.TRANSLUCENT,
    ).apply {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    // ───────────────────────── 控制列 ─────────────────────────

    @SuppressLint("ClickableViewAccessibility", "SetTextI18n")
    private fun buildControlView(): View {
        val bar = LinearLayout(service).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(6), dp(6), dp(6), dp(6))
            background = GradientDrawable().apply {
                cornerRadius = dp(8).toFloat()
                setColor(Color.WHITE)
                setStroke(dp(1), Color.parseColor("#1F000000"))
            }
            elevation = dp(4).toFloat()
        }

        val handle = TextView(service).apply {
            text = "⋮⋮"
            setTextColor(Color.parseColor("#FF9E9E9E"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 20f)
            setPadding(dp(10), dp(8), dp(8), dp(8))
            contentDescription = "拖曳移動控制列"
        }
        bar.addView(handle)
        bar.addView(controlButton("對話", "#FF2196F3") { onChat() })
        bar.addView(controlButton("重看", "#FF2196F3") { onRetry() })
        val toggle = controlButton(if (bubbleHidden) "顯示提示" else "隱藏提示", "#FF2196F3") { toggleBubble() }
        toggleButton = toggle
        bar.addView(toggle)
        bar.addView(controlButton("停止", "#FFF44336") { onStop() })

        // 拖曳把手移動整個控制列，避免擋到網頁按鈕
        var startX = 0
        var startY = 0
        var touchX = 0f
        var touchY = 0f
        handle.setOnTouchListener { _, event ->
            val params = controlParams ?: return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x
                    startY = params.y
                    touchX = event.rawX
                    touchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (event.rawX - touchX).toInt()
                    params.y = startY + (event.rawY - touchY).toInt()
                    controlView?.let { windowManager.updateViewLayout(it, params) }
                    true
                }
                else -> true
            }
        }
        return bar
    }

    private fun controlButton(label: String, color: String, onClick: () -> Unit) =
        TextView(service).apply {
            text = label
            setTextColor(Color.parseColor(color))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 17f)
            typeface = Typeface.DEFAULT_BOLD
            setPadding(dp(12), dp(10), dp(12), dp(10))
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.WRAP_CONTENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
            isClickable = true
            setOnClickListener { onClick() }
        }

    private fun dp(value: Int): Int = (value * density).toInt()
}

/** 只畫橘色框（會呼吸閃爍）的全螢幕透明 View，不攔截觸控。 */
@SuppressLint("ViewConstructor")
private class HighlightView(context: Context) : View(context) {

    private val density = resources.displayMetrics.density

    private var target: Rect? = null
    private var pulse = 0f

    private val boxPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 5 * density
        color = Color.parseColor("#FFFF6D00")
    }
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.parseColor("#FFFFAB40")
    }

    private val animator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 700
        repeatMode = ValueAnimator.REVERSE
        repeatCount = ValueAnimator.INFINITE
        addUpdateListener {
            pulse = it.animatedValue as Float
            invalidate()
        }
    }

    fun show(bounds: Rect?) {
        target = bounds?.let { Rect(it) }
        if (target != null) {
            if (!animator.isStarted) animator.start()
        } else {
            animator.cancel()
        }
        invalidate()
    }

    fun clear() {
        target = null
        animator.cancel()
        invalidate()
    }

    override fun onDetachedFromWindow() {
        animator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val t = target ?: return
        // 節點座標是「螢幕座標」，扣掉這個視窗在螢幕上的位置才能對齊
        val origin = IntArray(2)
        getLocationOnScreen(origin)
        val pad = 6 * density
        val box = RectF(t).apply {
            offset(-origin[0].toFloat(), -origin[1].toFloat())
            inset(-pad, -pad)
        }
        val radius = 12 * density
        glowPaint.strokeWidth = (8 + 10 * pulse) * density
        glowPaint.alpha = (160 * (1 - pulse)).toInt()
        canvas.drawRoundRect(box, radius, radius, glowPaint)
        canvas.drawRoundRect(box, radius, radius, boxPaint)
    }
}
