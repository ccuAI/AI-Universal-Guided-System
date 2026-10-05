import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class HospitalHelperScreen extends StatefulWidget {
  const HospitalHelperScreen({super.key});

  @override
  State<HospitalHelperScreen> createState() => _HospitalHelperScreenState();

}

class _HospitalHelperScreenState extends State<HospitalHelperScreen> {
  // 1. 宣告控制器
  late final WebViewController _controller;
  bool _isLoading = true; // 用來顯示載入中動畫

  @override
  void initState() {
    super.initState();

    // 2. 初始化控制器並設定參數
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // 啟用 JavaScript
      ..setBackgroundColor(const Color(0x00000000)) // 設定透明背景
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // 網頁載入進度更新
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false; // 載入完成，隱藏動畫
            });
          },
          onWebResourceError: (WebResourceError error) {
            // 處理連線錯誤
            print('網頁載入錯誤: ${error.description}');
          },
        ),
      );
      
    _controller.loadRequest(Uri.parse('https://flutter.dev')); // 3. 設定要載入的網址
    // 4. 設定 JavaScript 與 Flutter 的通訊
    _controller.addJavaScriptChannel(
      'FlutterChannel',
      onMessageReceived: (JavaScriptMessage message) {
        print('收到網頁傳來的訊息: ${message.message}');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter 鑲入式網頁'),
        actions: [
          // 範例：重新整理按鈕
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _controller.reload(),
          ),
        ],
      ),
      // 4. 使用 Stack 將 WebView 與載入動畫疊加
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(), // 畫面載入時的圈圈
            ),
        ],
      ),
    );
  }
}

