import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../network/api_client.dart';
import 'fcm_service.dart';

/// CallKit bridge — the iOS half of the incoming-ride alert.
///
/// Android draws its own full-screen-intent notification from
/// `firebaseMessagingBackgroundHandler`. iOS has no equivalent, so the backend
/// sends a PushKit VoIP push instead, the native `AppDelegate` reports it to
/// CallKit, and this class turns the driver's Accept/Decline on that call
/// screen into the same API calls the in-app buttons make.
///
/// No-ops on Android.
class CallService {
  CallService._();
  static final CallService instance = CallService._();

  StreamSubscription<CallEvent?>? _sub;
  bool _started = false;
  String? _uploadedToken;

  Future<void> init() async {
    if (_started || !Platform.isIOS) return;
    _started = true;

    _sub = FlutterCallkitIncoming.onEvent.listen(_onEvent, onError: (e) {
      if (kDebugMode) debugPrint('[callkit] event stream error: $e');
    });

    unawaited(registerToken());
  }

  /// PUT the PushKit token to the backend. The token isn't available the
  /// instant the app launches, so poll briefly rather than giving up.
  /// Safe to call again on resume and after login — it skips a repeat upload.
  Future<void> registerToken() async {
    if (!Platform.isIOS) return;
    for (var attempt = 0; attempt < 10; attempt++) {
      String? token;
      try {
        token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      } catch (e) {
        if (kDebugMode) debugPrint('[callkit] getDevicePushTokenVoIP failed: $e');
      }
      if (token != null && token.isNotEmpty) {
        if (token == _uploadedToken) return;
        try {
          await ApiClient.instance.dio.put('/auth/voip-token', data: {'token': token});
          _uploadedToken = token;
          if (kDebugMode) debugPrint('[callkit] voip token registered');
        } catch (e) {
          if (kDebugMode) debugPrint('[callkit] voip token upload failed: $e');
        }
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    if (kDebugMode) debugPrint('[callkit] no voip token after 10s');
  }

  /// Clear the token server-side so a signed-out device stops ringing.
  Future<void> clearToken() async {
    if (!Platform.isIOS) return;
    _uploadedToken = null;
    try {
      await ApiClient.instance.dio.put('/auth/voip-token', data: {'token': null});
    } catch (_) {}
  }

  /// Food and market dispatches ride on the same `new_ride_request` event as
  /// hails, but are accepted on different endpoints — mirror DriverProvider.
  String? _actionPath(Map<String, dynamic>? extra, String action) {
    if (extra == null) return null;
    if (extra['is_food'] == true || extra['is_food'] == 'true') {
      final id = extra['food_order_id'];
      return id == null ? null : '/food/orders/$id/$action';
    }
    if (extra['is_market'] == true || extra['is_market'] == 'true') {
      final id = extra['market_order_id'];
      return id == null ? null : '/market/orders/$id/$action';
    }
    final id = int.tryParse('${extra['booking_id'] ?? ''}');
    return id == null ? null : '/bookings/$id/$action';
  }

  Future<void> _onEvent(CallEvent? event) async {
    if (event == null) return;

    // CallEvent is a sealed hierarchy — each action is its own type.
    if (event is CallEventActionCallAccept) {
      final extra = event.callKitParams.extra;
      final path = _actionPath(extra, 'accept');
      if (path == null) return;
      // Queue a plain ride on the same slot the notification-shade Accept
      // uses, so the claim still happens if this call fails while the app is
      // waking. Then try immediately — the booking's status guards the server
      // side, so a duplicate is rejected rather than double-applied.
      final bookingId = int.tryParse('${extra?['booking_id'] ?? ''}');
      if (bookingId != null && path.startsWith('/bookings/')) {
        FcmService.instance.queueAcceptBookingId(bookingId);
      }
      try {
        await ApiClient.instance.dio.post(path);
        FcmService.instance.consumePendingAcceptBookingId();
      } catch (e) {
        if (kDebugMode) debugPrint('[callkit] immediate accept failed, queued: $e');
      }
      return;
    }

    if (event is CallEventActionCallDecline) {
      final path = _actionPath(event.callKitParams.extra, 'decline');
      if (path == null) return;
      try {
        // Tell the backend so it forwards to the next driver instead of
        // letting the request sit until the search times out.
        await ApiClient.instance.dio.post(path);
      } catch (e) {
        if (kDebugMode) debugPrint('[callkit] decline failed: $e');
      }
      return;
    }

    // actionCallTimeout and the rest need no server call — the backend's own
    // 30 s window already forwards an unanswered request.
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }
}
