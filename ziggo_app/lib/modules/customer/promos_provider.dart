import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

/// The admin's conditions on a promo, as short phrases for chips and summaries.
List<String> promoRules(Map<String, dynamic> p) {
  final rules = <String>[];
  final min = p['min_order_amount'] as num?;
  if (min != null && min > 0) rules.add('Min Rs.${min.toStringAsFixed(0)}');
  final vehicles = (p['vehicle_types'] as List?)?.map((v) => v.toString()).toList() ?? const <String>[];
  if (vehicles.isNotEmpty) rules.add('${vehicles.join(', ')} only');
  final perCustomer = (p['per_customer_limit'] as num?)?.toInt();
  if (perCustomer != null) {
    rules.add(perCustomer == 1 ? 'Once per customer' : '$perCustomer uses per customer');
  }
  if (p['new_customers_only'] == true) rules.add('New customers only');
  return rules;
}

/// Promo inbox + loyalty balance state (BRD: RW-01 + RW-04).
class PromosProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _items = const [];
  Map<String, dynamic> _loyalty = const {};
  String _category = 'all';  // 'all' | 'rides' | 'food' | 'market'
  bool _onlyClaimed = false;
  bool _loading = false;

  List<Map<String, dynamic>> get items => _items;
  Map<String, dynamic> get loyalty => _loyalty;
  String get category => _category;
  bool get onlyClaimed => _onlyClaimed;
  bool get loading => _loading;

  int get points => (_loyalty['points'] as num?)?.toInt() ?? 0;
  double get pointsValue => (_loyalty['value'] as num?)?.toDouble() ?? 0;
  bool get isLoyaltyActive => _loyalty['loyalty_is_active'] == true;

  set category(String c) {
    if (_category == c) return;
    _category = c;
    refresh();
  }

  set onlyClaimed(bool v) {
    if (_onlyClaimed == v) return;
    _onlyClaimed = v;
    refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final q = <String, dynamic>{
        if (_category != 'all') 'category': _category,
        if (_onlyClaimed) 'only_claimed': true,
      };
      final resp = await ApiClient.instance.dio.get('/promos', queryParameters: q);
      _items = List<Map<String, dynamic>>.from(resp.data as List);
    } on DioException {
      // ignore
    }
    try {
      final r = await ApiClient.instance.dio.get('/loyalty/balance');
      _loyalty = Map<String, dynamic>.from(r.data as Map);
    } on DioException {
      // ignore — endpoint may 403 if user isn't a customer
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Whether [code] applies to an order worth [amount] (before discounts) at a
  /// checkout without a server quote: category is food | market | events.
  /// The reply has `applies`, `discount_amount` and the server's `message`
  /// when it doesn't apply; null if the check couldn't be made.
  Future<Map<String, dynamic>?> check(String code, String category, double amount) async {
    try {
      final r = await ApiClient.instance.dio.post('/promos/check', data: {
        'code': code,
        'category': category,
        'amount': amount,
      });
      return Map<String, dynamic>.from(r.data as Map);
    } on DioException {
      return null;
    }
  }

  Future<bool> claim(int promoId) async {
    try {
      await ApiClient.instance.dio.post('/promos/$promoId/claim');
      // Optimistic local update
      final i = _items.indexWhere((p) => p['id'] == promoId);
      if (i >= 0) {
        _items[i] = {..._items[i], 'claimed_at': DateTime.now().toUtc().toIso8601String()};
        notifyListeners();
      }
      return true;
    } on DioException {
      return false;
    }
  }

  Future<bool> unclaim(int promoId) async {
    try {
      await ApiClient.instance.dio.delete('/promos/$promoId/claim');
      final i = _items.indexWhere((p) => p['id'] == promoId);
      if (i >= 0) {
        final m = Map<String, dynamic>.from(_items[i]);
        m.remove('claimed_at');
        _items[i] = m;
        if (_onlyClaimed) _items.removeAt(i);
        notifyListeners();
      }
      return true;
    } on DioException {
      return false;
    }
  }
}
