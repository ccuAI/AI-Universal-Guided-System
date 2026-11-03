import 'dart:math' as math;
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

        // 手機兩欄，平板與電腦三欄
        final isMobile = screenWidth < 600;
        final columns = isMobile ? 2 : 3;

        // 內容最大寬度限制
        final maxContentWidth =
            math.min(screenWidth, 960.0);

        final horizontalPadding =
            screenWidth < 360 ? 12.0 : 20.0;

        final spacing = isMobile ? 12.0 : 24.0;

        final availableWidth =
            maxContentWidth - horizontalPadding * 2;

        // 自動計算每個功能的寬度
        final itemWidth =
            (availableWidth - spacing * (columns - 1)) /
            columns;

        // 圖片大小隨著容器寬度改變
        final iconSize =
            (itemWidth * 0.8).clamp(80.0, 155.0);

        final titleSize = isMobile ? 18.0 : 22.0;

        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 960,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: isMobile ? 24 : 40,
                ),
                child: Column(
                  children: [
                    // 自動換行的功能選單
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: spacing,
                      runSpacing: isMobile ? 36 : 28,
                      children: [
                        // 醫療早報
                        SizedBox(
                          width: itemWidth,
                          child: _buildMenuButton(
                            title: '醫療早報',
                            fontSize: titleSize,
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                'daily_med_news',
                              );
                            },
                            iconWidget: Image.asset(
                              'web/icons/37810-removebg-preview.png',
                              width: iconSize,
                              height: iconSize,
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (context, error, stackTrace) {
                                return _buildPlaceholderIcon(
                                  Icons.menu_book,
                                  Colors.orange,
                                  iconSize,
                                );
                              },
                            ),
                          ),
                        ),

                        // AI 就醫夥伴
                        SizedBox(
                          width: itemWidth,
                          child: _buildMenuButton(
                            title: 'AI就醫夥伴',
                            fontSize: titleSize,
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                'hospital_helper',
                              );
                            },
                            iconWidget: _buildCircleIcon(
                              size: iconSize,
                              colors: const [
                                Colors.white,
                                Color(0xFFE8F5E9),
                              ],
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.smart_toy,
                                    color: const Color(0xFF66BB6A),
                                    size: iconSize * 0.34,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'AI就醫夥伴',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize:
                                          iconSize < 100 ? 10 : 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // 吃藥小助手
                        SizedBox(
                          width: itemWidth,
                          child: _buildMenuButton(
                            title: '吃藥小助手',
                            fontSize: titleSize,
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                'medicine_taker',
                              );
                            },
                            iconWidget: Image.asset(
                              'web/icons/37812-removebg-preview.png',
                              width: iconSize,
                              height: iconSize,
                              fit: BoxFit.contain,
                              errorBuilder:
                                  (context, error, stackTrace) {
                                return _buildPlaceholderIcon(
                                  Icons.medication,
                                  Colors.green,
                                  iconSize,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: isMobile ? 45 : 60),

                    Text(
                      '首頁',
                      style: TextStyle(
                        fontSize: isMobile ? 28 : 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),

                    const SizedBox(height: 20),
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
    required Widget iconWidget,
    required double fontSize,
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
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          iconWidget,
        ],
      ),
    );
  }

  // 5. 圓形漸層圖示
  Widget _buildCircleIcon({
    required double size,
    required List<Color> colors,
    required Widget child,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(child: child),
    );
  }

  // 6. 圖片載入失敗時的備用圖示
  Widget _buildPlaceholderIcon(
    IconData icon,
    Color color,
    double size,
  ) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: size * 0.4,
        color: color,
      ),
    );
  }
}

