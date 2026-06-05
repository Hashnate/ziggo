import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  /// Real-money top-up via PayHere. Returns null on success, an error string
  /// on failure (so the caller can show it). When PayHere isn't configured
  /// on the backend, transparently falls back to the mock direct-credit
  /// `topUp()` above — same UX, same result, no real money moves.
  Future<String?> topUpViaPayHere(BuildContext context, double amount) async {
    final enabled = await PayHereService.instance.isEnabled();
    if (!enabled) {
      final ok = await topUp(amount, description: 'Wallet top-up (mock)');
      return ok ? null : 'Failed to top up wallet';
    }
    final result = await PayHereService.instance.topUpWallet(context, amount);
    if (result.success) {
      await refresh();
      return null;
    }
    return result.message ?? 'Payment failed';
  }

  Future<Map<String, dynamic>?> resolveQrCode(String payload) async {
    try {
      final resp = await ApiClient.instance.dio.post(
        '/payments/qr/resolve',
        data: {'payload': payload},
      );
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['detail'] ?? 'Failed to resolve QR code';
      throw Exception(errorMsg);
    }
  }

  Future<Map<String, dynamic>> payMerchant(
      String merchantType, int merchantId, double amount) async {
    try {
      final resp = await ApiClient.instance.dio.post(
        '/payments/qr/pay',
        data: {
          'merchant_type': merchantType,
          'merchant_id': merchantId,
          'amount': amount,
        },
      );
      await refresh();
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      final errorMsg = e.response?.data?['detail'] ?? 'Failed to execute payment';
      throw Exception(errorMsg);
    }
  }
}

