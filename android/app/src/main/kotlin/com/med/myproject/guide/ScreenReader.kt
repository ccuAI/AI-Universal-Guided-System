package com.med.myproject.guide

import android.graphics.Rect
import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONArray
import org.json.JSONObject

/** 畫面上的一個元素（送給 AI 的精簡版本，bounds 只留在手機端畫框用）。 */
data class ScreenNode(
    val id: Int,
    val role: String,
    val label: String,
    val hint: String,
    val clickable: Boolean,
    val editable: Boolean,
    val filled: Boolean,
    val checked: Boolean?,
    val bounds: Rect,
    /** null：在畫面上；"above" / "below"：在畫面上方／下方，要捲動才看得到。 */
    val offscreen: String? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("role", role)
        if (label.isNotEmpty()) put("text", label)
        if (hint.isNotEmpty()) put("hint", hint)
        if (clickable) put("clickable", true)
        if (editable) {
            put("editable", true)
            put("filled", filled)
        }
        checked?.let { put("checked", it) }
        offscreen?.let { put("offscreen", it) }
    }
}

class ScreenSnapshot(
    val packageName: String,
    val url: String,
    val title: String,
    val nodes: List<ScreenNode>,
) {
    /** 只看內容不看座標和是否在畫面上：單純捲動不算「畫面變了」。 */
    val signature: Int = nodes.map { "${it.role}|${it.label}|${it.hint}|${it.filled}|${it.checked}" }.hashCode()

    val visibleCount: Int get() = nodes.count { it.offscreen == null }

    fun toJson(): JSONObject = JSONObject().apply {
        put("package", packageName)
        put("url", url)
        if (title.isNotEmpty()) put("title", title)
        put("nodes", JSONArray().apply { nodes.forEach { put(it.toJson()) } })
    }
}

/**
 * 把 Chrome 目前網頁的無障礙節點樹整理成精簡清單。
 *
 * - 畫面上的元素，加上「捲動才看得到」的元素（標記 offscreen），讓 AI 知道整頁有什麼
 * - 跳過 Chrome 自己的介面（網址列只拿來讀網址）
 * - 輸入框只回報「提示文字」和「有沒有填」，絕不送出使用者輸入的內容
 * - 文字先經過 PrivacyMasker 遮蔽身分證字號、電話
 */
object ScreenReader {

    private const val MAX_VISIBLE = 150
    private const val MAX_OFFSCREEN = 250
    private const val MAX_TEXT = 120
    private const val CHROME_ID_PREFIX = "com.android.chrome:id/"
    private const val URL_BAR_ID = "com.android.chrome:id/url_bar"

    /** 呼叫端負責回收 root。 */
    fun read(root: AccessibilityNodeInfo, screenWidth: Int, screenHeight: Int): ScreenSnapshot {
        val screen = Rect(0, 0, screenWidth, screenHeight)
        val result = ArrayList<ScreenNode>()
        var visibleCount = 0
        var offscreenCount = 0
        var url = ""
        var title = ""

        // (節點, 上層可點擊元素的文字)：用來去掉「按鈕裡面重複的文字」
        val stack = ArrayDeque<Pair<AccessibilityNodeInfo, String>>()
        stack.addLast(root to "")

        while (stack.isNotEmpty()) {
            val (node, parentLabel) = stack.removeLast()
            try {
                if (visibleCount >= MAX_VISIBLE && offscreenCount >= MAX_OFFSCREEN) break

                val viewId = node.viewIdResourceName.orEmpty()
                if (viewId == URL_BAR_ID) {
                    url = node.text?.toString().orEmpty()
                    continue
                }
                val isChromeUi = viewId.startsWith(CHROME_ID_PREFIX)

                // 網頁本體（WebView）的文字通常就是網頁標題
                if (title.isEmpty() && !isChromeUi &&
                    node.className?.toString()?.contains("WebView") == true
                ) {
                    title = clean(node.text?.toString().orEmpty().ifEmpty { node.contentDescription?.toString().orEmpty() })
                }

                var labelForChildren = parentLabel
                val bounds = Rect()
                node.getBoundsInScreen(bounds)
                val visible = node.isVisibleToUser

                // 判斷在畫面上、上方還是下方；看不見但位置在畫面內的（被收合、被蓋住）不收
                val position: String? = when {
                    bounds.isEmpty -> "skip"
                    visible && Rect.intersects(bounds, screen) -> null
                    bounds.bottom <= 0 -> "above"
                    bounds.top >= screenHeight -> "below"
                    else -> "skip"
                }

                val hasRoom = if (position == null) visibleCount < MAX_VISIBLE else offscreenCount < MAX_OFFSCREEN
                if (!isChromeUi && position != "skip" && hasRoom) {
                    val drawBounds = Rect(bounds).apply { if (position == null) intersect(screen) }
                    val item = toScreenNode(node, result.size, drawBounds, parentLabel, position)
                    if (item != null) {
                        result.add(item)
                        if (position == null) visibleCount++ else offscreenCount++
                        if (item.clickable && item.label.isNotEmpty()) labelForChildren = item.label
                    }
                }

                // 反向放入堆疊，取出時才會照網頁上的順序
                for (i in node.childCount - 1 downTo 0) {
                    node.getChild(i)?.let { stack.addLast(it to labelForChildren) }
                }
            } finally {
                if (node !== root) recycleCompat(node)
            }
        }
        stack.forEach { if (it.first !== root) recycleCompat(it.first) }
        stack.clear()

        val pkg = root.packageName?.toString().orEmpty()
        return ScreenSnapshot(pkg, PrivacyMasker.mask(url), title, result)
    }

    private fun toScreenNode(
        node: AccessibilityNodeInfo,
        id: Int,
        bounds: Rect,
        parentLabel: String,
        offscreen: String?,
    ): ScreenNode? {
        val editable = node.isEditable
        val checkable = node.isCheckable
        val clickable = node.isClickable ||
            node.actionList.any { it.id == AccessibilityNodeInfo.ACTION_CLICK }

        val rawText = node.text?.toString().orEmpty()
        val desc = node.contentDescription?.toString().orEmpty()
        val hintText = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            node.hintText?.toString().orEmpty()
        } else {
            ""
        }
        val className = node.className?.toString().orEmpty()

        val label: String
        val hint: String
        val filled: Boolean
        if (editable) {
            // 輸入框的 text 是使用者打的字：只判斷有沒有填，不送出內容
            label = ""
            hint = clean(hintText.ifEmpty { desc })
            filled = rawText.isNotEmpty() && rawText != hintText
        } else {
            label = clean(rawText.ifEmpty { desc })
            hint = ""
            filled = false
        }

        val interactive = editable || clickable || checkable
        if (!interactive && label.isEmpty()) return null
        if (!interactive && label == parentLabel) return null

        val role = when {
            editable -> "input"
            className.contains("Spinner") -> "select"
            className.contains("RadioButton") -> "radio"
            checkable -> "checkbox"
            className.contains("Button") -> "button"
            clickable -> "link"
            else -> "text"
        }

        return ScreenNode(
            id = id,
            role = role,
            label = label,
            hint = hint,
            clickable = clickable,
            editable = editable,
            filled = filled,
            checked = if (checkable) node.isChecked else null,
            bounds = Rect(bounds),
            offscreen = offscreen,
        )
    }

    private fun clean(text: String): String {
        val collapsed = PrivacyMasker.mask(text).replace(Regex("\\s+"), " ").trim()
        return if (collapsed.length > MAX_TEXT) collapsed.take(MAX_TEXT) + "…" else collapsed
    }

    @Suppress("DEPRECATION")
    fun recycleCompat(node: AccessibilityNodeInfo) {
        // Android 13 起 recycle() 不需要也不做事；舊版要手動回收避免記憶體洩漏
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) node.recycle()
    }
}

/** 送出畫面前遮蔽常見個資。 */
object PrivacyMasker {
    private val nationalId = Regex("[A-Za-z][1289]\\d{8}")
    private val mobile = Regex("09\\d{2}[- ]?\\d{3}[- ]?\\d{3}")

    fun mask(text: String): String =
        text.replace(nationalId, "[身分證]").replace(mobile, "[電話]")
}
