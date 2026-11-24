package com.med.myproject.guide

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter（lib/guide_channel.dart）與 AI 就醫夥伴原生端的溝通介面。
 * 在 MainActivity.configureFlutterEngine 裡呼叫 register()。
 */
object GuideChannel {

    private const val CHANNEL = "com.med.myproject/guide"

    fun register(activity: Activity, engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkInt" -> result.success(Build.VERSION.SDK_INT)

                "isServiceEnabled" -> result.success(isServiceEnabled(activity))

                "isGuideRunning" -> result.success(GuideSession.isRunning)

                "consumeReturnReason" -> {
                    result.success(GuideSession.returnReason)
                    GuideSession.returnReason = null
                }

                "openAccessibilitySettings" -> {
                    result.success(open(activity, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)))
                }

                "openAppDetails" -> {
                    val intent = Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", activity.packageName, null),
                    )
                    result.success(open(activity, intent))
                }

                "startGuide" -> {
                    val goal = call.argument<String>("goal").orEmpty().trim()
                    val url = call.argument<String>("url").orEmpty().trim()
                    val backendUrl = call.argument<String>("backendUrl").orEmpty().trim()
                    val accessToken = call.argument<String>("accessToken").orEmpty().trim()

                    when {
                        !isServiceEnabled(activity) ->
                            result.error("SERVICE_DISABLED", "尚未開啟 AI 就醫夥伴的無障礙服務", null)
                        goal.isEmpty() || url.isEmpty() || backendUrl.isEmpty() ->
                            result.error("BAD_ARGS", "goal、url、backendUrl 都必須提供", null)
                        else -> {
                            GuideSession.start(goal, backendUrl, accessToken)
                            GuideAccessibilityService.instance?.onSessionStarted()
                            val inChrome = openInBrowser(activity, url)
                            result.success(mapOf("openedInChrome" to inChrome))
                        }
                    }
                }

                "stopGuide" -> {
                    GuideSession.stop()
                    GuideAccessibilityService.instance?.onSessionStopped()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun isServiceEnabled(context: Context): Boolean {
        val expected = ComponentName(context, GuideAccessibilityService::class.java)
        val enabled = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == expected }
    }

    private fun open(activity: Activity, intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (e: ActivityNotFoundException) {
        false
    }

    /** 優先用 Chrome 開；沒有 Chrome 就用預設瀏覽器（此時引導不會啟動）。回傳是否用 Chrome 開。 */
    private fun openInBrowser(activity: Activity, url: String): Boolean {
        val uri = Uri.parse(url)
        val chrome = Intent(Intent.ACTION_VIEW, uri).setPackage(GuideAccessibilityService.CHROME_PACKAGE)
        if (open(activity, chrome)) return true
        open(activity, Intent(Intent.ACTION_VIEW, uri))
        return false
    }
}
