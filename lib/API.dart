import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConfig {

  static String get gptApiKey => dotenv.env['GPT_API_KEY'] ?? '';
}

class GPTService {  
  // 基礎網址與端點設定
  static const String _baseUrl = 'https://api.openai.com/v1';
  static const String _chatEndpoint = '$_baseUrl/chat/completions';

  /// 呼叫 GPT 進行醫療新知分析與摘要
  Future<String> getGPTResponse(String userMessage) async {
    try {
      // 防呆機制：確保 dotenv 已載入
      if (!dotenv.isInitialized) {
        await dotenv.load(fileName: ".env");
      }

      if (ApiConfig.gptApiKey.isEmpty) {
        return '錯誤: 找不到 API 金鑰，請確認專案根目錄下的 .env 檔案中是否已設定 GPT_API_KEY。';
      }

      final response = await http.post(
        Uri.parse(_chatEndpoint),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer ${ApiConfig.gptApiKey}',
        },
        body: jsonEncode({
          'model': 'gpt-4o',
          'messages': [
            {
              'role': 'system', 
              'content': '你是一個專業的醫療AI助手。請針對使用者提供的醫療新知進行嚴謹的分析，並提取出核心摘要、細節整理與結論。講述口吻請以可以讓老人家了解並不產生歧異的前提為準。'
            },
            {'role': 'user', 'content': userMessage}
          ],
          'temperature': 0.5,
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

