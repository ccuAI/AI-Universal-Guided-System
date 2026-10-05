import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;                  // 引入網路套件
import 'package:webfeed_revised/webfeed_revised.dart';
   // 引入 RSS 套件

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
  bool _isAiLoading = false;
  final TextEditingController _textController = TextEditingController();

  // 1. 🔍 改為動態清單，不再寫死資料
  List<ArticleModel> _articles = [];
  bool _isLoading = true; // 記錄是否正在從網路下載新聞

  @override
  void initState() {
    super.initState();
    _fetchNews(); // 🚀 APP 一啟動，自動去抓衛福部最新消息
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // 2. 🌐 從衛福部抓取即時新聞的非同步函式
  Future<void> _fetchNews() async {
    // 這裡以衛福部焦點新聞的 RSS 訂閱源為例
    const String rssUrl = 'https://www.mohw.gov.tw/rss-16-1.html';
    const String rssUrl2 = 'https://www.mohw.gov.tw/rss-17-1.html';
    const String rssUrl3 = 'https://www.mohw.gov.tw/rss-101-1.html';
    try {
      final response = await http.get(Uri.parse(rssUrl2));
      final response2 = await http.get(Uri.parse(rssUrl));
      final response3 = await http.get(Uri.parse(rssUrl3));
      if (response.statusCode == 200 && response2.statusCode == 200 && response3.statusCode == 200) {
        // 解析從衛福部伺服器回傳的 XML 資料
        final feed = RssFeed.parse(response.body);
        final feed2 = RssFeed.parse(response2.body);
        final feed3 = RssFeed.parse(response3.body);
        final List<ArticleModel> loadedArticles = [];
        
        // feed.items 裡面就是當下最新發布的所有新聞物件
        for (var item in feed.items ?? []) {
          loadedArticles.add(
            ArticleModel(
              title: item.title ?? '無標題',
              description: item.description ?? '點擊進入閱讀詳細內容...',
              url: item.link ?? 'https://mohw.gov.tw',
            ),
          );
        }

        // feed2.items 裡面就是當下最新發布的所有新聞物件
        for (var item in feed2.items ?? []) {
          loadedArticles.add(
            ArticleModel(
              title: item.title ?? '無標題',
              description: item.description ?? '點擊進入閱讀詳細內容...',
              url: item.link ?? 'https://mohw.gov.tw',
            ),
          );
        }

        // feed3.items 裡面就是當下最新發布的所有新聞物件
        for (var item in feed3.items ?? []) {
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
          _isLoading = false; // 載入完成
        });
      } else {
        throw Exception('無法連線至衛福部伺服器');
      }
    } catch (e) {
      print('抓取新聞失敗: $e');
      setState(() {
        _isLoading = false; // 即使失敗也停止轉圈圈，可以顯示錯誤或留空
      });
    }
  }

  // ... 您的 _initWebView 與 _buildAppBar 保持不變 ...
  void _initWebView(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));
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

  // 3. 🧩 修改初始佈局：如果還在下載，畫面中間顯示轉圈圈
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
        
        // 下半部分：動態目錄清單
        Expanded(
          flex: 6,
          child: Container(
            color: Colors.white,
            // 💡 如果還在下載，顯示進度條；下載好了就渲染最新的列表
            child: _isLoading
                ? const Center(child: CircularProgressIndicator()) 
                : RefreshIndicator(
                    onRefresh: _fetchNews, // 支援使用者「下拉更新」手勢
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
                              maxLines: 2,          // 限制標題最多兩行避免破版
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

  // ... 您的 _buildSplitLayout 保持不變 ...
  Widget _buildSplitLayout() {
    return Column(
      children: [
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
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(12)),
                      child: Text(_aiResponse, style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: _isAiLoading ? '思考中...' : '針對上方文章提問...',
                          enabled: !_isAiLoading,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey[300]!)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: _isAiLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, color: Colors.blue),
                      onPressed: _isAiLoading ? null : () {}, // 配合原邏輯留空
                    ),
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

