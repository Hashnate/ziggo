import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

class AddressesProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = false;

  List<Map<String, dynamic>> get items => _items;
  bool get loading => _loading;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await ApiClient.instance.dio.get('/customer/addresses');
      _items = List<Map<String, dynamic>>.from(resp.data as List);
    } on DioException {
      // ignore
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> add({
    required String label,
    required String address,
    required double lat,
    required double lng,
    bool isDefault = false,
  }) async {
    try {
      await ApiClient.instance.dio.post('/customer/addresses', data: {
        'label': label,
        'address': address,
        'lat': lat,
        'lng': lng,
        'is_default': isDefault,
      });
      await refresh();
      return true;
    } on DioException {
      return false;
    }
  }

  Future<bool> remove(int id) async {
    try {
      await ApiClient.instance.dio.delete('/customer/addresses/$id');
      await refresh();
      return true;
    } on DioException {
      return false;
    }
  }
}
