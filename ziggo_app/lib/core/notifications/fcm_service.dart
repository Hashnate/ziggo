// Firebase Cloud Messaging — Flutter side.
//
// Initialised once at app boot from main.dart. Auth provider calls
// registerWithBackend() right after a successful OTP-verify, and
// clearOnBackend() before clearing the JWT on logout.
//
// EVERYTHING is wrapped in try/catch so that:
//   - missing google-services.json (Android) or GoogleService-Info.plist (iOS)
//   - revoked permissions
//   - Firebase project being mis-configured
// degrade to a no-op — the rest of the app keeps working.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../network/api_client.dart';

/// Required for background message handling on Android — Firebase invokes a
/// top-level function in an isolated Dart isolate. We don't process the
/// message ourselves (the OS shows the system notification); this handler
/// exists so Firebase doesn't complain about a missing registration.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op — the system notification UI handles display.
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _initialised = false;
  bool _firebaseAvailable = false;
  String? _cachedToken;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenSub;

  bool get firebaseAvailable => _firebaseAvailable;
  String? get cachedToken => _cachedToken;

  /// Call once during app startup, BEFORE runApp.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    try {
      await Firebase.initializeApp();
      _firebaseAvailable = true;
    } catch (e) {
      // No google-services.json / no GoogleService-Info.plist → init throws.
      // We swallow and the rest of FcmService becomes a no-op.
      if (kDebugMode) {
        debugPrint('[fcm] Firebase.initializeApp failed: $e — push disabled');
      }
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;

      // iOS needs an explicit permission grant. Android auto-grants below v33.
      if (Platform.isIOS) {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      }

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Cache token now and observe rotations so the backend always has the
      // freshest one.
      _cachedToken = await messaging.getToken();
      _tokenSub = messaging.onTokenRefresh.listen((t) {
        _cachedToken = t;
        // If the user is logged in, push the rotated token straight away.
        unawaited(_sendToBackend(t));
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] init step failed: $e');
    }
  }

  /// Push the FCM token to the backend. Called by AuthProvider right after
  /// a successful login. Silently no-ops if Firebase isn't initialised yet.
  Future<bool> registerWithBackend() async {
    if (!_firebaseAvailable) return false;
    try {
      _cachedToken ??= await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return false;
    }
    final token = _cachedToken;
    if (token == null || token.isEmpty) return false;
    return _sendToBackend(token);
  }

  /// Clear the FCM token on the backend so the device stops getting pushes
  /// addressed to the previous user. Called from AuthProvider.logout()
  /// BEFORE the JWT is wiped, so the auth header is still attached.
  Future<void> clearOnBackend() async {
    if (!_firebaseAvailable) return;
    try {
      await ApiClient.instance.dio.put(
        '/auth/fcm-token',
        data: {'token': null},
      );
    } catch (_) {
      // Best-effort — losing the unregister is not fatal.
    }
  }

  Future<bool> _sendToBackend(String token) async {
    try {
      final resp = await ApiClient.instance.dio.put(
        '/auth/fcm-token',
        data: {'token': token},
      );
      return resp.data is Map && resp.data['ok'] == true;
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('[fcm] register failed: ${e.message}');
      return false;
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    // We don't show a local notification when the app is in the foreground —
    // the WebSocket has already delivered the event live and the UI has
    // already updated. The OS-level notification only shows when the app is
    // backgrounded / killed (handled by the OS itself, no code needed).
    if (kDebugMode) {
      debugPrint(
        '[fcm] foreground message: ${message.notification?.title} — '
        '${message.notification?.body}',
      );
    }
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _tokenSub?.cancel();
  }
}
