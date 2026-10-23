import 'package:flutter/material.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart'; // 1. 匯入 LINE SDK

class LongTermCareLoginScreen extends StatefulWidget {
  const LongTermCareLoginScreen({super.key});

  @override
  State<LongTermCareLoginScreen> createState() => _LongTermCareLoginScreenState();
}

class _LongTermCareLoginScreenState extends State<LongTermCareLoginScreen> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSdkInitialized = false; // 追蹤 SDK 是否初始化成功

  @override
  void initState() {
    super.initState();
    _initLineSdk(); // 2. 在初始化時設定 LINE SDK
  }

  Future<void> _initLineSdk() async {
    try {
      await LineSDK.instance.setup('YOUR_CHANNEL_ID'); 
      setState(() {
        _isSdkInitialized = true;
      });
      print("LINE SDK 初始化成功");

      // 💡 新增這行：這會讓 App 啟動時，直接在 debug 終端機印出當前正確的 Android Key Hash
      await LineSDK.instance.currentAccessToken;
      // 註：flutter_line_sdk 在特定 debug 模式或初始化錯誤時，會在原生的 log 中自動輸出當前應填寫的 Key Hash。
      
    } catch (e) {
      print("LINE SDK 初始化失敗: $e");
    }
  }


  // 實作 LINE 登入驗證邏輯
  Future<void> _loginWithLine() async {
    if (!_isSdkInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LINE SDK 尚未準備就緒，請稍後再試')),
      );
      return;
    }

    try {
      // 呼叫 LINE 登入，並要求權限：個人檔案 (profile)、OpenID (openid)、電子信箱 (email)
      final result = await LineSDK.instance.login(
        scopes: ['profile', 'openid', 'email'],
      );

      // 登入驗證成功
      print("LINE 登入成功！");
      print("使用者姓名: ${result.userProfile?.displayName}");
      print("使用者 ID: ${result.userProfile?.userId}");
      print("Access Token: ${result.accessToken.value}");

      if (mounted) {
        // 驗證成功後跳轉至下一頁
        Navigator.pushReplacementNamed(context, 'secondpage');
      }
    } catch (e) {
      // 使用者取消登入，或發生網路、平台憑證錯誤
      print("LINE 登入失敗: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('LINE 登入失敗或已取消')),
        );
      }
    }
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 144, 186, 219), 
      body: SafeArea(
        child: Column(
          children: [
            // 1. 頂部衛福部 Header 區塊
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                children: [
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

            // 中間主要內容
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

                    // 3. 帳號輸入框
                    _buildCustomInputField(
                      controller: _accountController,
                      hintText: '請輸入帳號',
                    ),
                    const SizedBox(height: 30),

                    // 4. 密碼輸入框
                    _buildCustomInputField(
                      controller: _passwordController,
                      hintText: '請輸入密碼',
                      isObscure: true,
                    ),
                    const SizedBox(height: 80),

                    // 社群登入按鈕列
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Google 登入按鈕
                        _buildSocialButton(
                          label: Image.asset("web/icons/Google.png"),
                          color: const Color(0xFF4285F4),
                          textColor: Colors.white,
                          onTap: () async {
                            Navigator.pushNamed(context, "secondpage");
                          },
                        ),
                        
                        // LINE 登入按鈕（已串接真實登入驗證）
                        _buildSocialButton(
                          label: ClipOval(
                            child: Image.asset(
                              "web/icons/Line.png",
                              fit: BoxFit.contain,
                            ),
                          ),
                          color: const Color(0xFF06C755),
                          textColor: Colors.white,
                          onTap: _loginWithLine, // 3. 綁定 LINE 登入方法
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
                          onTap: () async {
                            Navigator.pushNamed(context, "secondpage");
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
        GestureDetector(
          onTap: () {
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

  // 社群登入按鈕組件（將多餘未定義的參數簡化）
  Widget _buildSocialButton({
    required Widget label,
    required Color color,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: label,
      ),
    );
  }
}
