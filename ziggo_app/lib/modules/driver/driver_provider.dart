import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, AppLifecycleState;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/network/api_client.dart';
import '../../core/network/ws_client.dart';
import '../../core/notifications/fcm_service.dart';
import '../../core/services/floating_overlay_service.dart';

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

  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> get vehicles => _vehicles;
  List<Map<String, dynamic>> get approvedVehicles => _vehicles.where((v) => v['is_approved'] == true).toList();
  Map<String, dynamic>? get activeVehicle => _vehicles.firstWhere(
        (v) => v['is_active'] == true,
        orElse: () => _vehicles.isNotEmpty ? _vehicles.first : {},
      );

  StreamSubscription<Position>? _locationSub;
  DateTime? _lastLocationPush;
  Timer? _profileTimer;

  Future<void> bootstrap(String token) async {
    _ws.connect(token);
    _ws.events.listen(_onWsEvent);
    await loadProfile();
    await loadVehicles();
    await loadActive();
    await loadActiveFoodOrder();
    await loadActiveMarketOrder();
    await loadPendingRequest();
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

    if (event == 'admin_config_update') {
      loadProfile();
      loadIncentives();
      loadSurgeZones();
      return;
    }

    if (data == null) return;
    
    // Aggressive catch-all: If it looks like a request, show it!
    // But exclude cancellation events that might contain 'request'.
    final isCancelEvent = event.toString().contains('cancel');
    final isRequestEvent = !isCancelEvent && (
                           event == 'new_ride_request' || 
                           event == 'new_ride' || 
                           event == 'new_market_order' || 
                           event == 'new_market_request' || 
                           event.toString().contains('request') ||
                           event.toString().contains('broadcast') ||
                           (data.containsKey('pickup_lat') && data.containsKey('fare'))
    );

    if (isCancelEvent) {
      loadActive();
      final pending = _pendingRequest;
      if (pending != null) {
        final pendingBid = pending['booking_id'] ?? pending['food_order_id'] ?? pending['market_order_id'];
        final dataBid   = data['booking_id'] ?? data['food_order_id'] ?? data['market_order_id'];
        if (dataBid != null && pendingBid != null && pendingBid == dataBid) {
          _pendingRequest = null;
          FcmService.instance.cancelRideAlert();
          notifyListeners();
        }
      }
    } else if (isRequestEvent) {
      // Rich payload — rides, parcels (is_flash), food orders (is_food),
      // and market orders (is_market) all flow through this listener.
      _pendingRequest = data;
      notifyListeners();
      // App alive but off-screen (backgrounded or locked mid-session, kept
      // running by the location stream): sound the alarm now instead of
      // waiting on FCM. Same notification id as the push path, so if FCM
      // lands a second later it replaces this rather than stacking.
      if (SchedulerBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        unawaited(FcmService.instance.showRideAlarmFromApp(data));
      }
    } else if (event == 'booking_update' || event == 'destination_updated') {
      loadActive();
      // If the booking was cancelled by the customer while the driver still has
      // a pending request for the same booking, dismiss the request card now so
      // the driver is NOT shown a stale alert for a ride that no longer exists.
      final cancelledStatus = data['status']?.toString();
      if (cancelledStatus == 'cancelled') {
        final pending = _pendingRequest;
        if (pending != null) {
          final pendingBid = pending['booking_id'];
          final dataBid   = data['booking_id'];
          if (dataBid != null && pendingBid != null && pendingBid == dataBid) {
            _pendingRequest = null;
            FcmService.instance.cancelRideAlert();
            notifyListeners();
          }
        }
      }
    } else if (event == 'booking_cancelled') {
      // Dedicated cancellation event — dismiss matching pending request.
      loadActive();
      final pending = _pendingRequest;
      if (pending != null) {
        final pendingBid = pending['booking_id'];
        final dataBid   = data['booking_id'];
        if (dataBid != null && pendingBid != null && pendingBid == dataBid) {
          _pendingRequest = null;
          FcmService.instance.cancelRideAlert();
          notifyListeners();
        }
      }
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

  Future<void> loadVehicles() async {
    try {
      final resp = await ApiClient.instance.dio.get('/driver/vehicles');
      if (resp.data is List) {
        _vehicles = List<Map<String, dynamic>>.from(resp.data);
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<bool> selectActiveVehicle(int vehicleId) async {
    try {
      await ApiClient.instance.dio.post('/driver/vehicles/$vehicleId/select');
      await loadVehicles();
      await loadProfile();
      return true;
    } on DioException catch (e) {
      if (e.response?.data != null && e.response!.data is Map && e.response!.data['detail'] != null) {
        throw Exception(e.response!.data['detail']);
      }
      return false;
    }
  }

  Future<bool> addVehicle({
    required String vehicleType,
    required String vehicleNumber,
    String? vehicleModel,
    String? vehicleColor,
    int? vehicleYear,
    String? vehiclePhotoUrl,
    String? registrationDocUrl,
    String? insuranceDocUrl,
    String? revenueLicenseDocUrl,
  }) async {
    try {
      await ApiClient.instance.dio.post('/driver/vehicles', data: {
        'vehicle_type': vehicleType,
        'vehicle_number': vehicleNumber,
        if (vehicleModel != null) 'vehicle_model': vehicleModel,
        if (vehicleColor != null) 'vehicle_color': vehicleColor,
        if (vehicleYear != null) 'vehicle_year': vehicleYear,
        if (vehiclePhotoUrl != null) 'vehicle_photo_url': vehiclePhotoUrl,
        if (registrationDocUrl != null) 'registration_doc_url': registrationDocUrl,
        if (insuranceDocUrl != null) 'insurance_doc_url': insuranceDocUrl,
        if (revenueLicenseDocUrl != null) 'revenue_license_doc_url': revenueLicenseDocUrl,
      });
      await loadVehicles();
      return true;
    } on DioException catch (e) {
      if (e.response?.data != null && e.response!.data is Map && e.response!.data['detail'] != null) {
        throw Exception(e.response!.data['detail']);
      }
      return false;
    }
  }

  Future<bool> deleteVehicle(int vehicleId) async {
    try {
      await ApiClient.instance.dio.delete('/driver/vehicles/$vehicleId');
      await loadVehicles();
      return true;
    } catch (_) {
      return false;
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
    required String driverType,
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
        'driver_type': driverType,
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
        unawaited(FloatingOverlayService.hideFloatingWidget());
      }
      return true;
    } on DioException catch (e) {
      if (e.response?.data != null && e.response!.data is Map && e.response!.data['detail'] != null) {
        throw Exception(e.response!.data['detail']);
      }
      return false;
    }
  }

  /// Keeps the app alive for the whole online session — the way Uber does it.
  ///
  /// A plain Timer dies the moment the OS suspends the app, which on iOS is
  /// seconds after the driver switches apps or locks the phone. A continuous
  /// location stream is different: with the `location` background mode (iOS)
  /// or a location foreground service (Android) the OS lets the process keep
  /// running, so the WebSocket stays connected, location keeps reaching
  /// dispatch, and a ride request lands in the app the instant it's sent.
  Future<void> _startLocationStream() async {
    _stopLocationStream();

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return;
    }

    await _pushLocationOnce();

    final LocationSettings settings;
    if (Platform.isAndroid) {
      settings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        intervalDuration: const Duration(seconds: 10),
        // The foreground service is what stops Android killing the process
        // while the driver is online. Its notification is mandatory and is
        // the "You're online" card the driver sees.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: "You're online",
          notificationText: 'Ziggo is listening for ride requests',
          notificationChannelName: 'Online status',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    } else if (Platform.isIOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        activityType: ActivityType.automotiveNavigation,
        // Never let iOS pause updates when it decides the phone is stationary;
        // a parked driver waiting for a request is exactly who we need alive.
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    } else {
      settings = const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10);
    }

    _locationSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
        notifyListeners();
        // Every fix keeps the process alive; only some need to reach the server.
        final now = DateTime.now();
        if (_lastLocationPush == null ||
            now.difference(_lastLocationPush!) >= const Duration(seconds: 10)) {
          _lastLocationPush = now;
          unawaited(_sendLocation(pos));
        }
      },
      onError: (e) {
        if (kDebugMode) debugPrint('[driver] location stream error: $e');
      },
    );
  }

  void _stopLocationStream() {
    _locationSub?.cancel();
    _locationSub = null;
    _lastLocationPush = null;
  }

  Future<void> _sendLocation(Position pos) async {
    try {
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
      _lastLocationPush = DateTime.now();
      await _sendLocation(pos);
    } catch (_) {}
  }

  void updateCurrentLocation(LatLng location) {
    _currentLocation = location;
    notifyListeners();
  }

  Map<String, dynamic>? _lastCompletedRide;
  Map<String, dynamic>? get lastCompletedRide => _lastCompletedRide;

  Future<bool> updateRideStatus(
    String status, {
    String? reason,
    String? otp,
    double? actualDropLat,
    double? actualDropLng,
  }) async {
    if (_activeRide == null) return false;
    final id = _activeRide!['id'];
    try {
      final resp = await ApiClient.instance.dio.patch(
        '/bookings/$id/status',
        data: {
          'status': status,
          if (reason != null) 'reason': reason,
          if (otp != null) 'otp': otp,
          if (actualDropLat != null) 'lat': actualDropLat,
          if (actualDropLng != null) 'lng': actualDropLng,
        },
      );
      final updated = Map<String, dynamic>.from(resp.data);
      _activeRide = updated;
      if (status == 'completed') {
        _lastCompletedRide = updated;
      }
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

  /// Recover an outstanding ride offer from the server. A request normally
  /// arrives as a WebSocket event or a notification tap; if the app was asleep
  /// for the first and the second didn't route, the offer was invisible. Now
  /// it's fetched on every open and resume — the way Uber's driver app does.
  Future<void> loadPendingRequest() async {
    if (_activeRide != null || _activeFoodOrder != null || _activeMarketOrder != null) return;
    try {
      final resp = await ApiClient.instance.dio.get('/driver/pending-request');
      final data = resp.data;
      if (data == null || data is! Map) return;
      final request = Map<String, dynamic>.from(data);
      final incoming = request['booking_id'];
      final current = _pendingRequest?['booking_id'];
      // Same offer already on screen — leave its countdown alone.
      if (current != null && incoming != null && current == incoming) return;
      _pendingRequest = request;
      notifyListeners();
    } catch (_) {}
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
  void notifyListeners() {
    _updateWakelock();
    super.notifyListeners();
  }

  void _updateWakelock() {
    final bool hasActiveTrip = (_activeRide != null && !['completed', 'cancelled'].contains(_activeRide?['status'])) ||
        (_activeFoodOrder != null && !['delivered', 'cancelled'].contains(_activeFoodOrder?['status'])) ||
        (_activeMarketOrder != null && !['delivered', 'cancelled'].contains(_activeMarketOrder?['status']));
    try {
      if (hasActiveTrip) {
        WakelockPlus.enable();
      } else {
        WakelockPlus.disable();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      WakelockPlus.disable();
    } catch (_) {}
    _stopLocationStream();
    _profileTimer?.cancel();
    _ws.dispose();
    super.dispose();
  }
}
