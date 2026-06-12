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
import 'dart:typed_data';

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
const String _rideAlertChannelId = 'ziggo_ride_alerts_v5';
const String _rideAlertChannelName = 'Ride alerts';
const String _rideAlertChannelDesc =
    'New ride requests. Plays continuous custom sound.';

const String _foodAlertChannelId = 'ziggo_food_alerts_v3';
const String _foodAlertChannelName = 'Food and order alerts';
const String _foodAlertChannelDesc =
    'Food and market order updates. Plays custom sound.';

// Fixed notification id for the ride-alert so it can be cancelled later. The
// ride alert plays an INSISTENT (looping) sound, which keeps ringing until the
// notification is cancelled — so accept / decline / timeout must cancel THIS id
// to stop the sound. A fixed id also means a new request replaces the old one
// rather than stacking.
const int _rideAlertNotificationId = 7001;

const String _generalAlertChannelId = 'ziggo_general_alerts_v2';
const String _generalAlertChannelName = 'General updates';
const String _generalAlertChannelDesc =
    'Status updates and general notifications. Plays system default sound.';

/// Required for background message handling on Android — Firebase invokes a
/// top-level function in an isolated Dart isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The background isolate is a fresh Dart VM — Firebase must be re-initialised
  // here or any Firebase call (and some plugin plumbing) fails on release.
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  // Hybrid messages now carry a notification block, which the OS displays
  // itself while the app is backgrounded / killed. Rendering our own here too
  // would duplicate it — so only handle pure data-only payloads manually.
  if (message.notification != null) return;

  final data = message.data;
  final event = data['event'];
  if (event == 'new_ride_request') {
    final title = data['title'] ?? 'New ride request';
    final body = data['body'] ?? 'Tap to accept';

    final local = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    await local.initialize(const InitializationSettings(android: androidInit));

    await local.show(
      _rideAlertNotificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'ziggo_ride_alerts_v5',
          'Ride alerts',
          channelDescription: 'New ride requests. Plays continuous custom sound.',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('ride_alert'),
          additionalFlags: Int32List.fromList(<int>[4]),
          enableVibration: true,
        ),
      ),
    );
  }
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  Future<void>? _initFuture;
  bool _firebaseAvailable = false;
  String? _cachedToken;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<String>? _tokenSub;

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  bool get firebaseAvailable => _firebaseAvailable;
  String? get cachedToken => _cachedToken;

  /// Call once during app startup. Idempotent — repeated calls return the same
  /// in-flight (or completed) future, so callers can `await init()` to be sure
  /// the device token has been fetched before registering it with the backend.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
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

      // 2. Register the Android channels.
      //    Idempotent — calling create on an existing channel is a no-op.
      if (Platform.isAndroid) {
        final androidPlugin = _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.createNotificationChannel(
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
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              _foodAlertChannelId,
              _foodAlertChannelName,
              description: _foodAlertChannelDesc,
              importance: Importance.max,
              playSound: true,
              sound: RawResourceAndroidNotificationSound('food_alert'),
              enableVibration: true,
            ),
          );
          await androidPlugin.createNotificationChannel(
            const AndroidNotificationChannel(
              _generalAlertChannelId,
              _generalAlertChannelName,
              description: _generalAlertChannelDesc,
              importance: Importance.defaultImportance,
              playSound: true,
              enableVibration: true,
            ),
          );
        }
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
    // Wait for init() to finish (it fetches the token) so a fast login right
    // after launch doesn't no-op before Firebase is ready.
    await init();
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
    final event = message.data['event'];
    final isRideRequest = event == 'new_ride_request';

    String? title;
    String? body;

    if (isRideRequest) {
      title = message.data['title'] ?? 'New ride request';
      body = message.data['body'] ?? 'Tap to accept';
    } else {
      final notif = message.notification;
      if (notif == null) return; // pure data-only payload — let the WS update the UI
      title = notif.title;
      body = notif.body;
    }

    if (kDebugMode) {
      debugPrint('[fcm] foreground: $title — $body');
    }

    final isFoodOrMarket = message.data['is_food'] == 'true' ||
        message.data['is_market'] == 'true' ||
        event == 'food_order_update' ||
        event == 'order_update' ||
        event == 'market_order_update';

    String channelId;
    String channelName;
    String channelDesc;
    AndroidNotificationSound? androidSound;
    bool insistent = false;
    Importance importance = Importance.defaultImportance;
    Priority priority = Priority.defaultPriority;
    String? iosSound;

    if (isRideRequest) {
      channelId = _rideAlertChannelId;
      channelName = _rideAlertChannelName;
      channelDesc = _rideAlertChannelDesc;
      androidSound = const RawResourceAndroidNotificationSound('ride_alert');
      insistent = true;
      importance = Importance.max;
      priority = Priority.high;
      iosSound = 'ride_alert.caf';
    } else if (isFoodOrMarket) {
      channelId = _foodAlertChannelId;
      channelName = _foodAlertChannelName;
      channelDesc = _foodAlertChannelDesc;
      androidSound = const RawResourceAndroidNotificationSound('food_alert');
      importance = Importance.max;
      priority = Priority.high;
      iosSound = 'food_alert.caf';
    } else {
      channelId = _generalAlertChannelId;
      channelName = _generalAlertChannelName;
      channelDesc = _generalAlertChannelDesc;
      androidSound = null;
    }

    try {
      await _local.show(
        // Ride alerts use a fixed id so they can be cancelled (to stop the
        // looping sound) and so a new request replaces the old one. Other
        // notifications use the FCM message hash so they dedupe / stack.
        isRideRequest ? _rideAlertNotificationId : message.messageId.hashCode,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: importance,
            priority: priority,
            playSound: true,
            sound: androidSound,
            additionalFlags: insistent ? Int32List.fromList(<int>[4]) : null,
            enableVibration: true,
            // Tap → opens the app (since we don't set a payload route)
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: iosSound,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] failed to show foreground notification: $e');
    }
  }

  /// Cancel the active ride-alert notification — call this the moment a request
  /// is accepted, declined, or expires so the looping insistent sound stops.
  Future<void> cancelRideAlert() async {
    try {
      await _local.cancel(_rideAlertNotificationId);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _tokenSub?.cancel();
    await _clickController.close();
  }
}
