import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

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
