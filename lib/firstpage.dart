import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart'; // 1. 匯入 LINE SDK
import 'package:google_sign_in/google_sign_in.dart'; // 2. 匯入 Google 登入 SDK
import 'package:firebase_auth/firebase_auth.dart';


class LongTermCareLoginScreen extends StatefulWidget {
  const LongTermCareLoginScreen({super.key});


  @override
  State<LongTermCareLoginScreen> createState() => _LongTermCareLoginScreenState();
}


class _LongTermCareLoginScreenState extends State<LongTermCareLoginScreen> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
 
  bool _isLineSdkInitialized = false; // 追蹤 LINE SDK 是否初始化成功


  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId: '568574650772-5fm049p107851r9e84982pjatarufnkh.apps.googleusercontent.com',
  );

  final FirebaseAuth _auth = FirebaseAuth.instance;


@override
void initState() {
  super.initState();
 
  _initLineSdk();
}
  // ==================== LINE SDK 初始化 ====================
  Future<void> _initLineSdk() async {
    try {
      // 請確保這裡填入的是您真實的 LINE Login Channel ID
      await LineSDK.instance.setup('2012160109');
      if (!mounted) return;
      setState(() {
        _isLineSdkInitialized = true;
      });
      print("LINE SDK 初始化成功");
    } catch (e) {
      print("LINE SDK 初始化失敗: $e");
    }
  }


  // ==================== LINE 登入邏輯 ====================
  Future<void> _loginWithLine() async {
    if (!_isLineSdkInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LINE SDK 尚未準備就緒，請稍後再試')),
      );
      return;
    }
    try {
      // 呼叫 LINE 登入，並要求權限：個人檔案 (profile)、OpenID (openid)
      final result = await LineSDK.instance.login(
        scopes: ['profile', 'openid'],
      );
      // 登入驗證成功
      print("LINE 登入成功！");
      print("使用者姓名: ${result.userProfile?.displayName}");
      print("使用者 ID: ${result.userProfile?.userId}");
      print("Access Token: ${result.accessToken.value}");


      if (!mounted) return;
      // 驗證成功後跳轉至下一頁
      Navigator.pushReplacementNamed(context, 'secondpage');
    } on PlatformException catch (e) {
      print("LINE 登入失敗 (PlatformException): ${e.code} - ${e.message}");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LINE 登入失敗: ${e.message ?? '未知錯誤'}')),
      );
    } catch (e) {
      print("其他登入失敗原因: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LINE 登入失敗或已取消')),
      );
    }
  }


  // ==================== ✨ 新增：Google 登入與 Firebase 綁定邏輯 ====================
 Future<void> _loginWithGoogle() async {
  try {
    // 1. 觸發 Google 登入流程 (修正：改用標準的 signIn() 方法)
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
   
    // 檢查使用者是否取消了登入
    if (googleUser == null) {
      _showErrorSnackBar('使用者取消了 Google 登入');
      return;
    }


    // 2. 取得 Google 認證詳細資料 (修正：authentication 是屬性，不需要加 await 和 ())
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
   
    // 3. 建立 Firebase 憑證
    final AuthCredential credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );
   
    // 4. 登入 Firebase Auth
    final UserCredential userCredential = await _auth.signInWithCredential(credential);
    debugPrint('Google & Firebase 登入成功！使用者: ${userCredential.user?.displayName}');
   
    if (!mounted) return;
   
    // 5. 成功後安全跳轉
    Navigator.pushReplacementNamed(context, 'secondpage');
  } on PlatformException catch (e) {
    print("Google 登入失敗 (PlatformException): ${e.code} - ${e.message}");
    _showErrorSnackBar(e.message ?? '未知錯誤');
  } catch (e) {
    print("Google 登入其他錯誤: $e");
    _showErrorSnackBar('登入過程中發生預期外錯誤');
  }
}






  // 錯誤提示組件
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Google 登入失敗: $message'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10.0),
        ),
      ),
    );
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
                      '可視化長照 Ai 輔助系統',
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
                        // ✨ 修正：Google 登入按鈕（已綁定真實功能方法）
                        _buildSocialButton(
                          label: Image.asset("web/icons/Google.png", width: 32, height: 32),
                          color: const Color(0xFF4285F4),
                          onTap: _loginWithGoogle,
                        ),
                        // LINE 登入按鈕
                        _buildSocialButton(
                          label: Image.asset("web/icons/Line.png", width: 36, height: 36),
                          color: const Color(0xFF06C755),
                          onTap: _loginWithLine,
                        ),
                        // Facebook 登入按鈕（目前維持原樣，保留跳轉）
                        _buildSocialButton(
                          label: Image.asset("web/icons/Facebook.png", width: 36, height: 36),
                          color: const Color.fromARGB(255, 110, 126, 147),
                          onTap: () {
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
                  color: Colors.black.withOpacity(0.05),
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
            // TODO: 您可以在此處呼叫傳統的 Firebase Auth 帳密登入方法
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


  // 社群登入按鈕組件
  Widget _buildSocialButton({
    required Widget label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
boxShadow: [
BoxShadow(
color: Colors.black.withOpacity(0.15),
blurRadius: 8,
offset: const Offset(0, 4),
),
],
),
child: Center(
child: label,
),
),
);
}
}




