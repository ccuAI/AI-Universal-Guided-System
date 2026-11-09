import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// ML Kit 中文離線辨識入口。
///
/// Android 中文模型由 Gradle implementation 隨 App 打包；iOS 使用中文 Pod。
/// 每次辨識建立自己的 recognizer，並在 finally 關閉，因此離開頁面不會
/// 提前釋放仍在處理中的原生物件。此服務完全沒有 HTTP 上傳程式。
class MedicineOcrService {
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// ML Kit 需要本機路徑，因此只暫存校正後的副本，辨識結束便清除。
  /// 原始照片不被覆寫；資料保存與提醒必須等使用者確認表單後才進行。
  Future<String> recognizeBytes(Uint8List bytes) async {
    if (!supported) throw UnsupportedError('離線辨識需要 Android 或 iPhone');
    final directory = await (await getTemporaryDirectory()).createTemp(
      'medicine_ocr_',
    );
    final file = File('${directory.path}/corrected.jpg');
    try {
      await file.writeAsBytes(bytes, flush: true);
      return await recognize(XFile(file.path));
    } finally {
      try {
        if (await file.exists()) await file.delete();
        await directory.delete();
      } catch (error) {
        // 清理失敗不遮蓋真正的辨識結果／辨識例外。
        debugPrint('清理辨識暫存失敗：$error');
      }
    }
  }

  Future<String> recognize(XFile photo) async {
    if (!supported) throw UnsupportedError('離線辨識需要 Android 或 iPhone');
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      final text = result.text.trim();
      if (text.isEmpty) throw StateError('照片沒有可辨識的文字');
      return text;
    } finally {
      await recognizer.close();
    }
  }
}
