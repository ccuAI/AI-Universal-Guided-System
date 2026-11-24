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
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.min

/**
 * 在 Chrome 上方畫引導：
 * - 全螢幕、不攔截觸控的畫框層（HighlightView）
 * - 可拖曳的小控制列：「對話」「重看」「停止引導」
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
    private var controlView: View? = null
    private var controlParams: WindowManager.LayoutParams? = null

    /** 框出目標並顯示提示。 */
    fun showTarget(bounds: Rect, message: String) {
        ensureHighlight().show(bounds, message)
    }

    /** 只顯示提示文字（沒有要框的目標）。 */
    fun showMessage(message: String) {
        ensureHighlight().show(null, message)
    }

    /** 隱藏框和提示，但保留控制列（例如離開 Chrome 時）。 */
    fun hideHighlight() {
        highlightView?.clear()
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
        controlView?.let { runCatching { windowManager.removeView(it) } }
        highlightView = null
        controlView = null
        controlParams = null
    }

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

        // 控制列要蓋在畫框層上面：重新加入一次
        controlView?.let { cv ->
            runCatching { windowManager.removeView(cv) }
            windowManager.addView(cv, controlParams)
        }
        return view
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

/** 畫框 + 提示泡泡的全螢幕透明 View。 */
@SuppressLint("ViewConstructor")
private class HighlightView(context: Context) : View(context) {

    private val density = resources.displayMetrics.density

    private var target: Rect? = null
    private var message: String = ""
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
    private val bubblePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.parseColor("#F2202A44")
    }
    private val textPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, 22f, resources.displayMetrics)
        typeface = Typeface.DEFAULT_BOLD
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

    fun show(bounds: Rect?, text: String) {
        target = bounds?.let { Rect(it) }
        message = text
        if (target != null) {
            if (!animator.isStarted) animator.start()
        } else {
            animator.cancel()
        }
        invalidate()
    }

    fun clear() {
        target = null
        message = ""
        animator.cancel()
        invalidate()
    }

    override fun onDetachedFromWindow() {
        animator.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        // 節點座標是「螢幕座標」，扣掉這個視窗在螢幕上的位置才能對齊
        val origin = IntArray(2)
        getLocationOnScreen(origin)

        var box: RectF? = null
        target?.let { t ->
            val pad = 6 * density
            box = RectF(t).apply {
                offset(-origin[0].toFloat(), -origin[1].toFloat())
                inset(-pad, -pad)
            }
            val radius = 12 * density
            glowPaint.strokeWidth = (8 + 10 * pulse) * density
            glowPaint.alpha = (160 * (1 - pulse)).toInt()
            canvas.drawRoundRect(box!!, radius, radius, glowPaint)
            canvas.drawRoundRect(box!!, radius, radius, boxPaint)
        }

        if (message.isNotEmpty()) drawBubble(canvas, box)
    }

    private fun drawBubble(canvas: Canvas, box: RectF?) {
        val margin = 16 * density
        val padding = 16 * density
        val maxBubbleWidth = min(width - 2 * margin, 420 * density)
        val textWidth = (maxBubbleWidth - 2 * padding).toInt().coerceAtLeast(1)

        val layout = StaticLayout.Builder
            .obtain(message, 0, message.length, textPaint, textWidth)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(0f, 1.15f)
            .build()

        var contentWidth = 0f
        for (i in 0 until layout.lineCount) contentWidth = maxOf(contentWidth, layout.getLineWidth(i))
        val bubbleW = contentWidth + 2 * padding
        val bubbleH = layout.height + 2 * padding
        val gap = 14 * density

        val preferredTop = if (box != null) {
            val below = box.bottom + gap
            if (below + bubbleH < height - margin) below else (box.top - gap - bubbleH)
        } else {
            height - bubbleH - 150 * density // 沒有目標時放在下方，避開 Chrome 底部工具列
        }
        val top = preferredTop.coerceIn(margin, (height - bubbleH - margin).coerceAtLeast(margin))

        val left = if (box != null) {
            (box.centerX() - bubbleW / 2).coerceIn(margin, (width - bubbleW - margin).coerceAtLeast(margin))
        } else {
            (width - bubbleW) / 2
        }

        val rect = RectF(left, top, left + bubbleW, top + bubbleH)
        canvas.drawRoundRect(rect, 16 * density, 16 * density, bubblePaint)
        canvas.save()
        canvas.translate(left + padding, top + padding)
        layout.draw(canvas)
        canvas.restore()
    }
}
