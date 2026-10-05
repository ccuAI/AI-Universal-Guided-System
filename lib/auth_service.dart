import 'package:flutter/foundation.dart'; // 💡 引入 debugPrint
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:google_sign_in/google_sign_in.dart'; 
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart' as facebook_auth; 
import 'package:flutter_line_sdk/flutter_line_sdk.dart' as line_sdk; 

class AuthService { 
  final FirebaseAuth _auth = FirebaseAuth.instance; 
  
  // ✅ 修正 1：google_sign_in v7+ 改用 .instance，並加入初始化旗標
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance; 
  bool _isGoogleInitialized = false;

  // 輔助方法：確保 Google SDK 初始化完成
  Future<void> _ensureGoogleInitialized() async {
    if (!_isGoogleInitialized) {
      await _googleSignIn.initialize();
      _isGoogleInitialized = true;
    }
  }

  // ============================= 1. Google 登入 ============================= 
  Future<UserCredential?> signInWithGoogle() async { 
    try { 
      await _ensureGoogleInitialized();

      // ✅ 修正 2：v7+ 登入方法改為 .authenticate()
      final googleUser = await _googleSignIn.authenticate(
        scopeHint: ['email', 'openid', 'profile'],
      ); 
// 使用者取消登入

      // ✅ 修正 3：v7+ authentication 為同步屬性，移除 await
      final googleAuth = googleUser.authentication; 

      // ✅ 修正 4：v7+ 必須透過 authorizationClient 同步取得特定 Scopes 的授權資料以獲取 accessToken
      final googleAuthorization = await googleUser.authorizationClient.authorizationForScopes(['email', 'openid', 'profile']);
      
      final String? idToken = googleAuth.idToken; 
      final String? accessToken = googleAuthorization?.accessToken; // 從授權客戶端取得
      
      if (idToken == null) return null; 

      // 建立 Firebase 憑證 
      final AuthCredential credential = GoogleAuthProvider.credential( 
        accessToken: accessToken, 
        idToken: idToken, 
      ); 

      // 登入 Firebase 
      return await _auth.signInWithCredential(credential); 
    } catch (e) { 
      debugPrint('Google 登入失敗: $e'); // ✅ 修正 7：使用 debugPrint 代替 print
      return null; 
    } 
  } 

  // ==================== 2. Facebook 登入 ==================== 
  Future<UserCredential?> signInWithFacebook() async { 
    try { 
      final result = await facebook_auth.FacebookAuth.instance.login( 
        permissions: ['email', 'public_profile'], 
      ); 

      if (result.status == facebook_auth.LoginStatus.success && result.accessToken != null) { 
        // ✅ 修正 5：FacebookAuthProvider 屬於 firebase_auth，移除 facebook_auth. 前綴
        final AuthCredential credential = FacebookAuthProvider.credential( 
          result.accessToken!.tokenString, 
        ); 

        return await _auth.signInWithCredential(credential); 
      } else { 
        debugPrint('Facebook 登入狀態未成功: ${result.status}'); 
        return null; 
      } 
    } catch (e) { 
      debugPrint('Facebook 登入失敗: $e'); 
      return null; 
    } 
  } 

  // ==================== 3. LINE 登入 ==================== 
  Future<line_sdk.LoginResult?> signInWithLine() async { 
    try { 
      final result = await line_sdk.LineSDK.instance.login( 
        scopes: ["profile", "openid", "email"], 
      ); 

      final userProfile = result.userProfile; 
      debugPrint('LINE 登入成功: ${userProfile?.displayName}'); 

      return result; 
    } catch (e) { 
      debugPrint('LINE 登入失敗: $e'); 
      return null; 
    } 
  } 

  // ==================== 登出功能 ==================== 
  Future<void> signOut() async { 
    await _auth.signOut(); 
    await _ensureGoogleInitialized();
    await _googleSignIn.signOut(); 
    await facebook_auth.FacebookAuth.instance.logOut(); 
    try { 
      await line_sdk.LineSDK.instance.logout(); 
    } catch (_) {} 
  } 
}
