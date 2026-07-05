import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

class FoodProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _restaurants = const [];
  bool _loading = false;
  String? _error;

  // Admin-managed home layout (from GET /food/home).
  List<Map<String, dynamic>> _banners = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _collections = const [];
  List<Map<String, dynamic>> _deals = const [];

  // Active home-screen filters (tap a category/collection chip).
  int? _selectedCategoryId;
  int? _selectedCollectionId;

  // Favorited restaurant ids (overlaid onto restaurant cards).
  final Set<int> _favoriteIds = {};

  // Active delivery location — drives nearest-first sorting and prefills checkout.
  String? _deliveryLabel;
  String? _deliverySubtitle;
  double? _deliveryLat;
  double? _deliveryLng;

  // Active search query for filtering restaurants/menu items
  String _searchQuery = '';

  /// Cart keyed by menu_item_id: { menu_item_id: {item, quantity} }
  final Map<int, Map<String, dynamic>> _cart = {};
  int? _activeRestaurantId;
  Map<String, dynamic>? _activeRestaurant;

  List<Map<String, dynamic>> get restaurants => _restaurants;
  bool get loading => _loading;
  String? get error => _error;
  List<Map<String, dynamic>> get banners => _banners;
  List<Map<String, dynamic>> get categories => _categories;
  List<Map<String, dynamic>> get collections => _collections;
  List<Map<String, dynamic>> get deals => _deals;
  int? get selectedCategoryId => _selectedCategoryId;
  int? get selectedCollectionId => _selectedCollectionId;
  String? get deliveryLabel => _deliveryLabel;
  String? get deliverySubtitle => _deliverySubtitle;
  double? get deliveryLat => _deliveryLat;
  double? get deliveryLng => _deliveryLng;
  Map<int, Map<String, dynamic>> get cart => _cart;
  int? get activeRestaurantId => _activeRestaurantId;
  Map<String, dynamic>? get activeRestaurant => _activeRestaurant;
  String get searchQuery => _searchQuery;

  bool isFavorite(int id) => _favoriteIds.contains(id);

  int get cartCount => _cart.values.fold(0, (s, e) => s + (e['quantity'] as int));

  double get cartTotal => _cart.values.fold(
        0.0,
        (s, e) => s + ((e['item']['price'] as num).toDouble() * (e['quantity'] as int)),
      );

  List<Map<String, dynamic>> _asList(dynamic raw) =>
      List<Map<String, dynamic>>.from(
        (raw as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
      );

  /// Fetch the admin-configured home layout (banners, categories, collections,
  /// deals) in one round-trip. Keeps the previous layout on transient failure.
  Future<void> fetchHome() async {
    try {
      final resp = await ApiClient.instance.dio.get('/food/home');
      final data = Map<String, dynamic>.from(resp.data as Map);
      _banners = _asList(data['banners']);
      _categories = _asList(data['categories']);
      _collections = _asList(data['collections']);
      _deals = _asList(data['deals']);
      notifyListeners();
    } on DioException {
      // ignore — keep whatever we have
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
    fetchRestaurants();
  }

  void setDeliveryLocation({
    required String label,
    String? subtitle,
    required double lat,
    required double lng,
  }) {
    _deliveryLabel = label;
    _deliverySubtitle = subtitle;
    _deliveryLat = lat;
    _deliveryLng = lng;
    notifyListeners();
    fetchRestaurants();
  }

  /// Toggle a category filter (tapping the active one clears it). Mutually
  /// exclusive with the collection filter.
  Future<void> setCategoryFilter(int? categoryId) async {
    _selectedCategoryId = (_selectedCategoryId == categoryId) ? null : categoryId;
    _selectedCollectionId = null;
    notifyListeners();
    await fetchRestaurants();
  }

  Future<void> setCollectionFilter(int? collectionId) async {
    _selectedCollectionId = (_selectedCollectionId == collectionId) ? null : collectionId;
    _selectedCategoryId = null;
    notifyListeners();
    await fetchRestaurants();
  }

  Future<void> fetchRestaurants() async {
    _loading = true;
    notifyListeners();
    try {
      final qp = <String, dynamic>{};
      if (_selectedCategoryId != null) qp['category_id'] = _selectedCategoryId;
      if (_selectedCollectionId != null) qp['collection_id'] = _selectedCollectionId;
      if (_deliveryLat != null && _deliveryLng != null) {
        qp['lat'] = _deliveryLat;
        qp['lng'] = _deliveryLng;
      }
      if (_searchQuery.trim().isNotEmpty) {
        qp['q'] = _searchQuery.trim();
      }
      final resp = await ApiClient.instance.dio.get(
        '/food/restaurants',
        queryParameters: qp.isEmpty ? null : qp,
      );
      _restaurants = _asList(resp.data);
    } on DioException {
      // ignore
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> fetchFavorites() async {
    try {
      final resp = await ApiClient.instance.dio.get('/food/favorites');
      _favoriteIds
        ..clear()
        ..addAll((resp.data as List).map((e) => (e['id'] as num).toInt()));
      notifyListeners();
    } on DioException {
      // ignore (e.g. not authenticated yet)
    }
  }

  Future<void> toggleFavorite(int restaurantId) async {
    final wasFav = _favoriteIds.contains(restaurantId);
    if (wasFav) {
      _favoriteIds.remove(restaurantId);
    } else {
      _favoriteIds.add(restaurantId);
    }
    notifyListeners();
    try {
      if (wasFav) {
        await ApiClient.instance.dio.delete('/food/favorites/$restaurantId');
      } else {
        await ApiClient.instance.dio.post('/food/favorites/$restaurantId');
      }
    } on DioException {
      // rollback on failure
      if (wasFav) {
        _favoriteIds.add(restaurantId);
      } else {
        _favoriteIds.remove(restaurantId);
      }
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

  Map<String, dynamic>? _quote;
  Map<String, dynamic>? get quote => _quote;

  void clearCart() {
    _cart.clear();
    _activeRestaurantId = null;
    _activeRestaurant = null;
    _quote = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> quoteDelivery({
    required double lat,
    required double lng,
  }) async {
    if (_activeRestaurantId == null || _cart.isEmpty) return null;
    try {
      final resp = await ApiClient.instance.dio.post('/food/quote', data: {
        'restaurant_id': _activeRestaurantId,
        'delivery_lat': lat,
        'delivery_lng': lng,
        'items': _cart.values.map((e) => {
          'menu_item_id': (e['item'] as Map)['id'],
          'quantity': e['quantity'],
        }).toList(),
      });
      _quote = Map<String, dynamic>.from(resp.data as Map);
      notifyListeners();
      return _quote;
    } on DioException catch (e) {
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

  Future<bool> cancelOrder(int orderId, {String? reason}) async {
    try {
      await ApiClient.instance.dio.post(
        '/food/orders/$orderId/cancel',
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
        '/food/orders/$orderId/rate',
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
