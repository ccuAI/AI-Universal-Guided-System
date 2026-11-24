import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'guide_channel.dart';

/// AI 就醫夥伴：授權 → 輸入掛號目標 → 跳到 Chrome，由無障礙服務在畫面上引導。
///
/// 只支援 Android。引導本身在原生端（android/.../guide/）執行。
class HospitalHelperScreen extends StatefulWidget {
  const HospitalHelperScreen({super.key});

  @override
  State<HospitalHelperScreen> createState() => _HospitalHelperScreenState();
}

class _HospitalHelperScreenState extends State<HospitalHelperScreen>
    with WidgetsBindingObserver {
  // 引導伺服器預設網址：
  // - 部署到 Google Cloud Run 之後，改成 Cloud Run 給的網址（https://…run.app），組員安裝後就能直接用
  // - 還沒部署時用電腦上的伺服器（實機請先執行 adb reverse tcp:3001 tcp:3001）
  static const String _defaultBackendUrl = 'https://ai-hospital-guide-ttpkeycvfq-de.a.run.app';
  static const String _localBackendUrl = 'http://127.0.0.1:3001';

  // 雲端伺服器的通行碼（伺服器有設定 GUIDE_ACCESS_TOKEN 時才需要；沒設定就留空）
  static const String _defaultAccessToken = 'D32VBHxyFeiUBKWPBch6gALGp5SB1cGE';

  static const String _prefHospital = 'guide_hospital';
  static const String _prefUrl = 'guide_url';
  static const String _prefDepartment = 'guide_department';
  static const String _prefTime = 'guide_time';
  static const String _prefBackend = 'guide_backend_url';
  static const String _prefToken = 'guide_access_token';

  final _hospitalController = TextEditingController();
  final _urlController = TextEditingController();
  final _departmentController = TextEditingController();
  final _timeController = TextEditingController();
  final _backendController = TextEditingController(text: _defaultBackendUrl);
  final _tokenController = TextEditingController(text: _defaultAccessToken);

  bool _loading = true;
  bool _serviceEnabled = false;
  bool _guideRunning = false;
  bool _starting = false;
  int _sdkInt = 0;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hospitalController.dispose();
    _urlController.dispose();
    _departmentController.dispose();
    _timeController.dispose();
    _backendController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// 從系統設定頁或 Chrome 回來時重新檢查狀態。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _init() async {
    // 組員版本：每一步都有逾時保護，出錯也一定會關掉「載入中」
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      _hospitalController.text = prefs.getString(_prefHospital) ?? '';
      _urlController.text = prefs.getString(_prefUrl) ?? '';
      _departmentController.text = prefs.getString(_prefDepartment) ?? '';
      _timeController.text = prefs.getString(_prefTime) ?? '';
      // 之前存的是本機網址、而預設已經改成雲端時，改用新的預設（模擬器的 10.0.2.2 等自訂值保留）
      final savedBackend = prefs.getString(_prefBackend);
      _backendController.text = (savedBackend == null || savedBackend.isEmpty || savedBackend == _localBackendUrl)
          ? _defaultBackendUrl
          : savedBackend;
      // 之前存的是空的通行碼（舊版沒有通行碼）時，改用預設通行碼
      final savedToken = prefs.getString(_prefToken);
      _tokenController.text = (savedToken == null || savedToken.isEmpty) ? _defaultAccessToken : savedToken;

      if (_isAndroid) {
        try {
          _sdkInt = await GuideChannel.sdkInt()
              .timeout(const Duration(seconds: 5));
        } on PlatformException catch (e) {
          debugPrint('讀取 Android 版本失敗: $e');
        }
      }

      await _refreshStatus()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('AI 就醫夥伴初始化失敗：$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshStatus() async {
    if (!_isAndroid) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final enabled = await GuideChannel.isServiceEnabled();
      final running = await GuideChannel.isGuideRunning();
      final returnReason = await GuideChannel.consumeReturnReason();
      if (!mounted) return;
      setState(() {
        _serviceEnabled = enabled;
        _guideRunning = running;
        _loading = false;
      });
      if (returnReason == 'switch_hospital') await _resetForNewHospital();
    } on PlatformException catch (e) {
      debugPrint('檢查引導狀態失敗: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefHospital, _hospitalController.text.trim());
    await prefs.setString(_prefUrl, _urlController.text.trim());
    await prefs.setString(_prefDepartment, _departmentController.text.trim());
    await prefs.setString(_prefTime, _timeController.text.trim());
    await prefs.setString(_prefBackend, _backendController.text.trim());
    await prefs.setString(_prefToken, _tokenController.text.trim());
  }

  /// 引導途中說要換醫院：清空表單，請使用者重新輸入醫院。
  Future<void> _resetForNewHospital() async {
    _hospitalController.clear();
    _departmentController.clear();
    _timeController.clear();
    _urlController.clear();
    await _savePrefs();
    if (!mounted) return;
    _showSnack('要換醫院：請重新輸入想掛號的醫院，再按「開始引導」');
  }

  /// 沒填網址時，用 Google 搜尋「醫院名稱 網路手機掛號預約」，再由 AI 引導點進官方網站。
  String _resolveStartUrl(String hospital) {
    var url = _urlController.text.trim();
    if (url.isEmpty) {
      return 'https://www.google.com/search?q=${Uri.encodeQueryComponent('$hospital 網路手機掛號預約')}';
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    return url;
  }

  Future<bool> _checkBackend(String backendUrl) async {
    try {
      final res = await http
          .get(Uri.parse('$backendUrl/health'))
          .timeout(const Duration(seconds: 15)); // 雲端伺服器閒置後第一次連線要多等一下
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('引導伺服器連線失敗: $e');
      return false;
    }
  }

  Future<void> _startGuide() async {
    final hospital = _hospitalController.text.trim();
    final department = _departmentController.text.trim();
    final time = _timeController.text.trim();
    final backendUrl = _backendController.text.trim().replaceAll(RegExp(r'/+$'), '');

    if (hospital.isEmpty) {
      _showSnack('請先輸入要掛號的醫院');
      return;
    }

    setState(() => _starting = true);
    await _savePrefs();

    if (!await _checkBackend(backendUrl)) {
      if (!mounted) return;
      setState(() => _starting = false);
      _showSnack('連不上引導伺服器（$backendUrl），請確認網路，或伺服器已啟動');
      return;
    }

    final goal = [
      '醫院：$hospital',
      if (department.isNotEmpty) '科別：$department',
      if (time.isNotEmpty) '時間：$time',
    ].join('，');

    try {
      final inChrome = await GuideChannel.startGuide(
        goal: goal,
        url: _resolveStartUrl(hospital),
        backendUrl: backendUrl,
        accessToken: _tokenController.text.trim(),
      );
      if (!mounted) return;
      if (!inChrome) {
        _showSnack('找不到 Chrome，引導只支援 Chrome 瀏覽器，請先安裝');
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showSnack(e.message ?? '無法開始引導');
      await _refreshStatus();
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopGuide() async {
    await GuideChannel.stopGuide();
    await _refreshStatus();
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 16)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ───────────────────────── 畫面（樣式與醫療早報一致） ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        title: const Text(
          'AI 就醫夥伴',
          style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_isAndroid) {
      return _buildHeader(Icons.android, '掛號引導目前只支援 Android 手機');
    }
    return Column(
      children: [
        _buildHeader(
          Icons.local_hospital,
          _serviceEnabled
              ? '輸入想掛號的醫院，我會在 Chrome 上\n一步一步告訴您下一步要按哪裡'
              : '開始前，需要您開啟一個權限',
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: _serviceEnabled ? _buildGoalForm() : _buildPermissionGuide(),
            ),
          ),
        ),
      ],
    );
  }

  /// 上方淺藍色說明區（同醫療早報首頁）。
  Widget _buildHeader(IconData icon, String text) {
    return Container(
      width: double.infinity,
      color: Colors.blue[50],
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 56, color: Colors.blue),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.blueGrey, height: 1.5),
          ),
        ],
      ),
    );
  }

  // 1. 授權引導
  List<Widget> _buildPermissionGuide() {
    final needsRestrictedSettings = _sdkInt >= 33;
    var step = 1;

    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _tag('為什麼需要權限'),
            const SizedBox(height: 8),
            const Text(
              'AI 就醫夥伴需要「看得到」Chrome 掛號網頁上的按鈕，才能框出您下一步要按的地方。',
              style: TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            const Text(
              '• 只在您按下「開始引導」後，讀取 Chrome 畫面上的按鈕和文字\n'
              '• 不會讀取其他 App，不會送出身分證字號或您輸入的內容\n'
              '• 不會替您按下送出',
              style: TextStyle(fontSize: 14, height: 1.6, color: Colors.blueGrey),
            ),
          ],
        ),
      ),
      if (needsRestrictedSettings)
        _stepCard(
          number: step++,
          title: '允許受限設定',
          description: '按「前往設定」→ 點右上角「⋮」→ 選「允許受限設定」。\n找不到這個選項就代表不需要，直接做下一步。',
          onPressed: GuideChannel.openAppDetails,
        ),
      _stepCard(
        number: step++,
        title: '開啟「AI 就醫夥伴」',
        description: '按「前往設定」→「已安裝的應用程式」→「AI 就醫夥伴（掛號引導）」→ 打開開關。',
        onPressed: GuideChannel.openAccessibilitySettings,
      ),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        onPressed: _refreshStatus,
        icon: const Icon(Icons.refresh),
        label: const Text('我已經開啟了，重新檢查', style: TextStyle(fontSize: 16)),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    ];
  }

  // 2. 輸入掛號目標
  List<Widget> _buildGoalForm() {
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _tag('權限已開啟'),
                if (_guideRunning) ...[
                  const SizedBox(width: 8),
                  _tag('引導進行中'),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _field(_hospitalController, '醫院名稱', '例如：臺大醫院'),
            _field(_departmentController, '科別（可不填）', '例如：骨科'),
            _field(_timeController, '想看診的時間（可不填）', '例如：下週一上午'),
            _field(
              _urlController,
              '掛號網址（可不填）',
              '不填會先用 Google 搜尋',
              keyboardType: TextInputType.url,
            ),
            Theme(
              // 去掉 ExpansionTile 展開時的上下分隔線
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  '進階設定（開發用）',
                  style: TextStyle(fontSize: 14, color: Colors.blueGrey),
                ),
                children: [
                  _field(
                    _backendController,
                    '引導伺服器網址',
                    _defaultBackendUrl,
                    keyboardType: TextInputType.url,
                  ),
                  _field(
                    _tokenController,
                    '通行碼（雲端伺服器有設定才需要）',
                    '沒有就留空',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      ElevatedButton.icon(
        onPressed: _starting ? null : _startGuide,
        icon: _starting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_arrow),
        label: Text(
          _guideRunning ? '重新開始引導' : '開始引導',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      if (_guideRunning) ...[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _stopGuide,
          icon: const Icon(Icons.close, color: Colors.red),
          label: const Text('停止引導', style: TextStyle(fontSize: 16, color: Colors.red)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
      const SizedBox(height: 16),
      const Text(
        '開始後會打開 Chrome，畫面上的框會告訴您下一步按哪裡；有問題可以按「對話」問我。\n'
        '最後送出掛號前，請您自己確認資料再按下送出。',
        style: TextStyle(fontSize: 14, color: Colors.blueGrey, height: 1.5),
      ),
    ];
  }

  /// 白色卡片（同醫療早報的新聞卡片）。
  Widget _card({required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 2,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  /// 小標籤（同醫療早報的「AI 智慧助理」標籤）。
  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue[100],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _stepCard({
    required int number,
    required String title,
    required String description,
    required Future<void> Function() onPressed,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.blue[100],
                child: Text(
                  '$number',
                  style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_forward_ios, size: 14),
              label: const Text('前往設定', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
