import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../core/network/api_client.dart';
import '../../core/network/ws_client.dart';

/// Drives the full ride lifecycle: estimate → create → track → rate.
class BookingProvider extends ChangeNotifier {
  final WsClient _ws = WsClient();
  WsClient get ws => _ws;

  Map<String, dynamic>? _activeBooking;
  Map<String, dynamic>? get activeBooking => _activeBooking;

  String? _lastError;
  String? get lastError => _lastError;

  bool _busy = false;
  bool get busy => _busy;

  void _setBusy(bool v) {
    _busy = v;
    notifyListeners();
  }

  Future<void> connectRealtime(String token) async {
    _ws.connect(token);
    _ws.events.listen((msg) {
      final event = msg['event'];
      final data = msg['data'] as Map<String, dynamic>?;
      if (data == null) return;
      if (event == 'booking_update') {
        final bid = data['booking_id'];
        if (_activeBooking != null && _activeBooking!['id'] == bid) {
          _activeBooking = {..._activeBooking!, 'status': data['status']};
          notifyListeners();
        }
        // Lazy refresh
        loadActive();
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
    // BRD: RW-02 — preview redemption
    int redeemPoints = 0,
    // BRD: CD-19 — intermediate stops, each {lat,lng,address}
    List<Map<String, dynamic>> stops = const [],
  }) async {
    try {
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
          if (parcelWeightKg != null) 'parcel_weight_kg': parcelWeightKg,
          if (isRental) 'is_rental': true,
          if (rentalHours != null) 'rental_hours': rentalHours,
          if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
          if (redeemPoints > 0) 'redeem_points': redeemPoints,
          if (stops.isNotEmpty) 'stops': stops,
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

  Future<Map<String, dynamic>?> createBooking({
    required String serviceType,
    required LatLng pickup,
    required String pickupAddress,
    required LatLng drop,
    required String dropAddress,
    String paymentMethod = 'cash',
    String? promoCode,
    String tripType = 'one_way',
    // Flash parcel fields — only set for parcel deliveries
    bool isFlash = false,
    String? parcelType,
    double? parcelWeightKg,
    String? receiverName,
    String? receiverPhone,
    String? parcelInstructions,
    // Rental fields — only set when the booking is a vehicle-hire
    bool isRental = false,
    int? rentalHours,
    // BRD: RW-02 — redeem points at checkout
    int redeemPoints = 0,
    // BRD: CD-19 — intermediate stops
    List<Map<String, dynamic>> stops = const [],
    // BRD: PR-03 — basic courier (longer-distance parcel, not Flash)
    bool isCourier = false,
    // BRD: PR-05 — receive items / inverse Flash: customer is receiver,
    // driver collects FROM sender_* at pickup address.
    bool isPickupRequest = false,
    String? senderName,
    String? senderPhone,
  }) async {
    _setBusy(true);
    _lastError = null;
    try {
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
          if (redeemPoints > 0) 'redeem_points': redeemPoints,
          if (stops.isNotEmpty) 'stops': stops,
          if (isFlash) ...{
            'is_flash': true,
            if (parcelType != null) 'parcel_type': parcelType,
            if (parcelWeightKg != null) 'parcel_weight_kg': parcelWeightKg,
            if (receiverName != null && receiverName.isNotEmpty) 'receiver_name': receiverName,
            if (receiverPhone != null && receiverPhone.isNotEmpty) 'receiver_phone': receiverPhone,
            if (parcelInstructions != null && parcelInstructions.isNotEmpty)
              'parcel_instructions': parcelInstructions,
          },
          // BRD: PR-03 — Basic Courier (long-distance parcel)
          if (isCourier) ...{
            'is_courier': true,
            if (parcelType != null) 'parcel_type': parcelType,
            if (parcelWeightKg != null) 'parcel_weight_kg': parcelWeightKg,
            if (receiverName != null && receiverName.isNotEmpty) 'receiver_name': receiverName,
            if (receiverPhone != null && receiverPhone.isNotEmpty) 'receiver_phone': receiverPhone,
            if (parcelInstructions != null && parcelInstructions.isNotEmpty)
              'parcel_instructions': parcelInstructions,
          },
          // BRD: PR-05 — Receive items / inverse Flash
          if (isPickupRequest) ...{
            'is_pickup_request': true,
            if (parcelType != null) 'parcel_type': parcelType,
            if (parcelWeightKg != null) 'parcel_weight_kg': parcelWeightKg,
            if (senderName != null && senderName.isNotEmpty) 'sender_name': senderName,
            if (senderPhone != null && senderPhone.isNotEmpty) 'sender_phone': senderPhone,
            if (parcelInstructions != null && parcelInstructions.isNotEmpty)
              'parcel_instructions': parcelInstructions,
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

  Future<void> loadActive() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings/active');
      if (resp.data == null || (resp.data is String && resp.data == '')) {
        _activeBooking = null;
      } else {
        _activeBooking = Map<String, dynamic>.from(resp.data);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> updateStatus(int bookingId, String status, {String? reason}) async {
    try {
      final resp = await ApiClient.instance.dio.patch(
        '/bookings/$bookingId/status',
        data: {'status': status, if (reason != null) 'reason': reason},
      );
      _activeBooking = Map<String, dynamic>.from(resp.data);
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

  Future<bool> rate({required int bookingId, required int rating, String? feedback}) async {
    try {
      await ApiClient.instance.dio.post(
        '/bookings/$bookingId/rate',
        data: {'rating': rating, if (feedback != null) 'feedback': feedback},
      );
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

  Future<List<Map<String, dynamic>>> fetchHistory() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings');
      return List<Map<String, dynamic>>.from(resp.data as List);
    } catch (_) {
      return [];
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

  @override
  void dispose() {
    _ws.dispose();
    super.dispose();
  }
}
