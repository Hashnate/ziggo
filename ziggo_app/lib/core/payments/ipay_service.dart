// iPay — Sri Lankan card + wallet gateway.
//
// Flow on the client:
//   1. probe /payments/ipay/config → enabled? otherwise caller falls back
//      to the mock /customer/wallet/topup path.
//   2. POST /payments/ipay/checkout {amount} → { url, fields, order_id }.
//   3. Open IPayCheckoutScreen — a WebView that submits the signed form
//      to iPay. The user pays inside the WebView.
//   4. iPay redirects to our `return_url`. We catch the navigation, pop
//      the WebView, then poll /payments/ipay/status/{order_id}.
//   5. On 200 the wallet is credited and the caller refreshes the balance.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../../modules/customer/screens/ipay_checkout_screen.dart';

class IPayResult {
  final bool success;
  final String? orderId;
  final String? message;
  const IPayResult({required this.success, this.orderId, this.message});

  factory IPayResult.ok(String orderId) =>
      IPayResult(success: true, orderId: orderId);
  factory IPayResult.cancelled() =>
      const IPayResult(success: false, message: 'Payment cancelled');
  factory IPayResult.error(String msg) =>
      IPayResult(success: false, message: msg);
}

class IPayService {
  IPayService._();
  static final IPayService instance = IPayService._();

  bool? _enabledCache;

  /// Cheap probe — caches per-process so the wallet screen can switch UIs
  /// without a network round-trip every time.
  Future<bool> isEnabled() async {
    if (_enabledCache != null) return _enabledCache!;
    try {
      final r = await ApiClient.instance.dio.get('/payments/ipay/config');
      _enabledCache = (r.data is Map) && r.data['enabled'] == true;
    } on DioException {
      _enabledCache = false;
    }
    return _enabledCache!;
  }

  /// Full top-up flow: launches the WebView, waits for the user to pay,
  /// then polls for backend confirmation. Returns when settled.
  Future<IPayResult> topUpWallet(BuildContext context, double amount) async {
    if (amount < 100) {
      return IPayResult.error('Minimum top-up is LKR 100');
    }
    // Step 1: start the checkout
    final Map<String, dynamic> session;
    try {
      final r = await ApiClient.instance.dio.post(
        '/payments/ipay/checkout',
        data: {
          'amount': amount,
          'return_url': 'https://ziggo.app/ipay/return',
          'cancel_url': 'https://ziggo.app/ipay/cancel',
        },
      );
      session = Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      return IPayResult.error(
        e.response?.data?['detail']?.toString() ?? 'Failed to start checkout',
      );
    }

    final orderId = session['order_id']?.toString();
    final url = session['url']?.toString();
    final fields = (session['fields'] is Map)
        ? Map<String, dynamic>.from(session['fields'] as Map)
        : <String, dynamic>{};
    if (orderId == null || url == null || fields.isEmpty) {
      return IPayResult.error('Malformed checkout response');
    }

    // Step 2: open WebView
    if (!context.mounted) return IPayResult.cancelled();
    final bool? webResult = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => IPayCheckoutScreen(
          checkoutUrl: url,
          formFields: fields,
          title: 'Top Up with iPay',
        ),
      ),
    );

    if (webResult != true) {
      return IPayResult.cancelled();
    }

    // Step 3: poll for backend confirmation. The notify webhook may take a
    // few seconds to arrive; give it up to ~30s.
    for (int i = 0; i < 15; i++) {
      try {
        final r = await ApiClient.instance.dio.get(
          '/payments/ipay/status/$orderId',
        );
        if (r.statusCode == 200 && r.data != null) {
          return IPayResult.ok(orderId);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          // Not yet credited — keep polling.
        } else {
          return IPayResult.error(
            e.response?.data?['detail']?.toString() ?? 'Status check failed',
          );
        }
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    return IPayResult.error(
      'Payment is taking longer than expected. Check the wallet shortly.',
    );
  }
}
