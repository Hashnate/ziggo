import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

class MarketProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _vendors = const [];
  List<Map<String, dynamic>> _ads = const [];
  List<Map<String, dynamic>> _deals = const [];
  List<Map<String, dynamic>> _categories = const [];
  bool _loading = false;
  String? _error;

  /// Cart keyed by product_id: { product_id: {product, quantity} }
  final Map<int, Map<String, dynamic>> _cart = {};
  int? _activeVendorId;
  Map<String, dynamic>? _activeVendor;

  /// Promo code entered on the vendor page, carried through to checkout.
  String? _pendingPromoCode;

  /// Latest delivery quote (distance/weight/fee/in_range) for the current cart
  /// and chosen drop location. Null until checkout fetches one.
  Map<String, dynamic>? _quote;
  bool _isQuoting = false;

  final Set<int> _favourites = {};

  List<Map<String, dynamic>> get vendors => _vendors;
  List<Map<String, dynamic>> get ads => _ads;
  List<Map<String, dynamic>> get deals => _deals;
  List<Map<String, dynamic>> get categories => _categories;
  bool get loading => _loading;
  String? get error => _error;
  Map<int, Map<String, dynamic>> get cart => _cart;
  int? get activeVendorId => _activeVendorId;
  Map<String, dynamic>? get activeVendor => _activeVendor;
  String? get pendingPromoCode => _pendingPromoCode;
  Map<String, dynamic>? get quote => _quote;
  bool get isQuoting => _isQuoting;
  Set<int> get favourites => _favourites;

  void toggleFavourite(int vendorId) {
    if (_favourites.contains(vendorId)) {
      _favourites.remove(vendorId);
    } else {
      _favourites.add(vendorId);
    }
    notifyListeners();
  }

  bool isFavourite(int vendorId) => _favourites.contains(vendorId);

  void setPromoCode(String? code) {
    final trimmed = code?.trim();
    _pendingPromoCode = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    notifyListeners();
  }

  int get cartCount => _cart.values.fold(0, (s, e) => s + (e['quantity'] as int));

  double get cartTotal => _cart.values.fold(
        0.0,
        (s, e) => s + ((e['product']['price'] as num).toDouble() * (e['quantity'] as int)),
      );

  Future<void> refreshVendors({double? lat, double? lng}) async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await ApiClient.instance.dio.get(
        '/market/vendors',
        queryParameters: {
          if (lat != null && lng != null) 'lat': lat,
          if (lat != null && lng != null) 'lng': lng,
        },
      );
      _vendors = List<Map<String, dynamic>>.from(resp.data as List);
    } on DioException {
      // ignore
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<List<Map<String, dynamic>>> fetchProducts(int vendorId) async {
    try {
      final resp = await ApiClient.instance.dio.get('/market/vendors/$vendorId/products');
      return List<Map<String, dynamic>>.from(resp.data as List);
    } on DioException {
      return [];
    }
  }

  int getQuantity(int productId) => (_cart[productId]?['quantity'] as int?) ?? 0;

  int vendorCartCount(int vendorId) {
    if (_activeVendorId != vendorId) return 0;
    return cartCount;
  }

  void setActiveVendor(Map<String, dynamic> vendor) {
    final vendorId = (vendor['id'] as num).toInt();
    if (_activeVendorId == vendorId) {
      _activeVendor = vendor;
      return;
    }
    if (_activeVendorId != null && _activeVendorId != vendorId) {
      _cart.clear();
      _pendingPromoCode = null;
      _activeVendor = null;
      _quote = null;
    }
    _activeVendorId = vendorId;
    _activeVendor = vendor;
    notifyListeners();
  }

  void addToCart(int vendorId, Map<String, dynamic> product, {Map<String, dynamic>? vendor}) {
    if (_activeVendorId != null && _activeVendorId != vendorId) {
      _cart.clear();
      _pendingPromoCode = null;
      _activeVendor = null;
      _quote = null;
    }
    _activeVendorId = vendorId;
    if (vendor != null) {
      _activeVendor = vendor;
    }
    final pid = (product['id'] as num).toInt();
    final existing = _cart[pid];
    _cart[pid] = {
      'product': product,
      'quantity': (existing?['quantity'] as int? ?? 0) + 1,
    };
    notifyListeners();
  }

  void setProductQty(int vendorId, Map<String, dynamic> product, int quantity, {Map<String, dynamic>? vendor}) {
    if (_activeVendorId != null && _activeVendorId != vendorId) {
      _cart.clear();
      _pendingPromoCode = null;
      _activeVendor = null;
      _quote = null;
    }
    _activeVendorId = vendorId;
    if (vendor != null) {
      _activeVendor = vendor;
    }
    final pid = (product['id'] as num).toInt();
    if (quantity <= 0) {
      _cart.remove(pid);
      if (_cart.isEmpty) {
        _activeVendorId = null;
        _activeVendor = null;
        _pendingPromoCode = null;
        _quote = null;
      }
    } else {
      _cart[pid] = {
        'product': product,
        'quantity': quantity,
      };
    }
    notifyListeners();
  }

  void changeQty(int productId, int delta) {
    final e = _cart[productId];
    if (e == null) return;
    final q = (e['quantity'] as int) + delta;
    if (q <= 0) {
      _cart.remove(productId);
    } else {
      _cart[productId] = {...e, 'quantity': q};
    }
    if (_cart.isEmpty) {
      _activeVendorId = null;
      _activeVendor = null;
      _pendingPromoCode = null;
      _quote = null;
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _activeVendorId = null;
    _activeVendor = null;
    _pendingPromoCode = null;
    _quote = null;
    notifyListeners();
  }

  /// Preview the distance+weight delivery fee for the current cart at a chosen
  /// drop location. Result is cached in [quote] so the checkout bill can show
  /// the exact fee and whether the address is `in_range` before placing.
  Future<Map<String, dynamic>?> quoteDelivery({
    required double lat,
    required double lng,
  }) async {
    if (_activeVendorId == null || _cart.isEmpty) {
      _quote = null;
      notifyListeners();
      return null;
    }
    final items = _cart.values
        .map((e) => {'product_id': (e['product'] as Map)['id'], 'quantity': e['quantity']})
        .toList();
    _isQuoting = true;
    _quote = null;
    notifyListeners();
    try {
      final resp = await ApiClient.instance.dio.post('/market/quote', data: {
        'vendor_id': _activeVendorId,
        'delivery_lat': lat,
        'delivery_lng': lng,
        'items': items,
      });
      _quote = Map<String, dynamic>.from(resp.data as Map);
      return _quote;
    } on DioException catch (e) {
      _error = e.response?.data?['detail']?.toString() ?? e.message;
      return null;
    } finally {
      _isQuoting = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> placeOrder({
    String? deliveryAddress,
    double? lat,
    double? lng,
    required String paymentMethod,
    String? instructions,
    // BRD: RW-02 / RW-04 — opt-in checkout discounts.
    int redeemPoints = 0,
    String? promoCode,
    bool isSelfPickup = false,
    double appUsageCharge = 0.0,
  }) async {
    if (_activeVendorId == null || _cart.isEmpty) return null;
    final items = _cart.values
        .map((e) => {'product_id': (e['product'] as Map)['id'], 'quantity': e['quantity']})
        .toList();
    try {
      final resp = await ApiClient.instance.dio.post('/market/orders', data: {
        'vendor_id': _activeVendorId,
        'items': items,
        if (deliveryAddress != null) 'delivery_address': deliveryAddress,
        if (lat != null) 'delivery_lat': lat,
        if (lng != null) 'delivery_lng': lng,
        'payment_method': paymentMethod,
        if (instructions != null && instructions.isNotEmpty)
          'instructions': instructions,
        if (redeemPoints > 0) 'redeem_points': redeemPoints,
        if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
        'is_self_pickup': isSelfPickup,
        'app_usage_charge': appUsageCharge,
      });
      clearCart();
      return Map<String, dynamic>.from(resp.data);
    } on DioException catch (e) {
      _error = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return null;
    }
  }

  Future<bool> completeOrder(int orderId) async {
    try {
      await ApiClient.instance.dio.post('/market/orders/$orderId/complete');
      return true;
    } on DioException catch (e) {
      _error = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> fetchMyOrders() async {
    try {
      final resp = await ApiClient.instance.dio.get('/market/orders');
      return List<Map<String, dynamic>>.from(resp.data as List);
    } on DioException {
      return [];
    }
  }

  Future<void> fetchAds({double? lat, double? lng}) async {
    try {
      final resp = await ApiClient.instance.dio.get(
        '/market/ads',
        queryParameters: {
          if (lat != null && lng != null) 'lat': lat,
          if (lat != null && lng != null) 'lng': lng,
        },
      );
      _ads = List<Map<String, dynamic>>.from(resp.data as List);
      notifyListeners();
    } on DioException {
      // ignore
    }
  }

  Future<void> fetchDeals() async {
    try {
      final resp = await ApiClient.instance.dio.get('/market/deals');
      _deals = List<Map<String, dynamic>>.from(resp.data as List);
      notifyListeners();
    } on DioException {
      // ignore
    }
  }

  Future<void> fetchCategories() async {
    try {
      final resp = await ApiClient.instance.dio.get('/market/categories');
      _categories = List<Map<String, dynamic>>.from(resp.data as List);
      notifyListeners();
    } on DioException {
      // ignore
    }
  }

  Future<Map<String, dynamic>?> fetchVendorById(int id) async {
    try {
      final resp = await ApiClient.instance.dio.get('/market/vendors/$id');
      return Map<String, dynamic>.from(resp.data as Map);
    } on DioException {
      return null;
    }
  }

  Future<bool> cancelOrder(int orderId, {String? reason}) async {
    try {
      await ApiClient.instance.dio.post(
        '/market/orders/$orderId/cancel',
        data: reason != null ? {'reason': reason} : null,
      );
      return true;
    } on DioException catch (e) {
      _error = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> rateOrder(int orderId, int rating, {String? feedback}) async {
    try {
      await ApiClient.instance.dio.post(
        '/market/orders/$orderId/rate',
        data: {
          'rating': rating,
          if (feedback != null && feedback.isNotEmpty) 'feedback': feedback,
        },
      );
      return true;
    } on DioException catch (e) {
      _error = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return false;
    }
  }
}
