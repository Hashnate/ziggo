import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

class WalletProvider extends ChangeNotifier {
  double _balance = 0;
  String _currency = 'LKR';
  List<Map<String, dynamic>> _transactions = const [];

  double get balance => _balance;
  String get currency => _currency;
  List<Map<String, dynamic>> get transactions => _transactions;

  Future<void> refresh() async {
    try {
      final resp = await ApiClient.instance.dio.get('/customer/wallet');
      _balance = (resp.data['balance'] as num).toDouble();
      _currency = resp.data['currency'] as String? ?? 'LKR';
      final tx = await ApiClient.instance.dio.get('/customer/wallet/transactions');
      _transactions = List<Map<String, dynamic>>.from(tx.data as List);
      notifyListeners();
    } on DioException {
      // swallow; UI will show last known balance
    }
  }

  Future<bool> topUp(double amount, {String? description}) async {
    try {
      await ApiClient.instance.dio.post(
        '/customer/wallet/topup',
        data: {'amount': amount, if (description != null) 'description': description},
      );
      await refresh();
      return true;
    } on DioException {
      return false;
    }
  }
}
