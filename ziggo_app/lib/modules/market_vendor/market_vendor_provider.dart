import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/network/ws_client.dart';

/// State + API for the market-vendor portal. Mirrors RestaurantProvider but
/// targets `/market/vendor/*` endpoints. The vendor account is pre-created by
/// admin via the admin panel; the owner just OTP-logs in as `market_owner`.
class MarketVendorProvider extends ChangeNotifier {
  final WsClient _ws = WsClient();
  WsClient get ws => _ws;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? get profile => _profile;

  /// True once we've finished a /market/vendor/me call at least once. Used to
  /// distinguish "still loading" from "loaded, no profile yet" so the UI can
  /// flip to the registration screen instead of an infinite spinner.
  bool _profileLoaded = false;
  bool get profileLoaded => _profileLoaded;

  bool get isApproved => _profile?['is_approved'] == true;
  bool get isOpen => _profile?['is_open'] == true;
  bool get hasProfile => _profile != null;

  /// Delivery capabilities — drive the "deliver yourself or find a rider?"
  /// prompt when the vendor marks an order ready.
  bool get canSelfDeliver => _profile?['self_delivery'] == true;
  bool get canMarketplaceDeliver => _profile?['marketplace_delivery'] != false;
  bool get mustChooseDeliveryMode => canSelfDeliver && canMarketplaceDeliver;

  String? _lastError;
  String? get lastError => _lastError;

  List<Map<String, dynamic>> _pendingOrders = const [];
  List<Map<String, dynamic>> _activeOrders = const [];
  List<Map<String, dynamic>> _historyOrders = const [];
  List<Map<String, dynamic>> get pendingOrders => _pendingOrders;
  List<Map<String, dynamic>> get activeOrders => _activeOrders;
  List<Map<String, dynamic>> get historyOrders => _historyOrders;

  bool _loadingOrders = false;
  bool get loadingOrders => _loadingOrders;

  Map<String, dynamic>? _todayStats;
  Map<String, dynamic>? get todayStats => _todayStats;

  List<Map<String, dynamic>> _products = const [];
  List<Map<String, dynamic>> get products => _products;
  bool _loadingProducts = false;
  bool get loadingProducts => _loadingProducts;

  List<Map<String, dynamic>> _ads = const [];
  List<Map<String, dynamic>> get ads => _ads;

  final ValueNotifier<int> newOrderPing = ValueNotifier<int>(0);

  /// Latest message string when the backend's rider broadcast finds nobody
  /// in range. The home screen listens to flash a red snackbar so the owner
  /// knows the order is stuck on READY_FOR_PICKUP.
  final ValueNotifier<String?> noRidersPing = ValueNotifier<String?>(null);

  Future<void> bootstrap(String token) async {
    _ws.connect(token);
    _ws.events.listen(_onWsEvent);
    await loadProfile();
    if (isApproved) {
      await loadOrders();
      await loadTodayStats();
    }
  }

  void _onWsEvent(Map<String, dynamic> msg) {
    final event = msg['event'];
    if (event == 'new_market_order') {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      newOrderPing.value = newOrderPing.value + 1;
      loadOrders();
      loadTodayStats();
      return;
    }
    if (event == 'market_order_update') {
      loadOrders();
      loadHistory();
      loadTodayStats();
      return;
    }
    if (event == 'no_riders_for_market_order') {
      final reason = msg['data']?['reason']?.toString() ??
          'No riders available — the order is waiting for a rider.';
      noRidersPing.value = reason;
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> loadProfile() async {
    try {
      final resp = await ApiClient.instance.dio.get('/market/vendor/me');
      if (resp.data == null || (resp.data is String && resp.data == '')) {
        _profile = null;
      } else {
        _profile = Map<String, dynamic>.from(resp.data);
      }
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
    } finally {
      _profileLoaded = true;
      notifyListeners();
    }
  }

  Future<bool> toggleOnline(bool open) async {
    try {
      final resp = await ApiClient.instance.dio.post(
        '/market/vendor/online',
        data: {'is_open': open},
      );
      if (_profile != null) {
        _profile = {..._profile!, 'is_open': resp.data['is_open'] == true};
        notifyListeners();
      }
      return true;
    } on DioException {
      return false;
    }
  }

  Future<void> loadOrders() async {
    if (_loadingOrders) return;
    _loadingOrders = true;
    notifyListeners();
    try {
      final pendingResp = await ApiClient.instance.dio.get(
        '/market/vendor/orders',
        queryParameters: {'status': 'pending'},
      );
      final activeResp = await ApiClient.instance.dio.get(
        '/market/vendor/orders',
        queryParameters: {'status': 'active'},
      );
      _pendingOrders = List<Map<String, dynamic>>.from(pendingResp.data as List);
      _activeOrders = List<Map<String, dynamic>>.from(activeResp.data as List);
    } on DioException {
      // ignore
    } finally {
      _loadingOrders = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory() async {
    try {
      final resp = await ApiClient.instance.dio.get(
        '/market/vendor/orders',
        queryParameters: {'status': 'history'},
      );
      _historyOrders = List<Map<String, dynamic>>.from(resp.data as List);
      notifyListeners();
    } on DioException {
      // ignore
    }
  }

  Future<Map<String, dynamic>?> fetchOrderDetail(int orderId) async {
    try {
      final resp =
          await ApiClient.instance.dio.get('/market/vendor/orders/$orderId');
      return Map<String, dynamic>.from(resp.data as Map);
    } on DioException {
      return null;
    }
  }

  Future<String?> acceptOrder(int orderId) =>
      _orderAction('/market/vendor/orders/$orderId/accept');

  Future<String?> rejectOrder(int orderId, {String? reason}) => _orderAction(
        '/market/vendor/orders/$orderId/reject',
        body: reason == null ? null : {'reason': reason},
      );

  Future<String?> markPreparing(int orderId) =>
      _orderAction('/market/vendor/orders/$orderId/preparing');

  /// Mark an order ready. [deliveryMode] is "self" (vendor delivers) or
  /// "marketplace" (broadcast to riders). Required only when the vendor has
  /// both delivery options enabled; otherwise the backend resolves it.
  Future<String?> markReady(int orderId, {String? deliveryMode}) => _orderAction(
        '/market/vendor/orders/$orderId/ready',
        body: deliveryMode == null ? null : {'delivery_mode': deliveryMode},
      );

  /// Self-delivery: vendor has set off with the order.
  Future<String?> markOutForDelivery(int orderId) =>
      _orderAction('/market/vendor/orders/$orderId/out-for-delivery');

  /// Self-delivery: vendor handed the order to the customer.
  Future<String?> markDelivered(int orderId) =>
      _orderAction('/market/vendor/orders/$orderId/delivered');

  /// Re-trigger the rider broadcast for an order stuck at READY_FOR_PICKUP.
  /// Useful when the first broadcast missed (no riders in range / wrong
  /// vendor location / etc.).
  Future<String?> rebroadcast(int orderId) =>
      _orderAction('/market/vendor/orders/$orderId/rebroadcast');

  Future<String?> _orderAction(String path, {Map<String, dynamic>? body}) async {
    try {
      await ApiClient.instance.dio.post(path, data: body);
      await loadOrders();
      await loadTodayStats();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<void> loadTodayStats() async {
    try {
      final resp =
          await ApiClient.instance.dio.get('/market/vendor/stats/today');
      _todayStats = Map<String, dynamic>.from(resp.data as Map);
      notifyListeners();
    } on DioException {
      // ignore
    }
  }

  Future<Map<String, dynamic>?> fetchEarnings({String period = 'week'}) async {
    try {
      final resp = await ApiClient.instance.dio.get(
        '/market/vendor/earnings',
        queryParameters: {'period': period},
      );
      return Map<String, dynamic>.from(resp.data as Map);
    } on DioException {
      return null;
    }
  }

  // -------- Self-registration (mirrors RestaurantProvider.register) --------

  Future<String?> register({
    required String name,
    String? description,
    String? category,
    required String address,
    required double lat,
    required double lng,
    String? phoneNumber,
    String? openingTime,
    String? closingTime,
    double? deliveryFee,
    int? etaMinutes,
  }) async {
    try {
      final resp = await ApiClient.instance.dio.post(
        '/market/vendor/register',
        data: {
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
          if (category != null && category.isNotEmpty) 'category': category,
          'address': address,
          'lat': lat,
          'lng': lng,
          if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
          if (openingTime != null) 'opening_time': openingTime,
          if (closingTime != null) 'closing_time': closingTime,
          if (deliveryFee != null) 'delivery_fee': deliveryFee,
          if (etaMinutes != null) 'eta_minutes': etaMinutes,
        },
      );
      _profile = Map<String, dynamic>.from(resp.data);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Registration failed';
    }
  }

  // -------- Profile --------

  Future<String?> updateProfile({
    String? name,
    String? description,
    String? category,
    String? address,
    double? lat,
    double? lng,
    String? phoneNumber,
    String? openingTime,
    String? closingTime,
    double? deliveryFee,
    int? etaMinutes,
  }) async {
    try {
      final resp = await ApiClient.instance.dio.patch(
        '/market/vendor/profile',
        data: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (category != null) 'category': category,
          if (address != null) 'address': address,
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          if (phoneNumber != null) 'phone_number': phoneNumber,
          if (openingTime != null) 'opening_time': openingTime,
          if (closingTime != null) 'closing_time': closingTime,
          if (deliveryFee != null) 'delivery_fee': deliveryFee,
          if (etaMinutes != null) 'eta_minutes': etaMinutes,
        },
      );
      _profile = Map<String, dynamic>.from(resp.data);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> uploadCover(File file) async {
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path),
      });
      final resp = await ApiClient.instance.dio.post(
        '/market/vendor/cover-image',
        data: form,
      );
      _profile = Map<String, dynamic>.from(resp.data);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> uploadLogo(File file) async {
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path),
      });
      final resp = await ApiClient.instance.dio.post(
        '/market/vendor/logo-image',
        data: form,
      );
      _profile = Map<String, dynamic>.from(resp.data);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  // -------- Products --------

  Future<void> loadProducts() async {
    if (_loadingProducts) return;
    _loadingProducts = true;
    notifyListeners();
    try {
      final resp = await ApiClient.instance.dio.get('/market/vendor/products');
      _products = List<Map<String, dynamic>>.from(resp.data as List);
    } on DioException {
      // ignore
    } finally {
      _loadingProducts = false;
      notifyListeners();
    }
  }

  Future<String?> createProduct({
    required String name,
    required double price,
    int stockQuantity = 0,
    String? description,
    String? unit,
    bool isAvailable = true,
    String? category,
    double? originalPrice,
    bool isPopular = false,
    double? weightKg,
  }) async {
    try {
      await ApiClient.instance.dio.post('/market/vendor/products', data: {
        'name': name,
        'price': price,
        'stock_quantity': stockQuantity,
        if (description != null && description.isNotEmpty) 'description': description,
        if (unit != null && unit.isNotEmpty) 'unit': unit,
        'is_available': isAvailable,
        if (category != null && category.isNotEmpty) 'category': category,
        if (originalPrice != null && originalPrice > 0) 'original_price': originalPrice,
        'is_popular': isPopular,
        if (weightKg != null) 'weight_kg': weightKg,
      });
      await loadProducts();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> updateProduct(
    int id, {
    String? name,
    double? price,
    int? stockQuantity,
    String? description,
    String? unit,
    bool? isAvailable,
    String? category,
    double? originalPrice,
    bool? isPopular,
    double? weightKg,
  }) async {
    try {
      await ApiClient.instance.dio.patch('/market/vendor/products/$id', data: {
        if (name != null) 'name': name,
        if (price != null) 'price': price,
        if (stockQuantity != null) 'stock_quantity': stockQuantity,
        if (description != null) 'description': description,
        if (unit != null) 'unit': unit,
        if (isAvailable != null) 'is_available': isAvailable,
        if (category != null) 'category': category,
        if (originalPrice != null) 'original_price': originalPrice > 0 ? originalPrice : null,
        if (isPopular != null) 'is_popular': isPopular,
        if (weightKg != null) 'weight_kg': weightKg,
      });
      await loadProducts();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> toggleProductAvailability(int id, bool isAvailable) =>
      updateProduct(id, isAvailable: isAvailable);

  Future<String?> deleteProduct(int id) async {
    try {
      await ApiClient.instance.dio.delete('/market/vendor/products/$id');
      await loadProducts();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> uploadProductImage(int id, File file) async {
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path),
      });
      await ApiClient.instance.dio.post(
        '/market/vendor/products/$id/image',
        data: form,
      );
      await loadProducts();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<void> fetchMyAds() async {
    try {
      final resp = await ApiClient.instance.dio.get('/market/vendor/ads');
      _ads = List<Map<String, dynamic>>.from(resp.data as List);
      notifyListeners();
    } on DioException {
      // ignore
    }
  }

  Future<String?> uploadAd(File file, double radiusKm) async {
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path),
        'radius_km': radiusKm,
      });
      await ApiClient.instance.dio.post('/market/vendor/ads', data: form);
      await fetchMyAds();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> deleteAd(int adId) async {
    try {
      await ApiClient.instance.dio.delete('/market/vendor/ads/$adId');
      await fetchMyAds();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  @override
  void dispose() {
    _ws.dispose();
    newOrderPing.dispose();
    noRidersPing.dispose();
    super.dispose();
  }
}
