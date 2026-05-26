import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/payments/payhere_service.dart';

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

  /// Top up via PayHere (real card / wallet payment). Returns null on success
  /// (and refreshes the balance), or a user-facing error message on failure.
  ///
  /// Auto-falls back to the mock [topUp] endpoint when the server responds
  /// with HTTP 503 "PayHere not configured" — that way the demo flow keeps
  /// working until you paste merchant credentials into the server `.env`.
  Future<String?> topUpViaPayHere(double amount) async {
    final res = await PayHereService.instance.topUp(amount);
    if (res.paid) {
      await refresh();
      return null;
    }
    final err = res.error ?? 'Top-up failed';
    if (err.contains('not configured')) {
      // Dev fallback so the app stays usable before merchant onboarding.
      final ok = await topUp(amount, description: 'Wallet top-up (dev mock)');
      return ok ? null : 'Top-up failed';
    }
    return err;
  }
}
