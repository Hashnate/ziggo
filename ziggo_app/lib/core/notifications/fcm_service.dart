// Firebase Cloud Messaging — Flutter side.
//
// Init flow (once at boot from main.dart):
//   1. Firebase.initializeApp()         — reads google-services.json
//   2. Create the Android notification channel "ziggo_ride_alerts" with the
//      custom sound ride_alert.mp3 (pinned: Android won't change a channel's
//      sound after creation, so bump the channel id if you ever swap files)
//   3. Wire onMessage (foreground), onBackgroundMessage, onTokenRefresh
//   4. Cache the FCM device token; AuthProvider pushes it to the backend
//      right after OTP-verify
//
// Foreground handling: Android does NOT auto-show notifications when the
// app is in the foreground — the message arrives via onMessage and we have
// to display it ourselves with flutter_local_notifications, otherwise the
// user only sees the in-app UI update (silent). That was the cause of "test
// push made a sound but real ride didn't" — the app was open during rides.
//
// EVERYTHING is wrapped in try/catch so missing config / revoked perms /
// mis-configured Firebase degrade to a no-op — the app keeps working, just
// without push.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/api_client.dart';

// Must match the channel_id the backend sends in FCM payloads
// (see fcm_service.py `channel_id="ziggo_ride_alerts"`). Bumping this id
// here forces Android to create a fresh channel (use this trick if you ever
// swap the sound file — Android won't update an existing channel's sound).
const String _rideAlertChannelId = 'ziggo_ride_alerts_v3';
const String _rideAlertChannelName = 'Ride alerts';
const String _rideAlertChannelDesc =
    'New ride requests and ride status updates. Plays custom sound.';

/// Required for background message handling on Android — Firebase invokes a
/// top-level function in an isolated Dart isolate. The OS shows the system
/// notification automatically using the payload, so we don't need to do
/// anything here. Must be top-level + @pragma so it survives tree-shaking.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // No-op — OS displays the notification from the payload.
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _initialised = false;
  bool _firebaseAvailable = false;
  String? _cachedToken;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenSub;

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

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
      if (kDebugMode) {
        debugPrint('[fcm] Firebase.initializeApp failed: $e — push disabled');
      }
      return;
    }

    try {
      // 1. flutter_local_notifications init (Android + iOS)
      const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _local.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      // 2. Register the Android channel with the custom sound. This is what
      //    makes the ride_alert.mp3 actually play — on Android 8+ the
      //    channel's sound is what plays, NOT the FCM payload's sound.
      //    Idempotent — calling create on an existing channel is a no-op.
      if (Platform.isAndroid) {
        await _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                _rideAlertChannelId,
                _rideAlertChannelName,
                description: _rideAlertChannelDesc,
                importance: Importance.max,
                playSound: true,
                sound: RawResourceAndroidNotificationSound('ride_alert'),
                enableVibration: true,
              ),
            );
      }

      // 3. Permissions
      final messaging = FirebaseMessaging.instance;
      if (Platform.isIOS) {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      } else if (Platform.isAndroid) {
        // Android 13+ requires runtime POST_NOTIFICATIONS permission. The
        // firebase_messaging method handles all versions transparently.
        await messaging.requestPermission(alert: true, badge: true, sound: true);
      }

      // 4. Foreground display behaviour
      //    iOS: tell the OS to show the banner + play sound when the app is
      //    in the foreground (otherwise iOS suppresses everything by default).
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 5. Wire handlers
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Handle when the app is in the background and opened by a notification tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint('[fcm] notification opened app: ${message.data}');
        }
        _handleNotificationClick(message);
      });

      // Handle when the app is completely terminated and opened by a notification tap
      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          if (kDebugMode) {
            debugPrint('[fcm] initial message: ${message.data}');
          }
          _handleNotificationClick(message);
        }
      });

      // 6. Cache token + listen for rotations
      _cachedToken = await messaging.getToken();
      _tokenSub = messaging.onTokenRefresh.listen((t) {
        _cachedToken = t;
        unawaited(_sendToBackend(t));
      });

      if (kDebugMode) {
        debugPrint('[fcm] init complete, channel=$_rideAlertChannelId, token=${_cachedToken?.substring(0, 20)}...');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] init step failed: $e');
    }
  }

  final StreamController<RemoteMessage> _clickController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onNotificationClicked => _clickController.stream;
  RemoteMessage? _pendingClick;

  RemoteMessage? consumePendingClick() {
    final msg = _pendingClick;
    _pendingClick = null;
    return msg;
  }

  void _handleNotificationClick(RemoteMessage message) {
    _pendingClick = message;
    _clickController.add(message);
  }
  /// Parses a Map<String, dynamic> FCM data payload into typed fields suitable for DriverProvider/BookingProvider.
  Map<String, dynamic> parseFcmData(Map<String, dynamic> data) {
    final result = <String, dynamic>{};
    
    data.forEach((key, value) {
      result[key] = value;
    });

    const intFields = [
      'booking_id',
      'food_order_id',
      'market_order_id',
      'duration_min',
      'expires_in_seconds',
      'rental_hours',
      'courier_eta_days',
      'stop_count',
    ];
    for (final field in intFields) {
      if (data.containsKey(field) && data[field] != null) {
        result[field] = int.tryParse(data[field]!.toString()) ?? result[field];
      }
    }

    const doubleFields = [
      'pickup_lat',
      'pickup_lng',
      'drop_lat',
      'drop_lng',
      'distance_km',
      'fare',
      'driver_earnings',
      'parcel_weight_kg',
    ];
    for (final field in doubleFields) {
      if (data.containsKey(field) && data[field] != null) {
        result[field] = double.tryParse(data[field]!.toString()) ?? result[field];
      }
    }

    const boolFields = [
      'is_flash',
      'is_rental',
      'is_courier',
      'is_food',
      'is_market',
    ];
    for (final field in boolFields) {
      if (data.containsKey(field) && data[field] != null) {
        final val = data[field]!.toString().toLowerCase();
        result[field] = val == 'true' || val == '1';
      }
    }

    return result;
  }

  /// Push the FCM token to the backend. Called after a successful login.
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
  /// BEFORE the JWT is wiped so the auth header is still attached.
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

  /// Foreground message handler — Android doesn't auto-show notifications
  /// while the app is open, so we render one ourselves with the same channel
  /// (and therefore the same sound) the OS would have used in background.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notif = message.notification;
    if (notif == null) return; // pure data-only payload — let the WS update the UI

    if (kDebugMode) {
      debugPrint('[fcm] foreground: ${notif.title} — ${notif.body}');
    }

    // Show via flutter_local_notifications. The Android channel was already
    // created in init() with the custom sound, so just referencing the
    // channel id here is enough to make ride_alert.mp3 play.
    try {
      await _local.show(
        // Unique notification id — use the FCM message hash so duplicates
        // dedupe naturally if the OS retries.
        message.messageId.hashCode,
        notif.title,
        notif.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _rideAlertChannelId,
            _rideAlertChannelName,
            channelDescription: _rideAlertChannelDesc,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('ride_alert'),
            enableVibration: true,
            // Tap → opens the app (since we don't set a payload route)
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] failed to show foreground notification: $e');
    }
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _tokenSub?.cancel();
    await _clickController.close();
  }
}
