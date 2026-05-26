import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/api_client.dart';

/// Background message handler — MUST be a top-level / static function and
/// MUST be annotated `@pragma('vm:entry-point')` so the AOT compiler keeps
/// it alive in release builds (it's invoked from a fresh isolate).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    debugPrint(
      '[fcm-bg] ${message.messageId} '
      'data=${message.data} '
      'notification=${message.notification?.title}',
    );
  }
}

/// Singleton wrapper around Firebase Messaging that is safe to call even when
/// Firebase isn't configured yet — `init()` catches the error and falls back
/// to a no-op so the rest of the app still boots.
///
/// Lifecycle:
///   1. `main()` calls `FcmService.instance.init()` once before `runApp`.
///   2. After a successful login, call `FcmService.instance.registerWithBackend()`
///      to ship the device token to `PUT /api/v1/auth/fcm-token`.
///   3. On logout, call `FcmService.instance.clearOnBackend()` to remove it.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _initialised = false;
  String? _initError;
  String? _cachedToken;
  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;

  bool get initialised => _initialised;
  String? get initError => _initError;
  String? get currentToken => _cachedToken;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    if (_initialised) return;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      _initError = 'Firebase.initializeApp failed: $e';
      debugPrint('[fcm] $_initError');
      return;
    }

    try {
      final messaging = FirebaseMessaging.instance;

      // iOS / Android 13+ need an explicit permission grant.
      final settings = await messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[fcm] notification permission denied — tokens still work');
      }

      await _setupLocalChannel();

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      _cachedToken = await messaging.getToken();
      debugPrint('[fcm] token=${_cachedToken?.substring(0, 20)}...');
      _tokenSub = messaging.onTokenRefresh.listen((newToken) {
        _cachedToken = newToken;
        debugPrint('[fcm] token rotated, re-registering');
        registerWithBackend();
      });

      _initialised = true;
    } catch (e) {
      _initError = 'FCM setup failed: $e';
      debugPrint('[fcm] $_initError');
    }
  }

  Future<void> _setupLocalChannel() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosInit = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    // Channel id MUST match the one set by the server (`ziggo_default`).
    const channel = AndroidNotificationChannel(
      'ziggo_default',
      'Ziggo Alerts',
      description: 'Ride updates, payments, promotions',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  Future<void> _onForegroundMessage(RemoteMessage msg) async {
    final n = msg.notification;
    if (n == null) return;
    await _local.show(
      msg.hashCode,
      n.title,
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'ziggo_default', 'Ziggo Alerts',
          channelDescription: 'Ride updates, payments, promotions',
          importance: Importance.high, priority: Priority.high,
          icon: '@mipmap/launcher_icon',
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  /// Send the cached token to the backend so push messages route correctly.
  Future<bool> registerWithBackend() async {
    if (!_initialised || _cachedToken == null) return false;
    try {
      await ApiClient.instance.dio.put(
        '/auth/fcm-token',
        data: {'token': _cachedToken},
      );
      return true;
    } on DioException catch (e) {
      debugPrint('[fcm] registerWithBackend failed: ${e.message}');
      return false;
    }
  }

  Future<void> clearOnBackend() async {
    try {
      await ApiClient.instance.dio.put('/auth/fcm-token', data: {'token': ''});
    } on DioException {
      // ignore — we're logging out anyway.
    }
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _tokenSub?.cancel();
  }
}
