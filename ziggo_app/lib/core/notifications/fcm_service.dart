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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../network/api_client.dart';
import 'notification_router.dart';

// Must match the channel_id the backend sends in FCM payloads
// (see fcm_service.py `channel_id="ziggo_ride_alerts"`). Bumping this id
// here forces Android to create a fresh channel (use this trick if you ever
// swap the sound file — Android won't update an existing channel's sound).
const String _rideAlertChannelId = 'ziggo_ride_alarm_v9';
const String _rideAlertChannelName = 'Ride alarms';
const String _rideAlertChannelDesc =
    'New ride requests. Sounds like an alarm until you respond or it expires.';

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

  final data = message.data;
  final event = data['event'];

  if (event == 'new_ride_request') {
    // Android only: iOS renders the banner itself from the APNs alert payload.
    // This path initialises the plugin with Android-only settings, and iOS
    // reaches it because the backend sets content-available on ride requests.
    if (!Platform.isAndroid) return;

    final title = data['title'] ?? 'Incoming Ride Request';
    final body = data['body'] ?? 'Tap to view and accept the ride';

    final local = FlutterLocalNotificationsPlugin();
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    await local.initialize(const InitializationSettings(android: androidInit));

    // Ensure the call channel exists in the background isolate before showing
    final androidPlugin = local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        // Not const: vibrationPattern needs Int64List.fromList, a non-const
        // factory. Mirrors the main-isolate channel below.
        AndroidNotificationChannel(
          _rideAlertChannelId,
          _rideAlertChannelName,
          description: _rideAlertChannelDesc,
          importance: Importance.max,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('ride_alert'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        ),
      );
    }

    await showRideAlarm(local, title, body, data);
  }
}

/// The Android ride alarm. Shared by the FCM background isolate (app killed or
/// suspended) and the main isolate (app alive on its WebSocket in the
/// background) — both use the same notification id, so whichever fires second
/// replaces the first instead of stacking a duplicate.
Future<void> showRideAlarm(
  FlutterLocalNotificationsPlugin plugin,
  String title,
  String body,
  Map<String, dynamic> data,
) async {
  await plugin.show(
    _rideAlertNotificationId,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _rideAlertChannelId,
        _rideAlertChannelName,
        channelDescription: _rideAlertChannelDesc,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('ride_alert'),
        // Alarm stream: audible even with the ringer on silent, like a clock
        // alarm. Volume follows the phone's alarm slider, not the ringer.
        audioAttributesUsage: AudioAttributesUsage.alarm,
        category: AndroidNotificationCategory.alarm,
        // FLAG_INSISTENT (4) — loop the sound until the notification clears.
        additionalFlags: Int32List.fromList(<int>[4]),
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
        // Alarm-style banner: heads-up, can't be swiped away, and keeps
        // sounding until the driver opens it (the in-app sheet then takes
        // over), acts on it, or the 30 s accept window expires. No Accept /
        // Decline buttons — acting happens in the app only. No full-screen
        // takeover either; it shows on the lock screen as a banner.
        ongoing: true,
        autoCancel: false,
        timeoutAfter: 30000, // matches expires_in_seconds: 30 from backend
        visibility: NotificationVisibility.public,
      ),
    ),
    payload: jsonEncode(data),
  );
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  Future<void>? _initFuture;
  bool _firebaseAvailable = false;
   String? _cachedToken;
  String? _lastUploadedToken;
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
      unawaited(_logToServer('[fcm] Firebase initialized successfully on iOS/Android.'));
      await _installIosNotificationSounds();
    } catch (e) {
      unawaited(_logToServer('[fcm] Firebase.initializeApp failed: $e'));
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
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            try {
              final decoded = jsonDecode(payload);
              if (decoded is Map<String, dynamic>) {
                _handleNotificationDataClick(decoded);
                return;
              }
            } catch (e) {
              if (kDebugMode) debugPrint('[fcm] local notif payload decode error: $e');
            }
          }
          _handleNotificationDataClick({'event': 'broadcast_message'});
        },
      );

      // 2. Register the Android channels.
      //    Idempotent — calling create on an existing channel is a no-op.
      if (Platform.isAndroid) {
        final androidPlugin = _local
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.createNotificationChannel(
            AndroidNotificationChannel(
              _rideAlertChannelId,
              _rideAlertChannelName,
              description: _rideAlertChannelDesc,
              importance: Importance.max,
              playSound: true,
              sound: const RawResourceAndroidNotificationSound('ride_alert'),
              audioAttributesUsage: AudioAttributesUsage.alarm,
              enableVibration: true,
              vibrationPattern: Int64List.fromList([0, 1000, 500, 1000, 500, 1000]),
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
      if (Platform.isIOS) {
        final apns = await messaging.getAPNSToken();
        if (apns != null) {
          try {
            _cachedToken = await messaging.getToken();
          } catch (_) {}
        }
      } else {
        _cachedToken = await messaging.getToken();
      }
      unawaited(_logToServer('[fcm] init step 6 done, cachedToken: ${(_cachedToken != null && _cachedToken!.length > 15) ? _cachedToken!.substring(0, 15) : _cachedToken}...'));
      _tokenSub = messaging.onTokenRefresh.listen((t) {
        _cachedToken = t;
        unawaited(_logToServer('[fcm] onTokenRefresh triggered: ${(t.length > 15) ? t.substring(0, 15) : t}...'));
        unawaited(_sendToBackend(t));
      });

      if (kDebugMode) {
        debugPrint('[fcm] init complete, channel=$_rideAlertChannelId, token=${_cachedToken?.substring(0, 20)}...');
      }
    } catch (e) {
      unawaited(_logToServer('[fcm] init step failed: $e'));
      if (kDebugMode) debugPrint('[fcm] init step failed: $e');
    }
  }

  Future<void> _logToServer(String msg) async {
    try {
      await ApiClient.instance.dio.post(
        '/public/log',
        data: {'message': msg},
      );
    } catch (_) {}
  }

  final StreamController<RemoteMessage> _clickController = StreamController<RemoteMessage>.broadcast();
  Stream<RemoteMessage> get onNotificationClicked => _clickController.stream;
  RemoteMessage? _pendingClick;
  Map<String, dynamic>? _pendingDataClick;

  final StreamController<Map<String, dynamic>> _foregroundEventsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onForegroundEvent => _foregroundEventsController.stream;

  RemoteMessage? consumePendingClick() {
    final msg = _pendingClick;
    _pendingClick = null;
    return msg;
  }

  Map<String, dynamic>? consumePendingDataClick() {
    final d = _pendingDataClick;
    _pendingDataClick = null;
    return d;
  }

  void _handleNotificationClick(RemoteMessage message) {
    _pendingClick = message;
    _pendingDataClick = message.data;
    _clickController.add(message);
    NotificationRouter.handleNotification(message.data);
  }

  void _handleNotificationDataClick(Map<String, dynamic> data) {
    _pendingDataClick = data;
    NotificationRouter.handleNotification(data);
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
  /// Push the FCM token to the backend. Called after a successful login.
  Future<bool> registerWithBackend() async {
    unawaited(_logToServer('[fcm] registerWithBackend called. waiting for init...'));
    await init();
    unawaited(_logToServer('[fcm] init finished inside registerWithBackend. firebaseAvailable: $_firebaseAvailable'));
    if (!_firebaseAvailable) return false;
    
    if (Platform.isIOS && _cachedToken == null) {
      unawaited(_logToServer('[fcm] iOS device: checking APNS token before retrieving FCM token...'));
      String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      int apnsRetries = 0;
      while (apnsToken == null && apnsRetries < 15) {
        unawaited(_logToServer('[fcm] APNS token is null, waiting... try $apnsRetries'));
        await Future.delayed(const Duration(seconds: 1));
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        apnsRetries++;
      }
      if (apnsToken == null) {
        unawaited(_logToServer('[fcm] APNS token failed to register after 15 seconds. Make sure your provisioning/certificates match.'));
      } else {
        unawaited(_logToServer('[fcm] APNS token successfully set: ${apnsToken.length > 10 ? apnsToken.substring(0, 10) : apnsToken}...'));
      }
    }

    String? token = _cachedToken;
    unawaited(_logToServer('[fcm] starting token retrieval loop. initial cached token: ${(token != null && token.length > 15) ? token.substring(0, 15) : token}'));
    // Retry up to 8 times with a 1-second delay if the token is null (very common on iOS startup/login)
    for (int i = 0; i < 8; i++) {
      if (token != null && token.isNotEmpty) break;
      try {
        token = await FirebaseMessaging.instance.getToken();
        unawaited(_logToServer('[fcm] getToken loop try $i: ${(token != null && token.length > 15) ? token.substring(0, 15) : token}'));
      } catch (e) {
        unawaited(_logToServer('[fcm] getToken loop try $i threw error: $e'));
      }
      if (token == null || token.isEmpty) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    _cachedToken = token;
    unawaited(_logToServer('[fcm] token retrieval loop finished. cachedToken: ${(token != null && token.length > 15) ? token.substring(0, 15) : token}'));
    
    if (token == null || token.isEmpty) return false;
    if (token == _lastUploadedToken) {
      unawaited(_logToServer('[fcm] token already uploaded, skipping backend call'));
      return true;
    }
    return _sendToBackend(token);
  }

  /// Clear the FCM token on the backend so the device stops getting pushes
  /// addressed to the previous user. Called from AuthProvider.logout()
  /// BEFORE the JWT is wiped so the auth header is still attached.
  Future<void> clearOnBackend() async {
    _cachedToken = null; // Also clear local cache so next login retrieves a fresh one!
    _lastUploadedToken = null;
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
      unawaited(_logToServer('[fcm] PUT fcm-token payload sending...'));
      final resp = await ApiClient.instance.dio.put(
        '/auth/fcm-token',
        data: {'token': token},
      );
      final ok = resp.data is Map && resp.data['ok'] == true;
      unawaited(_logToServer('[fcm] PUT fcm-token resp status: ${resp.statusCode}, ok: $ok'));
      if (ok) {
        _lastUploadedToken = token;
      }
      return ok;
    } on DioException catch (e) {
      unawaited(_logToServer('[fcm] PUT fcm-token threw DioException: ${e.message}, response: ${e.response?.data}'));
      if (kDebugMode) debugPrint('[fcm] register failed: ${e.message}');
      return false;
    } catch (e) {
      unawaited(_logToServer('[fcm] PUT fcm-token threw unknown exception: $e'));
      return false;
    }
  }

  /// Foreground message handler — Android doesn't auto-show notifications
  /// while the app is open, so we render one ourselves with the same channel
  /// (and therefore the same sound) the OS would have used in background.
  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final event = message.data['event'];
    final isRideRequest = event == 'new_ride_request';

    // Ride requests in the foreground are alerted IN-APP: the WebSocket event
    // pops the request sheet, which loops the ride-alert sound itself. Showing
    // an FCM notification here as well would double the sound, so skip it. The
    // OS still shows the alert when the app is backgrounded/killed (that path
    // is handled by the system, not this foreground handler).
    if (isRideRequest) return;

    final notif = message.notification;
    if (notif == null) return; // pure data-only payload — let the WS update the UI
    final String? title = notif.title;
    final String? body = notif.body;

    if (kDebugMode) {
      debugPrint('[fcm] foreground: $title — $body');
    }

    // Emit event so providers can listen to push notifications and refresh state
    _foregroundEventsController.add(message.data);

    final isFoodOrMarket = message.data['is_food'] == 'true' ||
        message.data['is_market'] == 'true' ||
        event == 'food_order_update' ||
        event == 'order_update' ||
        event == 'market_order_update';

    String channelId;
    String channelName;
    String channelDesc;
    AndroidNotificationSound? androidSound;
    Importance importance = Importance.defaultImportance;
    Priority priority = Priority.defaultPriority;
    String? iosSound;

    if (isFoodOrMarket) {
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
        // FCM message hash as the id so these notifications dedupe / stack.
        message.messageId.hashCode,
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
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            sound: iosSound,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] failed to show foreground notification: $e');
    }
  }

  /// Cancel the active ride-alert notification — call this the moment a request
  /// is accepted, declined, or expires so the looping insistent sound stops.
  /// iOS only plays a custom notification sound from the main bundle or from
  /// the app's Library/Sounds folder. Flutter assets are in neither, so copy
  /// the .caf files there on every launch (cheap, and picks up replacements).
  /// Without this the backend's `sound: ride_alert.caf` silently falls back to
  /// the quiet default tone — the "silent" ride request.
  Future<void> _installIosNotificationSounds() async {
    if (!Platform.isIOS) return;
    try {
      final lib = await getLibraryDirectory();
      final dir = Directory('${lib.path}/Sounds');
      if (!await dir.exists()) await dir.create(recursive: true);
      for (final name in const ['ride_alert.caf', 'food_alert.caf']) {
        final data = await rootBundle.load('assets/sounds/$name');
        await File('${dir.path}/$name').writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
      }
      if (kDebugMode) debugPrint('[fcm] iOS notification sounds installed');
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] iOS sound install failed: $e');
    }
  }

  /// Raise the ride alarm from the live app. Used when a request arrives over
  /// the WebSocket while the app is alive but not on screen (backgrounded or
  /// phone locked during an online session). Android only: iOS shows the
  /// APNs banner itself and a local one on top would duplicate it.
  Future<void> showRideAlarmFromApp(Map<String, dynamic> data) async {
    if (!Platform.isAndroid) return;
    try {
      final title = (data['title'] ?? 'Incoming Ride Request').toString();
      final body = (data['body'] ?? 'Tap to view and accept the ride').toString();
      await showRideAlarm(_local, title, body, data);
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] showRideAlarmFromApp failed: $e');
    }
  }

  Future<void> cancelRideAlert() async {
    try {
      await _local.cancel(_rideAlertNotificationId);
    } catch (_) {}
  }

  /// Show a local notification for an incoming chat message.
  Future<void> showChatNotification(String title, String body, {Map<String, dynamic>? data}) async {
    try {
      final payloadData = data ?? {'event': 'chat_message', 'title': title, 'body': body};
      await _local.show(
        DateTime.now().millisecondsSinceEpoch.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _generalAlertChannelId,
            _generalAlertChannelName,
            channelDescription: _generalAlertChannelDesc,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(payloadData),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[fcm] failed to show chat notification: $e');
    }
  }

  Future<void> dispose() async {
    await _foregroundSub?.cancel();
    await _tokenSub?.cancel();
    await _clickController.close();
  }
}
