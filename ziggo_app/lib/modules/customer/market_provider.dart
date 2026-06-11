import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

class MarketProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _vendors = const [];
  List<Map<String, dynamic>> _ads = const [];
  bool _loading = false;
  String? _error;

  /// Cart keyed by product_id: { product_id: {product, quantity} }
  final Map<int, Map<String, dynamic>> _cart = {};
  int? _activeVendorId;

  /// Promo code entered on the vendor page, carried through to checkout.
  String? _pendingPromoCode;

  /// Latest delivery quote (distance/weight/fee/in_range) for the current cart
  /// and chosen drop location. Null until checkout fetches one.
  Map<String, dynamic>? _quote;

  List<Map<String, dynamic>> get vendors => _vendors;
  List<Map<String, dynamic>> get ads => _ads;
  bool get loading => _loading;
  String? get error => _error;
  Map<int, Map<String, dynamic>> get cart => _cart;
  int? get activeVendorId => _activeVendorId;
  String? get pendingPromoCode => _pendingPromoCode;
  Map<String, dynamic>? get quote => _quote;

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

  void addToCart(int vendorId, Map<String, dynamic> product) {
    if (_activeVendorId != null && _activeVendorId != vendorId) {
      _cart.clear();
      _pendingPromoCode = null;
    }
    _activeVendorId = vendorId;
    final pid = product['id'] as int;
    final existing = _cart[pid];
    _cart[pid] = {
      'product': product,
      'quantity': (existing?['quantity'] as int? ?? 0) + 1,
    };
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
    if (_cart.isEmpty) _activeVendorId = null;
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _activeVendorId = null;
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
    if (_activeVendorId == null || _cart.isEmpty) return null;
    final items = _cart.values
        .map((e) => {'product_id': (e['product'] as Map)['id'], 'quantity': e['quantity']})
        .toList();
    try {
      final resp = await ApiClient.instance.dio.post('/market/quote', data: {
        'vendor_id': _activeVendorId,
        'delivery_lat': lat,
        'delivery_lng': lng,
        'items': items,
      });
      _quote = Map<String, dynamic>.from(resp.data as Map);
      notifyListeners();
      return _quote;
    } on DioException catch (e) {
      _error = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, dynamic>?> placeOrder({
    required String deliveryAddress,
    required double lat,
    required double lng,
    String paymentMethod = 'cash',
    String? instructions,
    // BRD: RW-02 / RW-04 — opt-in checkout discounts.
    int redeemPoints = 0,
    String? promoCode,
  }) async {
    if (_activeVendorId == null || _cart.isEmpty) return null;
    final items = _cart.values
        .map((e) => {'product_id': (e['product'] as Map)['id'], 'quantity': e['quantity']})
        .toList();
    try {
      final resp = await ApiClient.instance.dio.post('/market/orders', data: {
        'vendor_id': _activeVendorId,
        'items': items,
        'delivery_address': deliveryAddress,
        'delivery_lat': lat,
        'delivery_lng': lng,
        'payment_method': paymentMethod,
        if (instructions != null && instructions.isNotEmpty)
          'instructions': instructions,
        if (redeemPoints > 0) 'redeem_points': redeemPoints,
        if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
      });
      clearCart();
      return Map<String, dynamic>.from(resp.data);
    } on DioException catch (e) {
      _error = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return null;
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
}
