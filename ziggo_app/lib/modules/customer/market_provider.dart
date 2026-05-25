import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

class MarketProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _vendors = const [];
  bool _loading = false;
  String? _error;

  /// Cart keyed by product_id: { product_id: {product, quantity} }
  final Map<int, Map<String, dynamic>> _cart = {};
  int? _activeVendorId;

  List<Map<String, dynamic>> get vendors => _vendors;
  bool get loading => _loading;
  String? get error => _error;
  Map<int, Map<String, dynamic>> get cart => _cart;
  int? get activeVendorId => _activeVendorId;

  int get cartCount => _cart.values.fold(0, (s, e) => s + (e['quantity'] as int));

  double get cartTotal => _cart.values.fold(
        0.0,
        (s, e) => s + ((e['product']['price'] as num).toDouble() * (e['quantity'] as int)),
      );

  Future<void> refreshVendors() async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await ApiClient.instance.dio.get('/market/vendors');
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
    notifyListeners();
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
}
