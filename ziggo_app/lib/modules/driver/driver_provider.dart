import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/network/api_client.dart';
import '../../core/network/ws_client.dart';
import '../../core/notifications/fcm_service.dart';

class DriverProvider extends ChangeNotifier {
  final WsClient _ws = WsClient();
  WsClient get ws => _ws;

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? get profile => _profile;

  Map<String, dynamic>? _activeRide;
  Map<String, dynamic>? get activeRide => _activeRide;

  Map<String, dynamic>? _activeFoodOrder;
  Map<String, dynamic>? get activeFoodOrder => _activeFoodOrder;

  Map<String, dynamic>? _activeMarketOrder;
  Map<String, dynamic>? get activeMarketOrder => _activeMarketOrder;

  Map<String, dynamic>? _pendingRequest;
  Map<String, dynamic>? get pendingRequest => _pendingRequest;

  LatLng? _currentLocation;
  LatLng? get currentLocation => _currentLocation;

  List<Map<String, dynamic>> _incentives = [];
  List<Map<String, dynamic>> get incentives => _incentives;

  List<Map<String, dynamic>> _surgeZones = [];
  List<Map<String, dynamic>> get surgeZones => _surgeZones;

  Timer? _locationTimer;
  Timer? _profileTimer;

  Future<void> bootstrap(String token) async {
    _ws.connect(token);
    _ws.events.listen(_onWsEvent);
    await loadProfile();
    await loadActive();
    await loadActiveFoodOrder();
    await loadActiveMarketOrder();
    await loadIncentives();
    await loadSurgeZones();
    await _pushLocationOnce();
    _startProfileTimer();

    if (_isOnline) {
      await _startLocationStream();
    }
  }

  void _startProfileTimer() {
    _profileTimer?.cancel();
    _profileTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      loadProfile();
      loadIncentives();
      loadSurgeZones();
    });
  }

  void _onWsEvent(Map<String, dynamic> msg) {
    final event = msg['event'];
    final data = msg['data'] as Map<String, dynamic>?;
    if (data == null) return;
    
    // Aggressive catch-all: If it looks like a request, show it!
    final isRequestEvent = event == 'new_ride_request' || 
                           event == 'new_ride' || 
                           event == 'new_market_order' || 
                           event == 'new_market_request' || 
                           event.toString().contains('request') ||
                           event.toString().contains('broadcast') ||
                           (data.containsKey('pickup_lat') && data.containsKey('fare'));

    if (isRequestEvent) {
      // Rich payload — rides, parcels (is_flash), food orders (is_food),
      // and market orders (is_market) all flow through this listener.
      _pendingRequest = data;
      notifyListeners();
    } else if (event == 'booking_update' || event == 'destination_updated') {
      loadActive();
    } else if (event == 'order_update') {
      loadActiveFoodOrder();
    } else if (event == 'market_order_update') {
      loadActiveMarketOrder();
    } else if (event == 'ride_taken' || event == 'order_taken' || event == 'market_order_taken') {
      // Another driver claimed it. Match by booking_id, food_order_id, OR
      // market_order_id depending on what was pending.
      final pending = _pendingRequest;
      if (pending == null) return;
      final sameBooking = data['booking_id'] != null &&
          pending['booking_id'] == data['booking_id'];
      final sameFood = data['food_order_id'] != null &&
          pending['food_order_id'] == data['food_order_id'];
      final sameMarket = data['market_order_id'] != null &&
          pending['market_order_id'] == data['market_order_id'];
      if (sameBooking || sameFood || sameMarket) {
        _pendingRequest = null;
        FcmService.instance.cancelRideAlert();
        notifyListeners();
      }
    }
  }

  Future<bool> acceptRide(int bookingId) async {
    final pending = _pendingRequest;
    final isFood = pending != null && pending['is_food'] == true;
    final isMarket = pending != null && pending['is_market'] == true;
    final path = isFood
        ? '/food/orders/${pending['food_order_id']}/accept'
        : isMarket
            ? '/market/orders/${pending['market_order_id']}/accept'
            : '/bookings/$bookingId/accept';
    _pendingRequest = null;
    FcmService.instance.cancelRideAlert();
    notifyListeners();
    try {
      final resp = await ApiClient.instance.dio.post(path);
      if (isFood) {
        _activeRide = null;
        await loadActiveFoodOrder();
      } else if (isMarket) {
        _activeRide = null;
        await loadActiveMarketOrder();
      } else {
        _activeRide = Map<String, dynamic>.from(resp.data);
      }
      notifyListeners();
      return true;
    } on DioException {
      notifyListeners();
      return false;
    }
  }

  Future<void> declineRide(int bookingId) async {
    final pending = _pendingRequest;
    final isFood = pending != null && pending['is_food'] == true;
    final isMarket = pending != null && pending['is_market'] == true;
    final path = isFood
        ? '/food/orders/${pending['food_order_id']}/decline'
        : isMarket
            ? '/market/orders/${pending['market_order_id']}/decline'
            : '/bookings/$bookingId/decline';
    _pendingRequest = null;
    FcmService.instance.cancelRideAlert();
    notifyListeners();
    try {
      await ApiClient.instance.dio.post(path);
    } on DioException {
      // ignore
    }
  }

  Future<void> loadActiveMarketOrder() async {
    try {
      final resp = await ApiClient.instance.dio.get('/market/orders/active');
      if (resp.data == null || (resp.data is String && resp.data == '')) {
        _activeMarketOrder = null;
      } else {
        _activeMarketOrder = Map<String, dynamic>.from(resp.data);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> updateMarketOrderStatus(String status) async {
    final order = _activeMarketOrder;
    if (order == null) return false;
    final id = order['id'];
    try {
      await ApiClient.instance.dio.patch(
        '/market/orders/$id/status',
        data: {'status': status},
      );
      if (status == 'delivered' || status == 'cancelled') {
        _activeMarketOrder = null;
        await loadProfile();
        await loadIncentives();
      } else {
        await loadActiveMarketOrder();
      }
      notifyListeners();
      return true;
    } on DioException {
      return false;
    }
  }

  Future<void> loadProfile() async {
    try {
      final resp = await ApiClient.instance.dio.get('/driver/me');
      _profile = Map<String, dynamic>.from(resp.data);
      _isOnline = _profile?['is_online'] == true;
      notifyListeners();
    } on DioException {
      // ignore
    }
  }

  bool get profileComplete => _profile?['profile_complete'] == true;
  bool get isApproved => _profile?['is_approved'] == true;

  Future<String?> register({
    required String fullName,
    String? email,
    required String nicNumber,
    required String licenseNumber,
    required String vehicleType,
    required String vehicleNumber,
    required String vehicleModel,
    required String vehicleColor,
    required String relativeName,
    required String relativeContact,
    required String relativeRelationship,
    String? referralCode,
  }) async {
    try {
      final resp = await ApiClient.instance.dio.post('/driver/register', data: {
        'full_name': fullName,
        if (email != null && email.isNotEmpty) 'email': email,
        'nic_number': nicNumber,
        'license_number': licenseNumber,
        'vehicle_type': vehicleType,
        'vehicle_number': vehicleNumber,
        'vehicle_model': vehicleModel,
        'vehicle_color': vehicleColor,
        'relative_name': relativeName,
        'relative_contact': relativeContact,
        'relative_relationship': relativeRelationship,
        if (referralCode != null && referralCode.isNotEmpty) 'referral_code': referralCode,
      });
      _profile = Map<String, dynamic>.from(resp.data);
      notifyListeners();
      return null; // success
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Registration failed';
    }
  }

  Future<void> loadActive() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings/active');
      if (resp.data == null || (resp.data is String && resp.data == '')) {
        _activeRide = null;
      } else {
        _activeRide = Map<String, dynamic>.from(resp.data);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadActiveFoodOrder() async {
    try {
      final resp = await ApiClient.instance.dio.get('/food/orders/active');
      if (resp.data == null || (resp.data is String && resp.data == '')) {
        _activeFoodOrder = null;
      } else {
        _activeFoodOrder = Map<String, dynamic>.from(resp.data);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> updateFoodOrderStatus(String status) async {
    final order = _activeFoodOrder;
    if (order == null) return false;
    final id = order['id'];
    try {
      await ApiClient.instance.dio.patch(
        '/food/orders/$id/status',
        data: {'status': status},
      );
      if (status == 'delivered' || status == 'cancelled') {
        _activeFoodOrder = null;
        await loadProfile();
        await loadIncentives();
      } else {
        await loadActiveFoodOrder();
      }
      notifyListeners();
      return true;
    } on DioException {
      return false;
    }
  }

  Future<bool> toggleOnline(bool online) async {
    try {
      final resp = await ApiClient.instance.dio.post(
        '/driver/online',
        data: {'is_online': online},
      );
      _isOnline = resp.data['is_online'] == true;
      notifyListeners();

      if (_isOnline) {
        await _startLocationStream();
      } else {
        _stopLocationStream();
      }
      return true;
    } on DioException {
      return false;
    }
  }

  Future<void> _startLocationStream() async {
    _stopLocationStream();
    await _pushLocationOnce();
    _locationTimer = Timer.periodic(const Duration(seconds: 15), (_) => _pushLocationOnce());
  }

  void _stopLocationStream() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _pushLocationOnce() async {
    try {
      // Permission and platform check
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      notifyListeners();

      await ApiClient.instance.dio.post(
        '/driver/location',
        data: {
          'lat': pos.latitude,
          'lng': pos.longitude,
          if (pos.heading >= 0.0 && pos.heading <= 360.0) 'heading': pos.heading,
        },
      );
    } catch (_) {}
  }

  Future<bool> updateRideStatus(String status, {String? reason, String? otp}) async {
    if (_activeRide == null) return false;
    final id = _activeRide!['id'];
    try {
      final resp = await ApiClient.instance.dio.patch(
        '/bookings/$id/status',
        data: {
          'status': status,
          if (reason != null) 'reason': reason,
          if (otp != null) 'otp': otp,
        },
      );
      _activeRide = Map<String, dynamic>.from(resp.data);
      if (status == 'completed' || status == 'cancelled') {
        _activeRide = null;
        await loadProfile();
        await loadIncentives();
      }
      notifyListeners();
      return true;
    } on DioException {
      return false;
    }
  }

  Future<bool> updateBankDetails({
    required String bankName,
    required String accountHolderName,
    required String accountNumber,
    required String branchName,
  }) async {
    try {
      final resp = await ApiClient.instance.dio.post('/driver/bank-details', data: {
        'bank_name': bankName,
        'account_holder_name': accountHolderName,
        'account_number': accountNumber,
        'branch_name': branchName,
      });
      _profile = Map<String, dynamic>.from(resp.data);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> rateBooking({required int bookingId, required int rating, String? feedback}) async {
    try {
      await ApiClient.instance.dio.post(
        '/bookings/$bookingId/rate',
        data: {'rating': rating, if (feedback != null) 'feedback': feedback},
      );
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void setPendingRequest(Map<String, dynamic> request) {
    _pendingRequest = request;
    notifyListeners();
  }

  void dismissPendingRequest() {
    _pendingRequest = null;
    notifyListeners();
  }

  Future<void> loadIncentives() async {
    try {
      final resp = await ApiClient.instance.dio.get('/driver/incentives');
      _incentives = List<Map<String, dynamic>>.from(resp.data);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadSurgeZones() async {
    try {
      final resp = await ApiClient.instance.dio.get('/surge-zones/active');
      _surgeZones = List<Map<String, dynamic>>.from(resp.data);
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> updateProfilePhoto(String filePath) async {
    try {
      final photoForm = FormData.fromMap({
        'photo': await MultipartFile.fromFile(filePath),
      });
      final resp = await ApiClient.instance.dio.post('/driver/profile-photo', data: photoForm);
      if (resp.data != null && resp.data['profile_photo'] != null) {
        _profile?['profile_photo'] = resp.data['profile_photo'];
        notifyListeners();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _stopLocationStream();
    _profileTimer?.cancel();
    _ws.dispose();
    super.dispose();
  }
}
