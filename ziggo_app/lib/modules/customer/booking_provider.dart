import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_client.dart';
import '../../core/network/ws_client.dart';
import '../../core/notifications/fcm_service.dart';

/// Drives the full ride lifecycle: estimate → create → track → rate.
class BookingProvider extends ChangeNotifier with WidgetsBindingObserver {
  final WsClient _ws = WsClient();
  WsClient get ws => _ws;

  final _adminUpdateController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get adminUpdates => _adminUpdateController.stream;

  StreamSubscription? _wsSub;
  StreamSubscription? _fcmSub;

  // Backend cancels a stale search at 120 s (swept every 30 s, so up to ~150 s).
  // The client only steps in if that clearly didn't happen.
  static const int _searchFailsafeSeconds = 180;

  Map<String, dynamic>? _activeBooking;
  Map<String, dynamic>? get activeBooking => _activeBooking;

  Map<String, dynamic>? _pendingRatingBooking;
  Map<String, dynamic>? get pendingRatingBooking => _pendingRatingBooking;

  String? _lastError;
  String? get lastError => _lastError;

  // A lady-driver ride with no lady driver free stays open, so the customer can
  // switch it to any driver. The event can arrive before the booking response,
  // so it is kept by booking id.
  int? _noLadyDriverBookingId;
  String? _noLadyDriverMessage;
  String? get noLadyDriverMessage {
    final b = _activeBooking;
    if (b == null || b['id'] != _noLadyDriverBookingId) return null;
    if (b['status'] != 'searching' || b['lady_driver_requested'] != true) return null;
    return _noLadyDriverMessage;
  }

  bool _busy = false;
  bool get busy => _busy;

  void _setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }

  Future<void> connectRealtime(String token) async {
    // connect() first: it sets isConnected synchronously, which is what callers
    // gate on. Both streams below are broadcast and outlive the connection, so
    // a second call would stack a duplicate handler on top of the first.
    _ws.connect(token);
    await _wsSub?.cancel();
    await _fcmSub?.cancel();
    _wsSub = _ws.events.listen((msg) {
      final event = msg['event'];
      final data = msg['data'] as Map<String, dynamic>?;
      if (data == null) return;
      if (event == 'booking_update') {
        final bid = data['booking_id'];
        final newStatus = data['status'];
        if (_activeBooking != null && _activeBooking!['id'] == bid) {
          if (newStatus == 'cancelled') {
            _activeBooking = null;
          } else {
            _activeBooking = {
              ..._activeBooking!,
              'status': newStatus,
              if (data['otp'] != null) 'otp': data['otp'],
              if (data.containsKey('is_driver_completing_prior_trip'))
                'is_driver_completing_prior_trip': data['is_driver_completing_prior_trip'],
            };
          }
          notifyListeners();
        }
        // Lazy refresh
        if (newStatus != 'cancelled' && newStatus != 'completed') {
          loadActive();
        }
      } else if (event == 'stop_arrived' || event == 'stop_departed') {
        loadActive();
      } else if (event == 'no_drivers_available') {
        final bid = data['booking_id'];
        if (data['lady_driver'] == true && bid != null) {
          _noLadyDriverBookingId = bid as int?;
          _noLadyDriverMessage = data['message']?.toString() ?? 'No lady driver is available nearby right now.';
          notifyListeners();
        } else if (_activeBooking != null && (bid == null || _activeBooking!['id'] == bid)) {
          _activeBooking = null;
          notifyListeners();
        }
      } else if (event == 'driver_location_update') {
        final bid = data['booking_id'];
        if (_activeBooking != null && _activeBooking!['id'] == bid && _activeBooking!['driver'] != null) {
          final driverData = Map<String, dynamic>.from(_activeBooking!['driver']);
          driverData['current_lat'] = data['lat'];
          driverData['current_lng'] = data['lng'];
          driverData['current_heading'] = data['heading'];
          _activeBooking = {..._activeBooking!, 'driver': driverData};
          notifyListeners();
        }
      } else if (event == 'admin_config_update') {
        _adminUpdateController.add(data ?? {});
      }
    });

    // Fallback: If WebSocket drops a message, FCM push notifications act as a secondary trigger
    _fcmSub = FcmService.instance.onForegroundEvent.listen((data) {
      if (data['event'] == 'booking_update') {
        final s = data['status']?.toString();
        // Skip loadActive() for terminal statuses — the WS handler already
        // updated _activeBooking inline. Calling loadActive() here could
        // race with the API and restore a stale completed booking.
        if (s != 'cancelled' && s != 'completed') {
          loadActive();
        } else if (s == 'cancelled') {
          _activeBooking = null;
          notifyListeners();
        }
      }
    });
  }

  Future<Map<String, dynamic>?> estimateFare({
    required String serviceType,
    required LatLng pickup,
    required LatLng drop,
    String? promoCode,
    String tripType = 'one_way',
    bool isFlash = false,
    double? parcelWeightKg,
    bool isRental = false,
    int? rentalHours,
    bool isCourier = false,
    // BRD: RW-02 — preview redemption
    int redeemPoints = 0,
    // BRD: CD-19 — intermediate stops, each {lat,lng,address}
    List<Map<String, dynamic>> stops = const [],
    List<Map<String, dynamic>> packages = const [],
  }) async {
    try {
      double? finalWeight = parcelWeightKg;
      if (finalWeight == null && packages.isNotEmpty) {
        double totalWeight = 0;
        for (var p in packages) {
          totalWeight += (p['weight_kg'] as num?)?.toDouble() ?? 0;
        }
        if (totalWeight > 0) finalWeight = totalWeight;
      }

      final resp = await ApiClient.instance.dio.post(
        '/bookings/estimate',
        data: {
          'service_type': serviceType,
          'pickup_lat': pickup.latitude,
          'pickup_lng': pickup.longitude,
          'drop_lat': drop.latitude,
          'drop_lng': drop.longitude,
          'trip_type': tripType,
          if (isFlash) 'is_flash': true,
          if (isCourier) 'is_courier': true,
          if (finalWeight != null) 'parcel_weight_kg': finalWeight,
          if (isRental) 'is_rental': true,
          if (rentalHours != null) 'rental_hours': rentalHours,
          if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
          if (redeemPoints > 0) 'redeem_points': redeemPoints,
          if (stops.isNotEmpty) 'stops': stops,
          if (packages.isNotEmpty) 'packages': packages,
        },
      );
      if (resp.data is! Map) return null;
      return Map<String, dynamic>.from(resp.data as Map);
    } on DioException catch (e) {
      final detail = e.response?.data;
      if (detail is Map && detail['detail'] != null) {
        _lastError = detail['detail'].toString();
      } else {
        _lastError = e.message ?? 'Network error';
      }
      if (kDebugMode) debugPrint('estimateFare error: $_lastError');
      notifyListeners();
      return null;
    } catch (e, st) {
      _lastError = 'Unexpected error: $e';
      if (kDebugMode) debugPrint('estimateFare error: $e\n$st');
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> estimateFaresBulk({
    required List<String> serviceTypes,
    required LatLng pickup,
    required LatLng drop,
    String? promoCode,
    String tripType = 'one_way',
    bool isFlash = false,
    double? parcelWeightKg,
    bool isRental = false,
    int? rentalHours,
    bool isCourier = false,
    int redeemPoints = 0,
    List<Map<String, dynamic>> stops = const [],
    List<Map<String, dynamic>> packages = const [],
    bool ladyDriver = false,
  }) async {
    try {
      final resp = await ApiClient.instance.dio.post(
        '/bookings/estimate/bulk',
        data: {
          'service_types': serviceTypes,
          'pickup_lat': pickup.latitude,
          'pickup_lng': pickup.longitude,
          'drop_lat': drop.latitude,
          'drop_lng': drop.longitude,
          'trip_type': tripType,
          if (isFlash) 'is_flash': true,
          if (isCourier) 'is_courier': true,
          if (parcelWeightKg != null) 'parcel_weight_kg': parcelWeightKg,
          if (isRental) 'is_rental': true,
          if (rentalHours != null) 'rental_hours': rentalHours,
          if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
          if (redeemPoints > 0) 'redeem_points': redeemPoints,
          if (stops.isNotEmpty) 'stops': stops,
          if (packages.isNotEmpty) 'packages': packages,
          if (ladyDriver) 'lady_driver': true,
        },
      );
      if (resp.data is! Map) return null;
      return Map<String, dynamic>.from(resp.data as Map);
    } on DioException catch (e) {
      final detail = e.response?.data;
      if (detail is Map && detail['detail'] != null) {
        _lastError = detail['detail'].toString();
      } else {
        _lastError = e.message ?? 'Network error';
      }
      if (kDebugMode) debugPrint('estimateFaresBulk error: $_lastError');
      notifyListeners();
      return null;
    } catch (e, st) {
      _lastError = 'Unexpected error: $e';
      if (kDebugMode) debugPrint('estimateFaresBulk error: $e\n$st');
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> createBooking({
    required String serviceType,
    required LatLng pickup,
    required String pickupAddress,
    required LatLng drop,
    required String dropAddress,
    String paymentMethod = 'cash',
    String? promoCode,
    String tripType = 'one_way',
    String? friendName,
    String? friendPhone,
    // Flash parcel fields — only set for parcel deliveries
    bool isFlash = false,
    String? parcelType,
    double? parcelWeightKg,
    String? receiverName,
    String? receiverPhone,
    String? parcelInstructions,
    // Courier parcel fields — island-wide weight-priced delivery
    bool isCourier = false,
    // Rental fields — only set when the booking is a vehicle-hire
    bool isRental = false,
    int? rentalHours,
    // BRD: RW-02 — redeem points at checkout
    int redeemPoints = 0,
    // BRD: CD-19 — intermediate stops
    List<Map<String, dynamic>> stops = const [],
    List<Map<String, dynamic>> packages = const [],
    DateTime? scheduledTime,
    // Phase 2: female customers, rides only
    bool ladyDriver = false,
    bool includeBikes = false,
  }) async {
    _setBusy(true);
    _lastError = null;
    try {
      double? finalWeight = parcelWeightKg;
      if (finalWeight == null && packages.isNotEmpty) {
        double totalWeight = 0;
        for (var p in packages) {
          totalWeight += (p['weight_kg'] as num?)?.toDouble() ?? 0;
        }
        if (totalWeight > 0) finalWeight = totalWeight;
      }

      final resp = await ApiClient.instance.dio.post(
        '/bookings',
        data: {
          'service_type': serviceType,
          'pickup_lat': pickup.latitude,
          'pickup_lng': pickup.longitude,
          'pickup_address': pickupAddress,
          'drop_lat': drop.latitude,
          'drop_lng': drop.longitude,
          'drop_address': dropAddress,
          'payment_method': paymentMethod,
          'trip_type': tripType,
          if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
          if (friendName != null && friendName.isNotEmpty) 'friend_name': friendName,
          if (friendPhone != null && friendPhone.isNotEmpty) 'friend_phone': friendPhone,
          if (receiverName != null && receiverName.isNotEmpty) 'receiver_name': receiverName,
          if (receiverPhone != null && receiverPhone.isNotEmpty) 'receiver_phone': receiverPhone,
          if (parcelInstructions != null && parcelInstructions.isNotEmpty)
            'parcel_instructions': parcelInstructions,
          if (redeemPoints > 0) 'redeem_points': redeemPoints,
          if (stops.isNotEmpty) 'stops': stops,
          if (scheduledTime != null) 'scheduled_time': scheduledTime.toIso8601String(),
          if (ladyDriver) 'lady_driver': true,
          if (includeBikes) 'include_bikes': true,
          if (isFlash || isCourier) ...{
            if (isFlash) 'is_flash': true,
            if (isCourier) 'is_courier': true,
            if (parcelType != null) 'parcel_type': parcelType,
            if (finalWeight != null) 'parcel_weight_kg': finalWeight,
            if (packages.isNotEmpty) 'packages': packages,
          },
          if (isRental) ...{
            'is_rental': true,
            if (rentalHours != null) 'rental_hours': rentalHours,
          },
        },
      );
      if (resp.data is! Map) {
        _lastError = 'Unexpected response from server (${resp.data.runtimeType})';
        notifyListeners();
        return null;
      }
      _activeBooking = Map<String, dynamic>.from(resp.data as Map);
      notifyListeners();
      return _activeBooking;
    } on DioException catch (e) {
      final detail = e.response?.data;
      if (detail is Map && detail['detail'] != null) {
        _lastError = detail['detail'].toString();
      } else if (detail is String && detail.isNotEmpty) {
        _lastError = detail;
      } else {
        _lastError = e.message ?? 'Network error';
      }
      if (kDebugMode) debugPrint('createBooking DioException: $_lastError');
      notifyListeners();
      return null;
    } catch (e, st) {
      _lastError = 'Unexpected error: $e';
      if (kDebugMode) debugPrint('createBooking error: $e\n$st');
      notifyListeners();
      return null;
    } finally {
      _setBusy(false);
    }
  }

  /// No lady driver took the ride: offer it to every nearby driver instead.
  Future<bool> switchToAnyDriver() async {
    final id = _activeBooking?['id'];
    if (id == null) return false;
    _setBusy(true);
    try {
      final resp = await ApiClient.instance.dio.post('/bookings/$id/any-driver');
      _activeBooking = Map<String, dynamic>.from(resp.data as Map);
      _noLadyDriverMessage = null;
      _noLadyDriverBookingId = null;
      return true;
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message ?? 'Network error';
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> loadActive() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings/active');
      if (resp.data == null || (resp.data is String && resp.data == '')) {
        _activeBooking = null;
      } else {
        final data = Map<String, dynamic>.from(resp.data);
        final status = data['status']?.toString();
        if (status == 'cancelled' || status == 'completed') {
          _activeBooking = null;
        } else if (status == 'searching') {
          // Failsafe only. The backend owns the search timeout (120 s) and will
          // cancel + push the update itself; this fires well after that so we
          // never kill a search the server is still dispatching.
          //
          // Scheduled rides are exempt: their booked_at is when the customer
          // scheduled the trip, possibly days before dispatch even starts, so
          // it says nothing about how long we've been searching.
          final bookedAtStr = data['booked_at']?.toString();
          final isScheduled = data['scheduled_at'] != null &&
              data['scheduled_at'].toString().isNotEmpty;
          bool isExpired = false;
          if (!isScheduled && bookedAtStr != null && bookedAtStr.isNotEmpty) {
            try {
              final bookedAt = DateTime.parse(bookedAtStr);
              final now = DateTime.now().toUtc();
              final diff = now.difference(bookedAt.toUtc()).inSeconds;
              if (diff > _searchFailsafeSeconds) {
                isExpired = true;
              }
            } catch (_) {}
          }
          if (isExpired) {
            final bid = data['id'] as int?;
            if (bid != null) {
              unawaited(cancelActiveSilently(bookingId: bid, reason: 'Search expired'));
            }
            _activeBooking = null;
          } else {
            _activeBooking = data;
          }
        } else {
          _activeBooking = data;
        }
      }
      notifyListeners();
      unawaited(_resumeSharingIfOn());
    } catch (_) {}

    // Do not check pending rating automatically on loadActive to prevent unwanted popups on startup
  }

  Future<Map<String, dynamic>?> updateStatus(int bookingId, String status, {String? reason}) async {
    try {
      final resp = await ApiClient.instance.dio.patch(
        '/bookings/$bookingId/status',
        data: {'status': status, if (reason != null) 'reason': reason},
      );
      if (status == 'cancelled' || status == 'completed') {
        _activeBooking = null;
      } else {
        _activeBooking = Map<String, dynamic>.from(resp.data);
      }
      notifyListeners();
      return _activeBooking;
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
      return null;
    }
  }

  Future<void> cancelActive({String reason = 'Cancelled by user'}) async {
    if (_activeBooking == null) return;
    await updateStatus(_activeBooking!['id'] as int, 'cancelled', reason: reason);
    _activeBooking = null;
    notifyListeners();
  }

  void clearActiveBookingLocally() {
    _activeBooking = null;
    notifyListeners();
  }

  Future<void> cancelActiveSilently({required int bookingId, String reason = 'Cancelled by user'}) async {
    try {
      await ApiClient.instance.dio.patch(
        '/bookings/$bookingId/status',
        data: {'status': 'cancelled', 'reason': reason},
      );
    } catch (_) {}
  }

  /// One booking by id, for screens handed only an id (the rating screen needs
  /// the driver block to show who it is rating).
  Future<Map<String, dynamic>?> fetchBooking(int bookingId) async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings/$bookingId');
      if (resp.data is Map) {
        return Map<String, dynamic>.from(resp.data as Map);
      }
      return null;
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
      return null;
    }
  }

  Future<Map<String, dynamic>?> checkPendingRating() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings/pending-rating');
      if (resp.data == null || (resp.data is String && resp.data == '')) {
        _pendingRatingBooking = null;
        notifyListeners();
        return null;
      }
      final data = Map<String, dynamic>.from(resp.data as Map);
      final bookingId = data['id'] as int?;
      if (bookingId == null) {
        _pendingRatingBooking = null;
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final dismissedId = prefs.getInt('dismissed_rating_booking_id');
      final dismissedList = prefs.getStringList('dismissed_rating_booking_ids') ?? [];
      if (dismissedId == bookingId || dismissedList.contains(bookingId.toString())) {
        _pendingRatingBooking = null;
        return null;
      }

      _pendingRatingBooking = data;
      notifyListeners();
      return _pendingRatingBooking;
    } catch (_) {
      return null;
    }
  }

  /// Records that the customer declined to rate this booking. The id is
  /// persisted, so ✕ / "Skip" is honoured on the next launch too — the API
  /// still reports the booking as unrated, and without this the full-screen
  /// prompt re-opens on every app open. rate() drops the key once a rating
  /// lands, and the backend stops offering the booking after 48 h anyway.
  Future<void> dismissRating(int bookingId) async {
    if (_pendingRatingBooking != null && _pendingRatingBooking!['id'] == bookingId) {
      _pendingRatingBooking = null;
    }
    _activeBooking = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('dismissed_rating_booking_id', bookingId);
      final dismissedList = prefs.getStringList('dismissed_rating_booking_ids') ?? [];
      if (!dismissedList.contains(bookingId.toString())) {
        dismissedList.add(bookingId.toString());
        await prefs.setStringList('dismissed_rating_booking_ids', dismissedList);
      }
    } catch (_) {}
  }

  /// Drops every trace of the signed-in customer. Providers outlive logout, so
  /// without this the next account to sign in on the same app run inherits the
  /// previous one's active ride and rating prompt.
  Future<void> resetSession() async {
    await _wsSub?.cancel();
    await _fcmSub?.cancel();
    _wsSub = null;
    _fcmSub = null;
    await _ws.disconnect();
    _endSharing();
    _shareStoppedBookingIds.clear();
    _activeBooking = null;
    _pendingRatingBooking = null;
    _lastError = null;
    _busy = false;
    notifyListeners();
  }

  Future<bool> rate({required int bookingId, required int rating, String? feedback}) async {
    try {
      await ApiClient.instance.dio.post(
        '/bookings/$bookingId/rate',
        data: {'rating': rating, if (feedback != null) 'feedback': feedback},
      );
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('dismissed_rating_booking_id');
        final dismissedList = prefs.getStringList('dismissed_rating_booking_ids') ?? [];
        if (dismissedList.contains(bookingId.toString())) {
          dismissedList.remove(bookingId.toString());
          await prefs.setStringList('dismissed_rating_booking_ids', dismissedList);
        }
      } catch (_) {}
      _pendingRatingBooking = null;
      _activeBooking = null;
      _lastError = null;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      final detail = e.response?.data;
      if (detail is Map && detail['detail'] != null) {
        _lastError = detail['detail'].toString();
      } else if (detail is String && detail.isNotEmpty) {
        _lastError = detail;
      } else {
        _lastError = e.message ?? 'Network error';
      }
      if (kDebugMode) debugPrint('rate DioException: $_lastError');
      notifyListeners();
      return false;
    } catch (e, st) {
      _lastError = 'Unexpected error: $e';
      if (kDebugMode) debugPrint('rate error: $e\n$st');
      notifyListeners();
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchFlashTiers() async {
    try {
      final resp = await ApiClient.instance.dio.get('/flash/pricing');
      return List<Map<String, dynamic>>.from(resp.data as List);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchCourierTiers() async {
    try {
      final resp = await ApiClient.instance.dio.get('/courier/pricing');
      return List<Map<String, dynamic>>.from(resp.data as List);
    } catch (_) {
      return const [];
    }
  }

  Future<List<Map<String, dynamic>>> fetchHistory() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings');
      return List<Map<String, dynamic>>.from(resp.data as List);
    } catch (_) {
      return [];
    }
  }

  // ---- BRD: CD-17 — SOS panic button ----------------------------------
  Future<bool> triggerSos(int bookingId, {double? lat, double? lng, String? note}) async {
    try {
      await ApiClient.instance.dio.post(
        '/bookings/$bookingId/sos',
        data: {
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          if (note != null && note.isNotEmpty) 'note': note,
        },
      );
      return true;
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return false;
    }
  }

  // ---- BRD: CD-17 + CD-31 — trip-share link --------------------------
  Future<Map<String, dynamic>?> getShareLink(int bookingId) async {
    try {
      final r = await ApiClient.instance.dio.post('/bookings/$bookingId/share');
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return null;
    }
  }

  // ---- BRD: Change Destination ---------------------------------------
  Future<bool> updateDestination(int bookingId, LatLng drop, String address, {List<Map<String, dynamic>> stops = const []}) async {
    _setBusy(true);
    _lastError = null;
    try {
      final resp = await ApiClient.instance.dio.patch(
        '/bookings/$bookingId/destination',
        data: {
          'drop_lat': drop.latitude,
          'drop_lng': drop.longitude,
          'drop_address': address,
          if (stops.isNotEmpty) 'stops': stops,
        },
      );
      _activeBooking = Map<String, dynamic>.from(resp.data as Map);
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
      if (kDebugMode) debugPrint('updateDestination DioException: $_lastError');
      notifyListeners();
      return false;
    } catch (e, st) {
      _lastError = 'Unexpected error: $e';
      if (kDebugMode) debugPrint('updateDestination error: $e\n$st');
      notifyListeners();
      return false;
    } finally {
      _setBusy(false);
    }
  }

  // ---- BRD: CD-19 — driver-side stop transitions -----------------------
  Future<Map<String, dynamic>?> arriveAtStop(int bookingId, int orderIndex) async {
    try {
      final r = await ApiClient.instance.dio.post(
        '/bookings/$bookingId/stops/$orderIndex/arrive',
      );
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> departFromStop(int bookingId, int orderIndex) async {
    try {
      final r = await ApiClient.instance.dio.post(
        '/bookings/$bookingId/stops/$orderIndex/depart',
      );
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return null;
    }
  }

  // ---- Phase 2 feature 01 — share my live location with the driver ----
  // Per booking and off until the customer turns it on. Points are sent only
  // while the driver is on the way and the app is in the foreground; there is
  // no background location. The backend keeps just the latest point and wipes
  // it when the trip starts or ends.
  static const _shareStatuses = {'accepted', 'arrived'};
  static const _shareTick = Duration(seconds: 5);
  static const _shareGapNearDriver = Duration(seconds: 15);
  // Re-sent even when standing still, so the driver's map (which hides a point
  // after 60 s) keeps showing the customer.
  static const _shareHeartbeat = Duration(seconds: 20);
  static const double _shareMinMoveMetres = 10;
  static const double _nearDriverMetres = 20;
  static const shareLocationOff = "Turn on your phone's location to share it with your driver.";
  static const shareNoPermission = 'Allow Ziggo to use your location to share it with your driver.';

  int? _sharingBookingId;
  // Bookings the customer switched off here; a poll that raced the switch-off
  // must not turn sharing back on.
  final Set<int> _shareStoppedBookingIds = {};
  bool _shareToggling = false;
  Future<bool?>? _shareInFlight;
  bool _observingLifecycle = false;
  StreamSubscription<Position>? _sharePositionSub;
  Timer? _shareTimer;
  Position? _sharePosition;
  Position? _shareSentPosition;
  DateTime? _shareSentAt;

  /// Rides (not parcels) whose driver is on the way to the pickup.
  bool get canShareLocation {
    final b = _activeBooking;
    return b != null &&
        b['is_flash'] != true &&
        b['is_courier'] != true &&
        _shareStatuses.contains(b['status']);
  }

  bool get sharingLocation =>
      _sharingBookingId != null && _sharingBookingId == _activeBooking?['id'] && canShareLocation;

  bool get shareToggling => _shareToggling;

  /// Turns sharing on for the active ride. Returns null on success, else a
  /// message for the customer.
  Future<String?> startSharingLocation() async {
    final b = _activeBooking;
    if (b == null || !canShareLocation || sharingLocation || _shareToggling) return null;
    final id = b['id'] as int;
    _shareToggling = true;
    notifyListeners();
    try {
      final problem = await _locationProblem(ask: true);
      if (problem != null) return problem;
      final p = await _freshPosition();
      if (p == null) return 'Could not find your location. Please try again.';
      final ok = await _postSharePoint(id, p);
      if (ok == null) return 'Could not share your location. Check your connection.';
      if (ok == false) return _lastError ?? 'Live location sharing is not available for this ride.';
      _shareStoppedBookingIds.remove(id);
      _sharePosition = p;
      _shareSentPosition = p;
      _shareSentAt = DateTime.now();
      _runSharing(id);
      return null;
    } finally {
      _shareToggling = false;
      notifyListeners();
    }
  }

  Future<void> stopSharingLocation() async {
    final id = _sharingBookingId ?? _activeBooking?['id'] as int?;
    final inFlight = _shareInFlight;
    _endSharing();
    if (id != null) _shareStoppedBookingIds.add(id);
    notifyListeners();
    if (id == null) return;
    // A point already on its way must land before the stop, not after it.
    if (inFlight != null) await inFlight;
    try {
      await ApiClient.instance.dio.delete('/bookings/$id/passenger-location');
    } catch (_) {}
  }

  // The app was closed or restarted with sharing on for this ride: carry on,
  // but never ask for permission without a tap.
  Future<void> _resumeSharingIfOn() async {
    final b = _activeBooking;
    if (b == null || b['passenger_sharing'] != true || _sharingBookingId != null || _shareToggling) return;
    final id = b['id'] as int;
    if (!canShareLocation || _shareStoppedBookingIds.contains(id)) return;
    _shareToggling = true;
    final problem = await _locationProblem(ask: false);
    _shareToggling = false;
    if (_activeBooking?['id'] != id || !canShareLocation) return;
    if (problem == null) {
      _runSharing(id);
      notifyListeners();
    } else {
      await stopSharingLocation();
    }
  }

  Future<String?> _locationProblem({required bool ask}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return shareLocationOff;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && ask) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) return shareNoPermission;
      return null;
    } catch (_) {
      return 'Could not check location access on this phone.';
    }
  }

  Future<Position?> _freshPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {}
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 2) return last;
    } catch (_) {}
    return null;
  }

  /// true = sent, false = the server won't take points for this ride any
  /// more (trip started, cancelled, …), null = network trouble, try again.
  Future<bool?> _postSharePoint(int bookingId, Position p) async {
    try {
      await ApiClient.instance.dio.post(
        '/bookings/$bookingId/passenger-location',
        data: {'lat': p.latitude, 'lng': p.longitude},
      );
      return true;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == null || code >= 500 || code == 429) return null;
      final detail = e.response?.data;
      _lastError = detail is Map ? detail['detail']?.toString() : null;
      return false;
    } catch (_) {
      return null;
    }
  }

  void _runSharing(int bookingId) {
    _sharingBookingId = bookingId;
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || _isForeground(state)) _listenForShare();
  }

  static bool _isForeground(AppLifecycleState s) =>
      s == AppLifecycleState.resumed || s == AppLifecycleState.inactive;

  void _listenForShare() {
    _sharePositionSub ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((p) => _sharePosition = p, onError: (_) {});
    _shareTimer ??= Timer.periodic(_shareTick, (_) => _sendShareIfDue());
  }

  void _pauseShare() {
    _sharePositionSub?.cancel();
    _sharePositionSub = null;
    _shareTimer?.cancel();
    _shareTimer = null;
    // Never send a pre-background fix as live after coming back.
    _sharePosition = null;
  }

  void _endSharing() {
    _sharingBookingId = null;
    _pauseShare();
    _shareSentPosition = null;
    _shareSentAt = null;
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_sharingBookingId == null) return;
    if (_isForeground(state)) {
      _listenForShare();
    } else {
      _pauseShare();
    }
  }

  Future<void> _sendShareIfDue() async {
    final id = _sharingBookingId;
    if (id == null) return;
    if (!sharingLocation) {
      // The ride ended, was cancelled or the trip started; the backend has
      // already wiped the point.
      _endSharing();
      notifyListeners();
      return;
    }
    final p = _sharePosition;
    if (p == null || _shareInFlight != null) return;
    final now = DateTime.now();
    final last = _shareSentAt;
    final sent = _shareSentPosition;
    bool due;
    if (last == null || sent == null || now.difference(last) >= _shareHeartbeat) {
      due = true;
    } else {
      final moved = Geolocator.distanceBetween(sent.latitude, sent.longitude, p.latitude, p.longitude);
      final gap = _driverIsNear(p) ? _shareGapNearDriver : _shareTick;
      due = moved >= _shareMinMoveMetres && now.difference(last) >= gap;
    }
    if (!due) return;
    final ok = await (_shareInFlight = _postSharePoint(id, p));
    _shareInFlight = null;
    if (_sharingBookingId != id) return;
    if (ok == true) {
      _shareSentAt = now;
      _shareSentPosition = p;
    } else if (ok == false) {
      _endSharing();
      notifyListeners();
    }
  }

  bool _driverIsNear(Position p) {
    final d = _activeBooking?['driver'];
    if (d is! Map) return false;
    final lat = d['current_lat'] as num?;
    final lng = d['current_lng'] as num?;
    if (lat == null || lng == null) return false;
    return Geolocator.distanceBetween(p.latitude, p.longitude, lat.toDouble(), lng.toDouble()) <= _nearDriverMetres;
  }

  @override
  void dispose() {
    _endSharing();
    _wsSub?.cancel();
    _fcmSub?.cancel();
    _ws.dispose();
    _adminUpdateController.close();
    super.dispose();
  }
}
