import 'package:flutter/material.dart';
import 'firstpage.dart';
import 'secondpage.dart';
import 'daily_med_news.dart';
import 'hospital_helper.dart';
import 'medicine_taker.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      // 💡 2. 加上這段路由表註冊，導航功能才會生效！
      routes: {
        'secondpage': (context) => const HomeScreen(),
        "firstpage": (context) => const LongTermCareLoginScreen(),
        "daily_med_news": (context) => const MedNews(), 
        "Med_news": (context) => const MedNews(),
        "home": (context) => const HomeScreen(),
        "hospital_helper": (context) => const HospitalHelperScreen(),
        "webview": (context) => const HospitalHelperScreen(),
        "medicine_taker": (context) => const MedicineTakerPage(),
      },
    );
  }
}




