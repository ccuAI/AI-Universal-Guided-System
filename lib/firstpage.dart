import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_line_sdk/flutter_line_sdk.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LongTermCareLoginScreen extends StatefulWidget {
  const LongTermCareLoginScreen({super.key});

  @override
  State<LongTermCareLoginScreen> createState() =>
      _LongTermCareLoginScreenState();
}

class _LongTermCareLoginScreenState extends State<LongTermCareLoginScreen> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLineSdkInitialized = false;

  // 沿用原專案的 Google Sign-In 6.x 寫法；若使用 7.x 須另外遷移 API。
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    serverClientId:
        '568574650772-5fm049p107851r9e84982pjatarufnkh.apps.googleusercontent.com',
  );
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _initLineSdk();
  }

  Future<void> _initLineSdk() async {
    try {
      await LineSDK.instance.setup('2012349789');
      if (!mounted) return;
      setState(() => _isLineSdkInitialized = true);
      debugPrint('LINE SDK 初始化成功');
    } catch (e) {
      debugPrint('LINE SDK 初始化失敗: $e');
    }
  }

  Future<void> _loginWithLine() async {
    if (!_isLineSdkInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LINE SDK 尚未準備就緒，請稍後再試')),
      );
      return;
    }
    try {
      await LineSDK.instance.login(scopes: ['profile', 'openid']);
      // 不記錄 access token 等敏感資訊。
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, 'secondpage');
    } on PlatformException catch (e) {
      debugPrint('LINE 登入失敗: ${e.code} - ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('LINE 登入失敗: ${e.message ?? '未知錯誤'}')),
      );
    } catch (e) {
      debugPrint('LINE 登入失敗或取消: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('LINE 登入失敗或已取消')),
      );
    }
  }

  Future<void> _loginWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _showErrorSnackBar('使用者取消了 Google 登入');
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      await _auth.signInWithCredential(credential);

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, 'secondpage');
    } on PlatformException catch (e) {
      debugPrint('Google 登入失敗: ${e.code} - ${e.message}');
      _showErrorSnackBar(e.message ?? '未知錯誤');
    } catch (e) {
      debugPrint('Google 登入發生錯誤: $e');
      _showErrorSnackBar('登入過程中發生預期外錯誤');
    }
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Google 登入：$message'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.red,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
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
      // 鍵盤彈出時縮小內容區，再由 SingleChildScrollView 提供捲動。
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final compactWidth = width < 600;
                  final compactHeight = constraints.maxHeight < 550;
                  final sidePadding = width < 360 ? 16.0 : 24.0;
                  final titleSize = width < 360
                      ? 23.0
                      : compactWidth
                          ? 27.0
                          : 32.0;

                  return SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      // 螢幕高時內容垂直置中；螢幕矮或鍵盤彈出時可滾動。
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: sidePadding,
                              vertical: compactHeight ? 24 : 44,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '可視化長照 AI 輔助系統',
                                  textAlign: TextAlign.center,
                                  softWrap: true,
                                  style: TextStyle(
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                    letterSpacing: compactWidth ? 0.5 : 1.5,
                                  ),
                                ),
                                SizedBox(height: compactHeight ? 28 : 52),
                                _buildCustomInputField(
                                  controller: _accountController,
                                  hintText: '請輸入帳號',
                                  compact: compactWidth,
                                ),
                                SizedBox(height: compactHeight ? 18 : 26),
                                _buildCustomInputField(
                                  controller: _passwordController,
                                  hintText: '請輸入密碼',
                                  isObscure: true,
                                  compact: compactWidth,
                                ),
                                SizedBox(height: compactHeight ? 32 : 60),
                                // 手機、平板與桌面皆維持三顆按鈕並排。
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildSocialButton(
                                      semanticLabel: '使用 Google 登入',
                                      size: compactWidth ? 54 : 60,
                                      label: Image.asset(
                                        'web/icons/google.png',
                                        width: 32,
                                        height: 32,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(Icons.g_mobiledata,
                                                color: Colors.white),
                                      ),
                                      color: const Color(0xFF4285F4),
                                      onTap: _loginWithGoogle,
                                    ),
                                    _buildSocialButton(
                                      semanticLabel: '使用 LINE 登入',
                                      size: compactWidth ? 54 : 60,
                                      label: Image.asset(
                                        'web/icons/Line.png',
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Text('LINE',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                      ),
                                      color: const Color(0xFF06C755),
                                      onTap: _loginWithLine,
                                    ),
                                    _buildSocialButton(
                                      semanticLabel: 'Facebook（目前僅頁面跳轉）',
                                      size: compactWidth ? 54 : 60,
                                      label: Image.asset(
                                        'web/icons/Facebook.png',
                                        width: 36,
                                        height: 36,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            const Text('f',
                                                style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 28,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                      ),
                                      color: const Color.fromARGB(
                                          255, 110, 126, 147),
                                      onTap: () => Navigator.pushNamed(
                                        context,
                                        'secondpage',
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logoWidth = math.max(
          0.0,
          math.min(200.0, constraints.maxWidth - 32.0),
        );
        return Container(
          width: double.infinity,
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: logoWidth,
            height: 56,
            child: Image.asset(
              'web/icons/779240515145235692.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Align(
                alignment: Alignment.centerLeft,
                child: Text('長照輔助系統'),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomInputField({
    required TextEditingController controller,
    required String hintText,
    required bool compact,
    bool isObscure = false,
  }) {
    final height = compact ? 54.0 : 60.0;
    final arrowSize = compact ? 50.0 : 60.0;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(height / 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
            alignment: Alignment.center,
            child: TextField(
              controller: controller,
              obscureText: isObscure,
              textInputAction: isObscure
                  ? TextInputAction.done
                  : TextInputAction.next,
              decoration: InputDecoration(
                hintText: hintText,
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(color: Colors.grey[400]),
              ),
            ),
          ),
        ),
        SizedBox(width: compact ? 10 : 16),
        Semantics(
          button: true,
          label: '清除此欄位文字',
          child: InkWell(
            borderRadius: BorderRadius.circular(arrowSize / 2),
            onTap: () {
              // 沿用原程式的清空欄位行為，不再印出帳號或密碼。
              // TODO: 若要執行帳密登入，請在此串接正式驗證流程。
              controller.clear();
            },
            child: Container(
              width: arrowSize,
              height: arrowSize,
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
        ),
      ],
    );
  }

  Widget _buildSocialButton({
    required String semanticLabel,
    required double size,
    required Widget label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(child: label),
        ),
      ),
    );
  }
}
