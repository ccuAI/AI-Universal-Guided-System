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

// 1. 頂部導覽列
PreferredSizeWidget _buildAppBar() {
return AppBar(
backgroundColor: Colors.white,
elevation: 0,
automaticallyImplyLeading: false,
titleSpacing: 0,
title: LayoutBuilder(
builder: (context, constraints) {
final isSmall = constraints.maxWidth < 360;

      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isSmall ? 12 : 20,
        ),
        child: Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_none,
                    color: Colors.black,
                    size: isSmall ? 24 : 28,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '通知中心',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: isSmall ? 15 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '客服服務',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: isSmall ? 15 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.support_agent,
                    color: Colors.black,
                    size: isSmall ? 24 : 28,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  ),
  bottom: PreferredSize(
    preferredSize: const Size.fromHeight(40),
    child: Container(
      width: double.infinity,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(
        vertical: 8,
        horizontal: 16,
      ),
      alignment: Alignment.centerLeft,
      child: const Text(
        '衛教宣導',
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
  ),
);

}

// 2. 響應式主頁面
Widget _buildBody() {
return LayoutBuilder(
builder: (context, constraints) {
final screenWidth = constraints.maxWidth;

    final isMobile = screenWidth < 600;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 20.0;
    final iconSize = screenWidth < 360 ? 64.0 : (isMobile ? 78.0 : 96.0);
    final titleSize = isMobile ? 22.0 : 26.0;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 720,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: isMobile ? 24 : 40,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '首頁',
                  style: TextStyle(
                    fontSize: isMobile ? 28 : 34,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF163348),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '請選擇您需要的服務',
                  style: TextStyle(fontSize: 17, color: Color(0xFF536675)),
                ),
                const SizedBox(height: 24),
                _buildMenuButton(
                  title: '醫療早報',
                  subtitle: '閱讀最新醫療資訊',
                  fontSize: titleSize*1.1,
                  iconSize: iconSize*1.8,
                  assetPath: 'web/icons/37810-removebg-preview.png',
                  fallbackIcon: Icons.menu_book,
                  accent: const Color(0xFF9A5317),
                  background: const Color(0xFFFFF4E8),
                  onTap: () => Navigator.pushNamed(context, 'daily_med_news'),
                ),
                const SizedBox(height: 24),
                _buildMenuButton(
                  title: 'AI就醫夥伴',
                  subtitle: '了解就醫與醫療分級資訊',
                  fontSize: titleSize*1.1,
                  iconSize: iconSize*1.8,
                  assetPath: 'web/icons/37821-removebg-preview.png',
                  fallbackIcon: Icons.medical_services_outlined,
                  accent: const Color(0xFF1766A1),
                  background: const Color(0xFFEAF4FD),
                  onTap: () => Navigator.pushNamed(context, 'hospital_helper'),
                ),
                const SizedBox(height: 24),
                _buildMenuButton(
                  title: '吃藥小助手',
                  subtitle: '管理您的用藥資訊',
                  fontSize: titleSize,
                  iconSize: iconSize*1.8,
                  assetPath: 'web/icons/37812-removebg-preview.png',
                  fallbackIcon: Icons.medication,
                  accent: const Color(0xFF226B49),
                  background: const Color(0xFFEAF7EF),
                  onTap: () => Navigator.pushNamed(context, 'medicine_taker'),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  },
);

}

// 3. 響應式底部導覽列
Widget _buildBottomNavigationBar() {
return LayoutBuilder(
builder: (context, constraints) {
final isMobile = constraints.maxWidth < 600;

    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.black12,
            width: 0.5,
          ),
        ),
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
        selectedFontSize: isMobile ? 12 : 14,
        unselectedFontSize: isMobile ? 11 : 14,
        selectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
        items: [
          const BottomNavigationBarItem(
            icon: SizedBox.shrink(),
            label: '首頁',
          ),
          BottomNavigationBarItem(
            icon: const SizedBox.shrink(),
            label: isMobile
                ? '會員中心'
                : '我的/會員中心',
          ),
          const BottomNavigationBarItem(
            icon: SizedBox.shrink(),
            label: '歷史紀錄',
          ),
          const BottomNavigationBarItem(
            icon: SizedBox.shrink(),
            label: '設定',
          ),
        ],
      ),
    );
  },
);

}

// 4. 功能按鈕
Widget _buildMenuButton({
required String title,
required String subtitle,
required String assetPath,
required IconData fallbackIcon,
required Color accent,
required Color background,
required double fontSize,
required double iconSize,
required VoidCallback onTap,
}) {
final radius = BorderRadius.circular(18);
return Material(
color: background,
elevation: 2,
shadowColor: accent.withValues(alpha: 0.18),
shape: RoundedRectangleBorder(
borderRadius: radius,
side: BorderSide(color: accent.withValues(alpha: 0.16)),
),
clipBehavior: Clip.antiAlias,
child: InkWell(
onTap: onTap,
borderRadius: radius,
child: Padding(
padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
child: Row(
children: [
Container(
width: iconSize,
height: iconSize,
padding: const EdgeInsets.all(6),
decoration: BoxDecoration(
color: Colors.white,
borderRadius: BorderRadius.circular(14),
),
child: Image.asset(
assetPath,
fit: BoxFit.contain,
errorBuilder: (context, error, stackTrace) => Icon(
fallbackIcon,
color: accent,
size: iconSize * 0.55,
),
),
),
const SizedBox(width: 14),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
mainAxisSize: MainAxisSize.min,
children: [
Text(
title,
style: TextStyle(
fontSize: fontSize,
fontWeight: FontWeight.w700,
color: const Color(0xFF163348),
),
),
const SizedBox(height: 6),
Text(
subtitle,
style: const TextStyle(
fontSize: 16,
height: 1.4,
color: Color(0xFF465C6B),
),
),
],
),
),
const SizedBox(width: 8),
Icon(Icons.chevron_right_rounded, color: accent, size: 30),
],
),
),
),
);
}
}



