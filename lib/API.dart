import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GPTService {  
  // 基礎網址與端點設定
  static const String _baseUrl = 'https://api.openai.com/v1';
  static const String _chatEndpoint = '$_baseUrl/chat/completions';

  // 優先從 .env 讀取，若無則嘗試從環境編譯參數讀取
  String get _apiKey {
    return dotenv.env['OPENAI_API_KEY'] ?? const String.fromEnvironment('OPENAI_API_KEY');
  }

  /// 呼叫 GPT 進行醫療新知分析與摘要
  Future<String> getGPTResponse(String userMessage) async {
    try {
      // 確保 dotenv 已載入（防呆機制，若在 main.dart 已載入可省略此行）
      if (!dotenv.isInitialized) {
        await dotenv.load(fileName: ".env");
      }

      if (_apiKey.isEmpty) {
        return '錯誤: 找不到 API 金鑰，請確認 .env 或環境變數設定。';
      }

      final response = await http.post(
        Uri.parse(_chatEndpoint),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o', // 使用當前穩定的主流模型
          'messages': [
            {
              'role': 'system', 
              'content': '你是一個專業的醫療AI助手。請針對使用者提供的醫療新知進行嚴謹的分析，並提取出核心摘要、臨床意義與結論。'
            },
            {'role': 'user', 'content': userMessage}
          ],
          'temperature': 0.5, // 調低隨機性，使醫療摘要更嚴謹穩定
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        return '錯誤: 伺服器回應 ${response.statusCode}\n內容: ${response.body}';
      }
    } catch (e) {
      return '連線失敗: $e';
    }
  }
}

