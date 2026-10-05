import 'package:flutter/material.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // 1. 頂部導覽列 (通知中心、客服服務、衛教宣導)
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      automaticallyImplyLeading: false,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 通知中心
            Row(
              children: const [
                Icon(Icons.notifications_none, color: Colors.black, size: 28),
                SizedBox(width: 4),
                Text('通知中心', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            // 客服服務
            Row(
              children: const [
                Text('客服服務', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(width: 4),
                Icon(Icons.support_agent, color: Colors.black, size: 28),
              ],
            ),
          ],
        ),
      ),
      // 衛教宣導橫條
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: Container(
          width: double.infinity,
          color: const Color(0xFF1A1A1A), // 深色背景
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          alignment: Alignment.centerLeft,
          child: const Text(
            '衛教宣導',
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // 2. 主頁面內容
  Widget _buildBody() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 30),
          
          // 醫療早報 & AI就醫夥伴 Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              children: [
                Expanded(
                  child: _buildMenuButton(
                    title: '醫療早報',
                    onTap: () async {
                      Navigator.pushNamed(context, "daily_med_news");
                    },
                    iconWidget: _buildCircleIcon(
                      colors: [Colors.white, const Color(0xFFE3F2FD)],
                      child: Container(
                        alignment: Alignment.center,
                        child: Image.asset(
                          'web/icons/news_icon.png',
                          width: 40,
                          height: 40,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildMenuButton(
                    title: 'AI就醫夥伴',
                    iconWidget: _buildCircleIcon(
                      colors: [Colors.white, const Color(0xFFE8F5E9)],
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.smart_toy, color: Color(0xFF66BB6A), size: 40),
                          SizedBox(height: 4),
                          Text('AI就醫夥伴', style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    onTap: ()  {
                      Navigator.pushNamed(context, "hospital_helper");
                    }, // 點擊後跳轉到 hospital_helper.dart
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 40),
          
          // 吃藥小助手
          _buildMenuButton(
            title: '吃藥小助手',
            iconWidget: _buildCircleIcon(
              colors: [const Color(0xFFFFE082), const Color(0xFFFFB74D)],
              child: Container(
                // 註：若無 pill icon 可用 medication
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('web/icons/pill_icon.png'),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            onTap: () {
              Navigator.pushNamed(context, 'medicine_taker');
            },
          ),
          
          const SizedBox(height: 50),
          
          // 當前頁面標示 "首頁"
          const Text(
            '首頁',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // 3. 底部導覽列
  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.black12, width: 0.5)),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.black87,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        items: const [
          BottomNavigationBarItem(icon: SizedBox.shrink(), label: '首頁'),
          BottomNavigationBarItem(icon: SizedBox.shrink(), label: '我的/會員中心'),
          BottomNavigationBarItem(icon: SizedBox.shrink(), label: '歷史紀錄'),
          BottomNavigationBarItem(icon: SizedBox.shrink(), label: '設定'),
        ],
      ),
    );
  }

  // 輔助組件：功能按鈕外殼
  Widget _buildMenuButton({
    required String title,
    required Widget iconWidget,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          iconWidget,
        ],
      ),
    );
  }

  // 輔助組件：圓形漸層圖標背景
  Widget _buildCircleIcon({required List<Color> colors, required Widget child}) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }
}
