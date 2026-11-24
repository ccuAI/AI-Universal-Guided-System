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

  static const _ink = Color(0xFF103B35);
  static const _green = Color(0xFF075C50);
  static const _paper = Color(0xFFFAF7F2);
  static const _outline = Color(0xFFBBCDB8);

  bool _passwordVisible = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: Image.asset('web/icons/KinecTap2.png'),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTitle(),
                              const SizedBox(height: 30),
                              _buildInput(
                                controller: _accountController,
                                hint: '電子郵件',
                                icon: Icons.mail_outline_rounded,
                              ),
                              const SizedBox(height: 14),
                              _buildInput(
                                controller: _passwordController,
                                hint: '密碼',
                                icon: Icons.lock_outline_rounded,
                                isPassword: true,
                              ),
                              const SizedBox(height: 18),
                              _buildLoginButton(),
                              const SizedBox(height: 20),
                            
                              const SizedBox(height: 18),
                              _buildSocialRow(),
                              const SizedBox(height: 28),
                              _buildFooter(),
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
    );
  }

  Widget _buildTitle() {
    return const Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '長照輔助整合系統',
            style: TextStyle(
              color: _ink,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        SizedBox(height: 2),
        Text(
          'KinecTap',
          style: TextStyle(
            color: Color(0xFF004B40),
            fontSize: 46,
            height: 1.15,
            letterSpacing: -0.8,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Kind Instructor for elders and caregivers',
            style: TextStyle(
              color: Color(0xFF597755),
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: BoxDecoration(
        color: const Color(0xFFFCFAF8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _outline, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x110E3020),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Icon(icon, color: _green, size: 27),
          ),
          Container(width: 1, height: 28, color: _outline),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: isPassword && !_passwordVisible,
              textInputAction:
                  isPassword ? TextInputAction.done : TextInputAction.next,
              style: const TextStyle(color: _ink, fontSize: 18),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: Color(0xFF636963)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 15),
                isDense: true,
              ),
            ),
          ),
          // 保留原本每個欄位的清空功能。
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, child) {
              return value.text.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: '清除此欄位文字',
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close_rounded,
                          color: _green, size: 21),
                    );
            },
          ),
          if (isPassword) ...[
            Container(width: 1, height: 28, color: _outline),
            IconButton(
              tooltip: _passwordVisible ? '隱藏密碼' : '顯示密碼',
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _green,
                size: 26,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLoginButton() {
    // 原始程式未實作帳號密碼驗證：保留純介面按鈕，不新增登入邏輯。
    return Tooltip(
      message: '電子郵件登入尚未串接，請使用下方登入方式',
      child: Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(36),
          gradient: const LinearGradient(
            colors: [Color(0xFF0C685B), Color(0xFF045347)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x290B5545),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: Colors.transparent,
            disabledForegroundColor: Colors.white,
            shadowColor: Colors.transparent,
            elevation: 0,
            shape: const StadiumBorder(),
          ),
          child: const Text(
            '登入',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSocialRow() {
    return Row(
      children: [
        Expanded(
          child: _buildSocialButton(
            name: 'LINE',
            asset: 'web/icons/Line.png',
            color: const Color(0xFF06C755),
            fallback: const Text('LINE',
                style: TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w900, fontSize: 15)),
            semanticLabel: '使用 LINE 登入',
            onTap: _loginWithLine,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSocialButton(
            name: 'Google',
            asset: 'web/icons/google.png',
            color: const Color(0xFF4285F4),
            fallback: const Icon(Icons.g_mobiledata, color: Colors.white,
                size: 44),
            semanticLabel: '使用 Google 登入',
            onTap: _loginWithGoogle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSocialButton(
            name: 'Facebook',
            asset: 'web/icons/Facebook.png',
            color: const Color(0xFF0866FF),
            fallback: const Icon(Icons.facebook, color: Colors.white,
                size: 44),
            semanticLabel: 'Facebook（目前僅頁面跳轉）',
            onTap: () => Navigator.pushNamed(context, 'secondpage'),
          ),
        ),
      ],
    );
  }

  Widget _buildSocialButton({
    required String name,
    required String asset,
    required Color color,
    required Widget fallback,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: const Color(0xFFFCFAF8),
        elevation: 2,
        shadowColor: const Color(0x33728768),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFCED8C5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
            child: Column(
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: Image.asset(
                    asset,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(color: color,
                          shape: BoxShape.circle),
                      child: Center(child: fallback),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        const Text('© KinecTap',
            style: TextStyle(color: Color(0xFF646963), fontSize: 14)),
        const SizedBox(height: 5),
        Align(
          alignment: Alignment.center,
                   child: Image.asset(
            'web/icons/779240515145235692.png',
            width: 170,
            height: 48,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Text(
              '長照輔助系統',
              style: TextStyle(color: _ink, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }
}



