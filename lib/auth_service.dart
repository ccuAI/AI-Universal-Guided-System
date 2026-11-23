import 'package:flutter/foundation.dart'; // 💡 引入 debugPrint
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:google_sign_in/google_sign_in.dart'; 
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart' as facebook_auth; 
import 'package:flutter_line_sdk/flutter_line_sdk.dart' as line_sdk; 

class AuthService { 
  final FirebaseAuth _auth = FirebaseAuth.instance; 
  
  // Use the GoogleSignIn API supported by the installed package version.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'openid', 'profile'],
  );

  // ============================= 1. Google 登入 ============================= 
  Future<UserCredential?> signInWithGoogle() async { 
    try { 
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;
// 使用者取消登入

      final googleAuth = await googleUser.authentication;
      
      final String? idToken = googleAuth.idToken; 
      final String? accessToken = googleAuth.accessToken;
      
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
     
        final AuthCredential credential = FacebookAuthProvider.credential( 
          result.accessToken!.token,
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
    await _googleSignIn.signOut(); 
    await facebook_auth.FacebookAuth.instance.logOut(); 
    try { 
      await line_sdk.LineSDK.instance.logout(); 
    } catch (_) {} 
  } 
}
