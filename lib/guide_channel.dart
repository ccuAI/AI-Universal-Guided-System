import 'package:flutter/services.dart';

/// AI 就醫夥伴：呼叫 Android 原生端（GuideChannel.kt）的介面。
class GuideChannel {
  GuideChannel._();

  static const MethodChannel _channel = MethodChannel('com.med.myproject/guide');

  static Future<int> sdkInt() async =>
      await _channel.invokeMethod<int>('sdkInt') ?? 0;

  /// 使用者是否已在系統設定開啟「AI 就醫夥伴（掛號引導）」無障礙服務。
  static Future<bool> isServiceEnabled() async =>
      await _channel.invokeMethod<bool>('isServiceEnabled') ?? false;

  static Future<bool> isGuideRunning() async =>
      await _channel.invokeMethod<bool>('isGuideRunning') ?? false;

  static Future<void> openAccessibilitySettings() =>
      _channel.invokeMethod('openAccessibilitySettings');

  /// 開啟本 App 的「應用程式資訊」頁（Android 13+ 要在這裡「允許受限設定」）。
  static Future<void> openAppDetails() => _channel.invokeMethod('openAppDetails');

  /// 開始引導並用 Chrome 開啟 [url]。回傳是否成功用 Chrome 開啟。
  static Future<bool> startGuide({
    required String goal,
    required String url,
    required String backendUrl,
  }) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('startGuide', {
      'goal': goal,
      'url': url,
      'backendUrl': backendUrl,
    });
    return result?['openedInChrome'] == true;
  }

  static Future<void> stopGuide() => _channel.invokeMethod('stopGuide');
}
