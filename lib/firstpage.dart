import 'package:flutter/material.dart';

class LongTermCareLoginScreen extends StatefulWidget {
  const LongTermCareLoginScreen({super.key});

  @override
  State<LongTermCareLoginScreen> createState() => _LongTermCareLoginScreenState();
}

class _LongTermCareLoginScreenState extends State<LongTermCareLoginScreen> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  // 實例化您的 AuthService 登入服務
 // final AuthService _authService = AuthService();

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 背景採用圖片中的淺藍色調
      backgroundColor: const Color(0xFFDDEEFA), 
      body: SafeArea(
        child: Column(
          children: [
            // 1. 頂部衛福部 Header 區塊 (已修正括號語法錯誤)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
                  // Logo 預留位置(先用衛福部圖示代替)
                  SizedBox(
                    width: 200,
                    height: 60,
                    child: Center(
                      child: Image.asset(
                        "web/icons/779240515145235692.png",
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ), 

            // 中間主要內容填充與對齊
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 2. 主標題
                    const Text(
                      '可視化長照Ai輔助系統',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 60),

                    // 3. 第一個輸入框
                    _buildCustomInputField(
                      controller: _accountController,
                      hintText: '請輸入帳號',
                    ),
                    const SizedBox(height: 30),

                    // 4. 第二個輸入框
                    _buildCustomInputField(
                      controller: _passwordController,
                      hintText: '請輸入密碼',
                      isObscure: true,
                    ),
                    const SizedBox(height: 80),

                    // 5. 第三方登入按鈕列 (已將圖片按鈕成功連結 AuthService)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Google 登入按鈕
                        _buildSocialButton(
                          label: Container(
                            child: Image.asset("web/icons/Google.png"),
                          ),
                          color: const Color(0xFF4285F4),
                          textColor: Colors.white,
                          fontSize: 12,
                          onTap: () async {
                            Navigator.pushNamed(context, "secondpage");
                          },
                        ),
                        // LINE 登入按鈕
                        _buildSocialButton(
                          label: ClipOval(
                            child: Image.asset(
                              "web/icons/Line.png",
                              fit: BoxFit.contain,
                            ),
                          ),
                          color: const Color(0xFF06C755),
                          textColor: Colors.white,
                          fontSize: 12,
                          onTap: () {
                            Navigator.pushReplacementNamed(context, 'secondpage');
                            // print('點擊了 LINE 圖片登入');
                            // final lineResult = await _authService.signInWithLine();
                            // if (lineResult != null) {
                            //   print("LINE 登入成功！用戶: ${lineResult.userProfile?.displayName}");
                            //   // TODO: 登入成功後的跳轉邏輯
                            // }
                          },
                        ),
                        // Facebook 登入按鈕
                        _buildSocialButton(
                          label: ClipOval(
                            child: Image.asset(
                              "web/icons/Facebook.png",
                              fit: BoxFit.contain,
                            ),
                          ),
                          color: const Color.fromARGB(255, 110, 126, 147),
                          textColor: Colors.white,
                          fontSize: 12,
                          onTap: () async {
                            Navigator.pushNamed(context, "secondpage");
                            // 2. 執行 Facebook 登入邏輯 (目前為註解狀態)
                            // await facebook_auth.FacebookAuth.instance.loginWithReadPermissions(['email']);
                            // final facebookResult = await facebook_auth.FacebookAuth.instance.loginWithReadPermissions(['email']);
                            // if (facebookResult != null) {
                            //   print("Facebook 登入成功！用戶: ${facebookResult.userProfile?.id}");
                            // }
                            // print('點擊了 Facebook 圖片登入');
                            // final userCredential = await _authService.signInWithFacebook();
                            // if (userCredential != null) {
                            //   print("Facebook 登入成功！用戶: ${userCredential.user?.displayName}");
                            //   // TODO: 登入成功後的跳轉邏輯
                            // }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 自訂輸入框組件
  Widget _buildCustomInputField({
    required TextEditingController controller,
    required String hintText,
    bool isObscure = false,
  }) {
    return Row(
      children: [
        // 左側白色膠囊型輸入框
        Expanded(
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            alignment: Alignment.center,
            child: TextField(
              controller: controller,
              obscureText: isObscure,
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey[400]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        // 右側黑色圓形按鈕
        GestureDetector(
          onTap: () {
            // 目前是清除輸入，若要改為提交帳密傳統登入，可以在這裡寫 API 對接
            print('點擊右側按鈕，當前輸入內容: ${controller.text}');
            controller.clear();
          },
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // 社群登入按鈕組件 (加入 Padding 確保圖片不會貼邊)
  Widget _buildSocialButton({
    required Widget label,
    required Color color,
    required Color textColor,
    double fontSize = 24,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 65,
        height: 65,
        padding: const EdgeInsets.all(4.0), // 留出一點邊距讓底色圓圈露出來
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
            child: label,
          ),
        ),
      ),
    );
  }
}

