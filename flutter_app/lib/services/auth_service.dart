import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class SocialAuthResult {
  final String provider; // 'google', 'apple', 'kakao'
  final String token; // Firebase ID token or Kakao access token
  final bool cancelled;

  SocialAuthResult({required this.provider, required this.token, this.cancelled = false});

  factory SocialAuthResult.cancelled() =>
      SocialAuthResult(provider: '', token: '', cancelled: true);
}

class AuthService {
  static final _auth = FirebaseAuth.instance;
  static final _googleSignIn = GoogleSignIn();

  // --- Google Sign-In ---
  static Future<SocialAuthResult> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return SocialAuthResult.cancelled();

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null) throw Exception('Failed to get Firebase ID token');

      return SocialAuthResult(provider: 'google', token: idToken);
    } catch (e) {
      debugPrint('Google sign-in error: $e');
      rethrow;
    }
  }

  // --- Apple Sign-In ---
  static Future<SocialAuthResult> signInWithApple() async {
    try {
      // Generate nonce
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      debugPrint('Apple identityToken: ${appleCredential.identityToken != null ? 'present' : 'NULL'}');
      debugPrint('Apple authorizationCode: ${appleCredential.authorizationCode != null ? 'present' : 'NULL'}');

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      final idToken = await userCredential.user?.getIdToken();
      if (idToken == null) throw Exception('Failed to get Firebase ID token');

      return SocialAuthResult(provider: 'apple', token: idToken);
    } catch (e) {
      if (e is SignInWithAppleAuthorizationException &&
          e.code == AuthorizationErrorCode.canceled) {
        return SocialAuthResult.cancelled();
      }
      debugPrint('Apple sign-in error: $e');
      rethrow;
    }
  }

  // --- Kakao Sign-In ---
  static Future<SocialAuthResult> signInWithKakao() async {
    try {
      kakao.OAuthToken token;

      // Try KakaoTalk login first, fallback to web
      if (await kakao.isKakaoTalkInstalled()) {
        try {
          token = await kakao.UserApi.instance.loginWithKakaoTalk();
        } catch (e) {
          token = await kakao.UserApi.instance.loginWithKakaoAccount();
        }
      } else {
        token = await kakao.UserApi.instance.loginWithKakaoAccount();
      }

      return SocialAuthResult(provider: 'kakao', token: token.accessToken);
    } catch (e) {
      debugPrint('Kakao sign-in error: $e');
      rethrow;
    }
  }

  // --- Auth Info Persistence ---
  static Future<void> saveAuthInfo(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('social_provider', provider);
  }

  static Future<String?> getSavedProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('social_provider');
  }

  static Future<void> clearAuthInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('social_provider');
  }

  // --- Token Refresh ---
  static Future<String?> refreshToken(String provider) async {
    try {
      if (provider == 'google' || provider == 'apple') {
        final user = _auth.currentUser;
        if (user == null) return null;
        return await user.getIdToken(true);
      } else if (provider == 'kakao') {
        // Check if Kakao token is still valid
        try {
          await kakao.UserApi.instance.accessTokenInfo();
          // Token is valid, get it from token manager
          final tokenManager = await kakao.TokenManagerProvider.instance.manager.getToken();
          return tokenManager?.accessToken;
        } catch (e) {
          return null;
        }
      }
    } catch (e) {
      debugPrint('Token refresh error: $e');
    }
    return null;
  }

  static Future<void> signOutGoogle() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  // --- Sign Out ---
  static Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await kakao.UserApi.instance.logout();
    } catch (_) {}
    await clearAuthInfo();
  }

  // --- Helpers ---
  static String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
