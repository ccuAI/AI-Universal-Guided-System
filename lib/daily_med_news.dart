import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;                  
import 'package:webfeed_revised/webfeed_revised.dart';
import 'API.dart';

class ArticleModel {
  final String title;
  final String description;
  final String url;

  ArticleModel({required this.title, required this.description, required this.url});
}

class MedNews extends StatefulWidget {
  const MedNews({super.key});

  @override
  State<MedNews> createState() => _MedNewsState();
}

class _MedNewsState extends State<MedNews> {
  String? _selectedUrl;
  String? _selectedTitle;
  WebViewController? _webViewController;

  String _aiResponse = "您好！我是您的 AI 助理。已經為您準備好上方的醫療網頁，請問有什麼不明白的地方想諮詢嗎？";
  bool _isAiLoading = false; // 🚀 用來記錄 AI 是否正在分析
  final TextEditingController _textController = TextEditingController();

  List<ArticleModel> _articles = [];
  bool _isLoading = true; 

  @override
  void initState() {
    super.initState();
    _fetchNews(); 
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _fetchNews() async {
    const String rssUrl = 'https://www.mohw.gov.tw/rss-16-1.html';
    try {
      final response = await http.get(Uri.parse(rssUrl));
      if (response.statusCode == 200) {
        final feed = RssFeed.parse(response.body);
        final List<ArticleModel> loadedArticles = [];
        for (var item in feed.items ?? []) {
          loadedArticles.add(
            ArticleModel(
              title: item.title ?? '無標題',
              description: item.description ?? '點擊進入閱讀詳細內容...',
              url: item.link ?? 'https://mohw.gov.tw',
            ),
          );
        }
        setState(() {
          _articles = loadedArticles;
          _isLoading = false; 
        });
      } else {
        throw Exception('無法連線至衛福部伺服器');
      }
    } catch (e) {
      print('抓取新聞失敗: $e');
      setState(() {
        _isLoading = false; 
      });
    }
  }

  //初始化 WebView 並在網頁載入完畢時「自動獲取資訊」
  void _initWebView(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String url) async {
            // 1. 當網頁完全載入後，透過 JS 抽取全網頁的純文字資訊
            final dynamic rawText = await _webViewController?.runJavaScriptReturningResult(
              "window.document.body.innerText;"
            );

            if (rawText != null) {
              String pageText = rawText.toString();
              
              // 2. 清理部分平台 JS 回傳字串前後會自動包裹引號與換行符號的問題
              pageText = pageText.replaceAll(r'\n', '\n').trim();
              if (pageText.startsWith('"') && pageText.endsWith('"')) {
                pageText = pageText.substring(1, pageText.length - 1);
              }

              // 3. 🚀 隨時獲取資訊：將網頁純文字丟給 AI 進行分析
              _analyzeMedicalNewsWithAI(pageText);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));
  }

  // 🤖 呼叫您的 AI APP / API 處理分析與摘要
  Future<void> _analyzeMedicalNewsWithAI(String webContent) async {
    setState(() {
      _isAiLoading = true;
      _aiResponse = "AI 助理正在為您閱讀與分析網頁資訊，請稍候...";
    });

    try {
      final response = await GPTService().getGPTResponse(webContent);
      setState(() {
        _aiResponse = response;
        _isAiLoading = false;
      });
    } catch (e) {
      setState(() {
        _aiResponse = "抱歉，AI 助理在分析網頁時發生錯誤，請重新點選試試。";
        _isAiLoading = false;
      });
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      automaticallyImplyLeading: false,
      title: Text(
        _selectedUrl == null ? '今日醫療新知' : 'AI 輔助閱讀：$_selectedTitle',
        style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      actions: [
        if (_selectedUrl != null)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: '關閉視窗回到目錄',
            onPressed: () {
              setState(() {
                _selectedUrl = null;
                _selectedTitle = null;
                _webViewController = null;
                _aiResponse = "您好！我是您的 AI 助理。已經為您準備好上方的醫療網頁，請問有什麼不明白的地方想諮詢嗎？";
              });
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: _buildAppBar(),
      resizeToAvoidBottomInset: true, 
      body: _selectedUrl == null ? _buildInitLayout() : _buildSplitLayout(),
    );
  }

  Widget _buildInitLayout() {
    return Column(
      children: [
        Expanded(
          flex: 4,
          child: Container(
            color: Colors.blue[50],
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.health_and_safety, size: 64, color: Colors.blue),
                  SizedBox(height: 12),
                  Text(
                    '歡迎使用長照 AI 輔助系統\n請在下方目錄選擇您想閱讀的醫療新知',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.blueGrey, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 6,
          child: Container(
            color: Colors.white,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator()) 
                : RefreshIndicator(
                    onRefresh: _fetchNews, 
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _articles.length,
                      itemBuilder: (context, index) {
                        final article = _articles[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          elevation: 2,
                          child: ListTile(
                            leading: const Icon(Icons.article, color: Colors.blue),
                            title: Text(
                              article.title, 
                              style: const TextStyle(fontWeight: FontWeight.bold),
                              maxLines: 2,          
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              article.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                            onTap: () {
                              setState(() {
                                _selectedUrl = article.url;
                                _selectedTitle = article.title;
                                _initWebView(article.url);
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
String question="";
  // 🧩 為您補全並優化的 _buildSplitLayout 佈局
  Widget _buildSplitLayout() {
    return Column(
      children: [
        // 上半部：網頁顯示區
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey, width: 2)),
            ),
            child: _webViewController != null
                ? WebViewWidget(controller: _webViewController!)
                : const Center(child: CircularProgressIndicator()),
          ),
        ),
        // 下半部：AI 智慧助理對話/回應區
        Expanded(
          flex: 5,
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue[100], borderRadius: BorderRadius.circular(4)),
                      child: const Text('AI 智慧助理', style: TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    // 如果 AI 正在載入，在標籤旁轉圈圈提示使用者
                    if (_isAiLoading)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // AI 回應文字滾動區
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                      child: Text(

_aiResponse,
style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87)
),
),
),
),
const SizedBox(height: 8),

Row(
children: [
Expanded(
child: TextField(
controller: _textController,
decoration: InputDecoration(
hintText: '輸入問題以諮詢此醫療新知...',
isDense: true,
contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
),
),
),
const SizedBox(width: 8),
IconButton(
icon: const Icon(Icons.send, color: Colors.blue),
onPressed: () {
if (_textController.text.trim().isNotEmpty) {
  question=_textController.text.trim();
  _analyzeMedicalNewsWithAI(question);
  _textController.clear();
}
},
)
],
),
],
),
),
),
],
);
}
}
