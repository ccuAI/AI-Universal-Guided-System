package com.med.myproject.guide

import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** AI 回傳的下一步。 */
data class GuideAction(
    val action: String,
    val targetId: Int?,
    val message: String,
    val confidence: Double,
    /** AI 讀完整個網頁後，對這一頁的摘要（在做什麼、重要資訊）。 */
    val pageSummary: String = "",
    /** 讓使用者自己選時，選項在網頁上的位置（只用來提示往哪邊滑）。 */
    val focusId: Int? = null,
)

/** 對話視窗的 AI 回覆；newGoal 不為 null 代表長輩修改了需求；switchHospital 代表要換醫院（回 App 重新選）。 */
data class ChatReply(val reply: String, val newGoal: String?, val switchHospital: Boolean = false)

/**
 * 呼叫 AI 就醫夥伴專用的後端（backfront/guide-server）。
 * 網路在背景執行緒，callback 回到主執行緒。
 */
class GuideApiClient {

    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    fun requestNext(baseUrl: String, body: JSONObject, callback: (Result<GuideAction>) -> Unit) {
        executor.execute {
            val result = runCatching { parseAction(post("$baseUrl/guide/next", body)) }
            mainHandler.post { callback(result) }
        }
    }

    fun requestChat(baseUrl: String, body: JSONObject, callback: (Result<ChatReply>) -> Unit) {
        executor.execute {
            val result = runCatching {
                val json = post("$baseUrl/guide/chat", body)
                ChatReply(
                    reply = json.optString("reply", ""),
                    newGoal = if (json.isNull("new_goal")) null else json.optString("new_goal").ifBlank { null },
                    switchHospital = json.optBoolean("switch_hospital", false),
                )
            }
            mainHandler.post { callback(result) }
        }
    }

    fun shutdown() {
        executor.shutdownNow()
    }

    private fun parseAction(json: JSONObject): GuideAction {
        val targetId = if (!json.has("target_id") || json.isNull("target_id")) {
            null
        } else {
            json.optInt("target_id")
        }
        return GuideAction(
            action = json.optString("action", "wait"),
            targetId = targetId,
            message = json.optString("message", ""),
            confidence = json.optDouble("confidence", 1.0),
            pageSummary = json.optString("page_summary", ""),
            focusId = if (!json.has("focus_id") || json.isNull("focus_id")) null else json.optInt("focus_id"),
        )
    }

    private fun post(url: String, body: JSONObject): JSONObject {
        val conn = URL(url).openConnection() as HttpURLConnection
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 5_000
            conn.readTimeout = 30_000
            conn.doOutput = true
            conn.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            // 雲端伺服器的通行碼
            if (GuideSession.accessToken.isNotEmpty()) conn.setRequestProperty("X-Guide-Token", GuideSession.accessToken)
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }

            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() }.orEmpty()
            if (code !in 200..299) throw IOException("HTTP $code: ${text.take(200)}")

            return JSONObject(text)
        } finally {
            conn.disconnect()
        }
    }
}
