import 'dart:convert';
import 'package:http/http.dart' as http;

class GPTService {         // GPT 服務類別範例APIKEY
  final String _apiKey = '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'; // 建議實際開發時透過環境變數隱藏
  final String _baseUrl = 'https://openai.com';

  Future<String> getGPTResponse(String userMessage) async {
    try {
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o', // 可更換為您想使用的模型
          'messages': [
            {'role': 'system', 'content': '你是一個得力的助手。'},
            {'role': 'user', 'content': userMessage}
          ],
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        // 解析 UTF-8 編碼避免中文亂碼
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['choices'][0]['message']['content'].toString().trim();
      } else {
        return '錯誤: 伺服器回應 ${response.statusCode}';
      }
    } catch (e) {
      return '連線失敗: $e';
    }
  }
}
