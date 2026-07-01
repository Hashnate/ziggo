import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/network/ws_client.dart';

/// State + API for the restaurant-owner portal.
class RestaurantProvider extends ChangeNotifier {
  final WsClient _ws = WsClient();
  WsClient get ws => _ws;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? get profile => _profile;

  /// True once we've finished a /restaurant/me call at least once, regardless
  /// of whether the response had a profile. Used by screens to distinguish
  /// "still loading" from "loaded, no profile yet" — without this, a 200-null
  /// response leaves the UI stuck on a spinner.
  bool _profileLoaded = false;
  bool get profileLoaded => _profileLoaded;

  bool get isApproved => _profile?['is_approved'] == true;
  bool get isOpen => _profile?['is_open'] == true;
  bool get hasProfile => _profile != null;

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

  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _items = const [];
  List<Map<String, dynamic>> get categories => _categories;
  List<Map<String, dynamic>> get items => _items;
  bool _loadingMenu = false;
  bool get loadingMenu => _loadingMenu;

  /// Fires every time a new_food_order WS event arrives. Screens listen to it
  /// to show a banner / play a sound without rebuilding the whole tree.
  final ValueNotifier<int> newOrderPing = ValueNotifier<int>(0);

  Future<void> bootstrap(String token) async {
    _ws.connect(token);
    _ws.events.listen(_onWsEvent);
    await loadProfile();
    if (isApproved) {
      await loadOrders();
      await loadTodayStats();
    }
  }

  /// Fires when the admin approves the restaurant. UI listens and shows a
  /// celebratory dialog instead of forcing the owner to refresh.
  final ValueNotifier<int> approvalPing = ValueNotifier<int>(0);

  void _onWsEvent(Map<String, dynamic> msg) {
    final event = msg['event'];
    if (event == 'new_food_order') {
      HapticFeedback.heavyImpact();
      SystemSound.play(SystemSoundType.alert);
      newOrderPing.value = newOrderPing.value + 1;
      loadOrders();
      loadTodayStats();
      return;
    }
    if (event == 'order_update') {
      loadOrders();
      loadHistory();
      loadTodayStats();
      return;
    }
    if (event == 'restaurant_approved' || event == 'restaurant_suspended') {
      loadProfile();
      loadTodayStats();
      if (event == 'restaurant_approved') {
        HapticFeedback.mediumImpact();
        approvalPing.value = approvalPing.value + 1;
      }
    }
  }

  Future<void> loadProfile() async {
    try {
      final resp = await ApiClient.instance.dio.get('/restaurant/me');
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

  Future<String?> register({
    required String name,
    String? description,
    required String address,
    required double lat,
    required double lng,
    String? phoneNumber,
    String? cuisine,
    String? openingTime,
    String? closingTime,
    double? deliveryFee,
    int? etaMinutes,
  }) async {
    try {
      final resp = await ApiClient.instance.dio.post(
        '/restaurant/register',
        data: {
          'name': name,
          if (description != null && description.isNotEmpty) 'description': description,
          'address': address,
          'lat': lat,
          'lng': lng,
          if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
          if (cuisine != null && cuisine.isNotEmpty) 'cuisine': cuisine,
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

  Future<bool> toggleOnline(bool open) async {
    try {
      final resp = await ApiClient.instance.dio.post(
        '/restaurant/online',
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
        '/restaurant/orders',
        queryParameters: {'status': 'pending'},
      );
      final activeResp = await ApiClient.instance.dio.get(
        '/restaurant/orders',
        queryParameters: {'status': 'active'},
      );
      _pendingOrders = List<Map<String, dynamic>>.from(pendingResp.data as List);
      _activeOrders = List<Map<String, dynamic>>.from(activeResp.data as List);
    } on DioException {
      // ignore — keep last good state visible
    } finally {
      _loadingOrders = false;
      notifyListeners();
    }
  }

  Future<void> loadHistory() async {
    try {
      final resp = await ApiClient.instance.dio.get(
        '/restaurant/orders',
        queryParameters: {'status': 'history'},
      );
      _historyOrders = List<Map<String, dynamic>>.from(resp.data as List);
      notifyListeners();
    } on DioException {
      // ignore
    }
  }

  Future<String?> acceptOrder(int orderId) async {
    return _orderAction('POST', '/restaurant/orders/$orderId/accept');
  }

  Future<String?> rejectOrder(int orderId, {String? reason}) async {
    return _orderAction(
      'POST',
      '/restaurant/orders/$orderId/reject',
      body: reason == null ? null : {'reason': reason},
    );
  }

  Future<String?> markPreparing(int orderId) async {
    return _orderAction('POST', '/restaurant/orders/$orderId/preparing');
  }

  Future<String?> markReady(int orderId) async {
    return _orderAction('POST', '/restaurant/orders/$orderId/ready');
  }

  Future<String?> _orderAction(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      if (method == 'POST') {
        await ApiClient.instance.dio.post(path, data: body);
      }
      await loadOrders();
      await loadTodayStats();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Action failed';
    }
  }

  /// Single-order detail including the line items the customer ordered.
  /// Used by the order detail screen so the merchant sees what to cook.
  Future<Map<String, dynamic>?> fetchOrderDetail(int orderId) async {
    try {
      final resp = await ApiClient.instance.dio.get('/restaurant/orders/$orderId');
      return Map<String, dynamic>.from(resp.data as Map);
    } on DioException {
      return null;
    }
  }

  Future<void> loadTodayStats() async {
    try {
      final resp = await ApiClient.instance.dio.get('/restaurant/stats/today');
      _todayStats = Map<String, dynamic>.from(resp.data as Map);
      notifyListeners();
    } on DioException {
      // ignore — leave last good state
    }
  }

  // -------- Menu management --------

  Future<void> loadMenu() async {
    if (_loadingMenu) return;
    _loadingMenu = true;
    notifyListeners();
    try {
      final c = await ApiClient.instance.dio.get('/restaurant/categories');
      final i = await ApiClient.instance.dio.get('/restaurant/items');
      _categories = List<Map<String, dynamic>>.from(c.data as List);
      _items = List<Map<String, dynamic>>.from(i.data as List);
    } on DioException {
      // ignore
    } finally {
      _loadingMenu = false;
      notifyListeners();
    }
  }

  Future<String?> createCategory({required String name, String? description}) async {
    try {
      await ApiClient.instance.dio.post('/restaurant/categories', data: {
        'name': name,
        if (description != null && description.isNotEmpty) 'description': description,
      });
      await loadMenu();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> updateCategory(
    int id, {
    String? name,
    String? description,
    bool? isActive,
  }) async {
    try {
      await ApiClient.instance.dio.patch('/restaurant/categories/$id', data: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (isActive != null) 'is_active': isActive,
      });
      await loadMenu();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> deleteCategory(int id) async {
    try {
      await ApiClient.instance.dio.delete('/restaurant/categories/$id');
      await loadMenu();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> createItem({
    required String name,
    required double price,
    int? categoryId,
    String? description,
    bool isVeg = false,
    bool isAvailable = true,
    int? prepTimeMin,
  }) async {
    try {
      await ApiClient.instance.dio.post('/restaurant/items', data: {
        'name': name,
        'price': price,
        if (categoryId != null) 'category_id': categoryId,
        if (description != null && description.isNotEmpty) 'description': description,
        'is_veg': isVeg,
        'is_available': isAvailable,
        if (prepTimeMin != null) 'prep_time_min': prepTimeMin,
      });
      await loadMenu();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> updateItem(
    int id, {
    String? name,
    double? price,
    int? categoryId,
    String? description,
    bool? isVeg,
    bool? isAvailable,
    int? prepTimeMin,
  }) async {
    try {
      await ApiClient.instance.dio.patch('/restaurant/items/$id', data: {
        if (name != null) 'name': name,
        if (price != null) 'price': price,
        if (categoryId != null) 'category_id': categoryId,
        if (description != null) 'description': description,
        if (isVeg != null) 'is_veg': isVeg,
        if (isAvailable != null) 'is_available': isAvailable,
        if (prepTimeMin != null) 'prep_time_min': prepTimeMin,
      });
      await loadMenu();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> toggleItemAvailability(int id, bool isAvailable) async {
    return updateItem(id, isAvailable: isAvailable);
  }

  Future<String?> deleteItem(int id) async {
    try {
      await ApiClient.instance.dio.delete('/restaurant/items/$id');
      await loadMenu();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  // -------- Profile editing --------

  Future<String?> updateProfile({
    String? name,
    String? description,
    String? address,
    double? lat,
    double? lng,
    String? phoneNumber,
    String? cuisine,
    String? openingTime,
    String? closingTime,
    double? deliveryFee,
    int? etaMinutes,
  }) async {
    try {
      final resp = await ApiClient.instance.dio.patch(
        '/restaurant/profile',
        data: {
          if (name != null) 'name': name,
          if (description != null) 'description': description,
          if (address != null) 'address': address,
          if (lat != null) 'lat': lat,
          if (lng != null) 'lng': lng,
          if (phoneNumber != null) 'phone_number': phoneNumber,
          if (cuisine != null) 'cuisine': cuisine,
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

  // -------- Image uploads (multipart) --------

  Future<String?> uploadCover(File file) async {
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path),
      });
      final resp = await ApiClient.instance.dio.post(
        '/restaurant/cover-image',
        data: form,
      );
      _profile = Map<String, dynamic>.from(resp.data);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  Future<String?> uploadItemImage(int itemId, File file) async {
    try {
      final form = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path),
      });
      await ApiClient.instance.dio.post(
        '/restaurant/items/$itemId/image',
        data: form,
      );
      await loadMenu();
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? e.message ?? 'Failed';
    }
  }

  // -------- Earnings --------

  Future<Map<String, dynamic>?> fetchEarnings({String period = 'week'}) async {
    try {
      final resp = await ApiClient.instance.dio.get(
        '/restaurant/earnings',
        queryParameters: {'period': period},
      );
      return Map<String, dynamic>.from(resp.data as Map);
    } on DioException {
      return null;
    }
  }

  // -------- Commission --------

  /// Fetches the restaurant's commission summary and payment history.
  /// Returns a map with keys: outstanding_amount, commission_rate,
  /// total_sales, total_commission_owed, total_paid, payments (list).
  Future<Map<String, dynamic>?> fetchCommission() async {
    try {
      final resp =
          await ApiClient.instance.dio.get('/restaurant/commission');
      return Map<String, dynamic>.from(resp.data as Map);
    } on DioException {
      return null;
    }
  }

  /// Submits a commission payment to the admin.
  /// Returns null on success, or an error string on failure.
  Future<String?> payCommission() async {
    try {
      await ApiClient.instance.dio.post('/restaurant/commission/pay');
      return null;
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ??
          e.message ??
          'Payment failed';
    }
  }

  @override
  void dispose() {
    _ws.dispose();
    newOrderPing.dispose();
    approvalPing.dispose();
    super.dispose();
  }
}
