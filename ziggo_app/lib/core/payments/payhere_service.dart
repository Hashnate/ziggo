// PayHere — Sri Lankan card + wallet gateway.
//
// Flow on the client:
//   1. probe /payments/payhere/config → enabled? otherwise caller falls back
//      to the mock /customer/wallet/topup path.
//   2. POST /payments/payhere/checkout {amount} → { url, fields, order_id }.
//   3. Open PayHereCheckoutScreen — a WebView that submits the signed form
//      to PayHere. The user pays inside the WebView.
//   4. PayHere redirects to our `return_url`. We catch the navigation, pop
//      the WebView, then poll /payments/payhere/status/{order_id}.
//   5. On 200 the wallet is credited and the caller refreshes the balance.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../network/api_client.dart';
import '../../modules/customer/screens/payhere_checkout_screen.dart';

class PayHereResult {
  final bool success;
  final String? orderId;
  final String? message;
  const PayHereResult({required this.success, this.orderId, this.message});

  factory PayHereResult.ok(String orderId) =>
      PayHereResult(success: true, orderId: orderId);
  factory PayHereResult.cancelled() =>
      const PayHereResult(success: false, message: 'Payment cancelled');
  factory PayHereResult.error(String msg) =>
      PayHereResult(success: false, message: msg);
}

class PayHereService {
  PayHereService._();
  static final PayHereService instance = PayHereService._();

  bool? _enabledCache;

  /// Cheap probe — caches per-process so the wallet screen can switch UIs
  /// without a network round-trip every time.
  Future<bool> isEnabled() async {
    if (_enabledCache != null) return _enabledCache!;
    try {
      final r = await ApiClient.instance.dio.get('/payments/payhere/config');
      _enabledCache = (r.data is Map) && r.data['enabled'] == true;
    } on DioException {
      _enabledCache = false;
    }
    return _enabledCache!;
  }

  /// Full top-up flow: launches the WebView, waits for the user to pay,
  /// then polls for backend confirmation. Returns when settled.
  Future<PayHereResult> topUpWallet(BuildContext context, double amount) async {
    if (amount < 100) {
      return PayHereResult.error('Minimum top-up is LKR 100');
    }
    // Step 1: start the checkout
    final Map<String, dynamic> session;
    try {
      final r = await ApiClient.instance.dio.post(
        '/payments/payhere/checkout',
        data: {
          'amount': amount,
          // The WebView watches for navigations to these URLs to detect end
          // of flow. Any URL works as long as they're unique-ish to us;
          // PayHere just redirects the browser, it doesn't care if they're
          // reachable.
          'return_url': 'https://ziggo.app/payhere/return',
          'cancel_url': 'https://ziggo.app/payhere/cancel',
        },
      );
      session = Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      return PayHereResult.error(
        e.response?.data?['detail']?.toString() ?? 'Failed to start checkout',
      );
    }

    final orderId = session['order_id']?.toString();
    final url = session['url']?.toString();
    final fields = (session['fields'] is Map)
        ? Map<String, dynamic>.from(session['fields'] as Map)
        : <String, dynamic>{};
    if (orderId == null || url == null || fields.isEmpty) {
      return PayHereResult.error('Malformed checkout response');
    }

    // Step 2: open WebView
    if (!context.mounted) return PayHereResult.cancelled();
    final bool? webResult = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PayHereCheckoutScreen(
          checkoutUrl: url,
          formFields: fields,
        ),
      ),
    );

    if (webResult != true) {
      return PayHereResult.cancelled();
    }

    // Step 3: poll for backend confirmation. The notify webhook may take a
    // few seconds to arrive; give it up to ~30s.
    for (int i = 0; i < 15; i++) {
      try {
        final r = await ApiClient.instance.dio.get(
          '/payments/payhere/status/$orderId',
        );
        if (r.statusCode == 200 && r.data != null) {
          return PayHereResult.ok(orderId);
        }
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          // Not yet credited — keep polling.
        } else {
          return PayHereResult.error(
            e.response?.data?['detail']?.toString() ?? 'Status check failed',
          );
        }
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    return PayHereResult.error(
      'Payment is taking longer than expected. Check the wallet shortly.',
    );
  }
}
