import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

class NotificationsProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _items = const [];
  bool _loading = false;

  List<Map<String, dynamic>> get items => _items;
  bool get loading => _loading;
  int get unreadCount => _items.where((n) => n['is_read'] != true).length;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await ApiClient.instance.dio.get('/customer/notifications');
      _items = List<Map<String, dynamic>>.from(resp.data as List);
    } on DioException {
      // ignore
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(int id) async {
    final idx = _items.indexWhere((n) => n['id'] == id);
    if (idx != -1 && _items[idx]['is_read'] != true) {
      _items = _items
          .map((n) => n['id'] == id ? {...n, 'is_read': true} : n)
          .toList();
      notifyListeners();
    }
    try {
      await ApiClient.instance.dio.post('/customer/notifications/$id/read');
    } on DioException {
      try {
        await ApiClient.instance.dio.post('/driver/notifications/$id/read');
      } catch (_) {}
    }
  }

  Future<void> markAllAsRead() async {
    final unreads = _items.where((n) => n['is_read'] != true).toList();
    if (unreads.isEmpty) return;
    _items = _items.map((n) => {...n, 'is_read': true}).toList();
    notifyListeners();
    try {
      await ApiClient.instance.dio.post('/customer/notifications/read-all');
    } on DioException {
      try {
        await ApiClient.instance.dio.post('/driver/notifications/read-all');
      } catch (_) {
        for (final n in unreads) {
          final id = n['id'] as int;
          try {
            await ApiClient.instance.dio.post('/customer/notifications/$id/read');
          } catch (_) {}
        }
      }
    }
  }
}
