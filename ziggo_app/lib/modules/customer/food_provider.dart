import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

class FoodProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _restaurants = const [];
  bool _loading = false;
  String? _error;

  /// Cart keyed by menu_item_id: { menu_item_id: {item, quantity} }
  final Map<int, Map<String, dynamic>> _cart = {};
  int? _activeRestaurantId;
  Map<String, dynamic>? _activeRestaurant;

  List<Map<String, dynamic>> get restaurants => _restaurants;
  bool get loading => _loading;
  String? get error => _error;
  Map<int, Map<String, dynamic>> get cart => _cart;
  int? get activeRestaurantId => _activeRestaurantId;
  Map<String, dynamic>? get activeRestaurant => _activeRestaurant;

  int get cartCount => _cart.values.fold(0, (s, e) => s + (e['quantity'] as int));

  double get cartTotal => _cart.values.fold(
        0.0,
        (s, e) => s + ((e['item']['price'] as num).toDouble() * (e['quantity'] as int)),
      );

  Future<void> fetchRestaurants() async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await ApiClient.instance.dio.get('/food/restaurants');
      _restaurants = List<Map<String, dynamic>>.from(resp.data as List);
    } on DioException {
      // ignore
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> fetchRestaurantDetail(int restaurantId) async {
    try {
      final resp = await ApiClient.instance.dio.get('/food/restaurants/$restaurantId');
      return Map<String, dynamic>.from(resp.data);
    } on DioException {
      return null;
    }
  }

  void setActiveRestaurant(Map<String, dynamic> restaurant) {
    if (_activeRestaurantId != null && _activeRestaurantId != restaurant['id']) {
      _cart.clear();
    }
    _activeRestaurantId = restaurant['id'] as int;
    _activeRestaurant = restaurant;
    notifyListeners();
  }

  void addToCart(Map<String, dynamic> item) {
    final id = item['id'] as int;
    final existing = _cart[id];
    _cart[id] = {
      'item': item,
      'quantity': (existing?['quantity'] as int? ?? 0) + 1,
    };
    notifyListeners();
  }

  void changeQty(int itemId, int delta) {
    final e = _cart[itemId];
    if (e == null) return;
    final q = (e['quantity'] as int) + delta;
    if (q <= 0) {
      _cart.remove(itemId);
    } else {
      _cart[itemId] = {...e, 'quantity': q};
    }
    if (_cart.isEmpty) {
      _activeRestaurantId = null;
      _activeRestaurant = null;
    }
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _activeRestaurantId = null;
    _activeRestaurant = null;
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
    if (_activeRestaurantId == null || _cart.isEmpty) return null;
    final items = _cart.values
        .map((e) => {
              'menu_item_id': (e['item'] as Map)['id'],
              'quantity': e['quantity'],
            })
        .toList();
    try {
      final resp = await ApiClient.instance.dio.post('/food/orders', data: {
        'restaurant_id': _activeRestaurantId,
        'items': items,
        'delivery_address': deliveryAddress,
        'delivery_lat': lat,
        'delivery_lng': lng,
        'payment_method': paymentMethod,
        if (instructions != null && instructions.isNotEmpty) 'instructions': instructions,
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
      final resp = await ApiClient.instance.dio.get('/food/orders');
      return List<Map<String, dynamic>>.from(resp.data as List);
    } on DioException {
      return [];
    }
  }
}
