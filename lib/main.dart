import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'firstpage.dart';
import 'secondpage.dart';
import 'daily_med_news.dart';
import 'hospital_helper.dart';
import 'medicine_taker.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    if (e.toString().contains('duplicate-app')) {
      debugPrint("Firebase 已在其他地方初始化，忽略此重複建立的錯誤。");
    } else {
      rethrow;
    }
  }

  // 全域隱藏下方系統導覽列與上方狀態列
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '可視化長照 AI 輔助系統',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LongTermCareLoginScreen(),
      routes: {
        'secondpage': (context) => const HomeScreen(),
        'firstpage': (context) => const LongTermCareLoginScreen(),
        'daily_med_news': (context) => const MedNews(),
        'Med_news': (context) => const MedNews(),
        'home': (context) => const HomeScreen(),
        'medicine_taker': (context) => const MedicineTakerPage(),
        'hospital_helper': (context) => const HospitalHelperScreen(),
        'webview': (context) => const HospitalHelperScreen(),
},
    );
  }
}

