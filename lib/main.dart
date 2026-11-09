import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'firstpage.dart';
import 'secondpage.dart';
import 'daily_med_news.dart';
import 'hospital_helper.dart';
import 'medicine_taker.dart';
import 'medicine/medicine_notification_service.dart';
import 'medicine/medicine_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

/// 保留原本的登入與首頁路由，並在 App 層處理本機通知的啟動與導頁。
/// 初始化不要求通知權限；使用者保存計畫或按「啟用通知」才會看到授權詢問。
class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _notifications = MedicineNotificationService.instance;
  bool _resynchronizing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifications.onOpenDose = _openMedicine;
    // 等 MaterialApp 建好 Navigator，再處理由通知冷啟動帶來的事件 id。
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeReminders());
  }

  Future<void> _initializeReminders() async {
    if (!_notifications.supported) return;
    try {
      await _notifications.initialize();
      if (!mounted) return;
      final doseId = _notifications.initialDoseId;
      _notifications.initialDoseId = null;
      if (doseId != null) _openMedicine(doseId);
      await _resynchronize();
    } catch (error) {
      // 原生通知初始化失敗不阻止進入 App；服藥頁會顯示可重試的排程狀態。
      debugPrint('初始化用藥提醒失敗：$error');
    }
  }

  void _openMedicine(int doseId) {
    if (!mounted) return;
    _navigator.currentState?.push<void>(
      CupertinoPageRoute(
        settings: const RouteSettings(name: 'medicine_taker'),
        builder: (_) => MedicineTakerPage(initialDoseId: doseId),
      ),
    );
  }

  Future<void> _resynchronize() async {
    if (_resynchronizing || !_notifications.supported) return;
    _resynchronizing = true;
    try {
      // 即使回到的是首頁，也要延伸長期計畫並重查權限與當地時區。
      await MedicineRepository.instance.ensureUpcomingDoses();
      await _notifications.synchronize();
    } catch (error) {
      debugPrint('回到 App 時同步用藥提醒失敗：$error');
    } finally {
      _resynchronizing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resynchronize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notifications.onOpenDose = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      title: '可視化長照 AI 輔助系統',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const LongTermCareLoginScreen(),
      routes: {
        'secondpage': (context) => const HomeScreen(),
        'firstpage': (context) => const LongTermCareLoginScreen(),
        'daily_med_news': (context) => const MedNews(),
        'Med_news': (context) => const MedNews(),
        'home': (context) => const HomeScreen(),
        'hospital_helper': (context) => const HospitalHelperScreen(),
        'webview': (context) => const HospitalHelperScreen(),
      },
      // 命名路由也使用 CupertinoPageRoute，讓左邊緣向右滑可回上一頁。
      // 頁面內水平滑動則交給三個分頁，不攔截整頁手勢以免衝突。
      onGenerateRoute: (settings) {
        if (settings.name != 'medicine_taker') return null;
        return CupertinoPageRoute<void>(
          settings: settings,
          builder: (_) => MedicineTakerPage(
            initialDoseId: settings.arguments is int
                ? settings.arguments as int
                : null,
          ),
        );
      },
    );
  }
}
