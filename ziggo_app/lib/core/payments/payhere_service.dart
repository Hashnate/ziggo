import 'dart:async';

import 'package:dio/dio.dart';
import 'package:payhere_mobilesdk_flutter/payhere_mobilesdk_flutter.dart';

import '../network/api_client.dart';

/// Result of a single PayHere checkout attempt.
class PayHereResult {
  final bool completed;       // user finished the sheet (does NOT mean paid)
  final bool paid;            // server confirms `status == "completed"`
  final String? orderId;
  final String? error;        // user-facing reason if anything went wrong

  const PayHereResult({
    required this.completed,
    required this.paid,
    this.orderId,
    this.error,
  });

  static const PayHereResult dismissed =
      PayHereResult(completed: false, paid: false, error: 'Cancelled');
}

/// Thin wrapper around the PayHere native SDK.
///
/// Flow:
///   1. Ask our backend to build a signed checkout payload (server holds the
///      merchant secret — never the app).
///   2. Hand the payload to the PayHere SDK which opens the native sheet.
///   3. After the sheet closes, poll `/payments/payhere/status/{order_id}`
///      until it flips to `completed` (the PayHere webhook is the source of
///      truth — the SDK's own success callback is just a UI hint).
class PayHereService {
  PayHereService._();
  static final PayHereService instance = PayHereService._();

  /// Top up the customer wallet by [amountLkr].
  Future<PayHereResult> topUp(double amountLkr) {
    return _start(
      endpoint: '/payments/payhere/topup/init',
      body: {'amount': amountLkr},
    );
  }

  /// Pay an existing booking by card. Backend picks the right amount column
  /// (final_amount if the trip has settled, fare_amount otherwise).
  Future<PayHereResult> payBooking(int bookingId) {
    return _start(
      endpoint: '/payments/payhere/booking/init',
      body: {'booking_id': bookingId},
    );
  }

  /// Pay an existing food order by card.
  Future<PayHereResult> payFoodOrder(int orderId) {
    return _start(
      endpoint: '/payments/payhere/food/init',
      body: {'order_id': orderId},
    );
  }

  /// Pay an existing market order by card.
  Future<PayHereResult> payMarketOrder(int orderId) {
    return _start(
      endpoint: '/payments/payhere/market/init',
      body: {'order_id': orderId},
    );
  }

  /// Buy Ziggo Gold membership ([months] = 1, 3, 6, or 12).
  Future<PayHereResult> payGoldSubscription(int months) {
    return _start(
      endpoint: '/payments/payhere/gold/init',
      body: {'months': months},
    );
  }

  Future<PayHereResult> _start({
    required String endpoint,
    required Map<String, dynamic> body,
  }) async {
    // 1. Backend builds the signed payload.
    Map<String, dynamic> initResp;
    try {
      final r = await ApiClient.instance.dio.post(endpoint, data: body);
      initResp = Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      final detail = e.response?.data?['detail']?.toString();
      return PayHereResult(
        completed: false,
        paid: false,
        error: detail ?? 'Could not start payment',
      );
    }
    final orderId = initResp['order_id'] as String;
    final paymentObject = Map<String, dynamic>.from(initResp['payhere'] as Map);

    // 2. Launch the native sheet. PayHere.startPayment uses callbacks (not
    //    a Future) so wrap in a Completer. Guard against the SDK firing more
    //    than one callback (it has been known to call both error + dismiss).
    final completer = Completer<_SheetOutcome>();
    void finish(_SheetOutcome o) {
      if (!completer.isCompleted) completer.complete(o);
    }
    PayHere.startPayment(
      paymentObject,
      (paymentId) => finish(_SheetOutcome.success(paymentId.toString())),
      (error) => finish(_SheetOutcome.failure(error.toString())),
      () => finish(_SheetOutcome.dismissed()),
    );
    final sheet = await completer.future;
    if (sheet.dismissed) return PayHereResult.dismissed;
    if (!sheet.success) {
      return PayHereResult(
        completed: true, paid: false,
        orderId: orderId,
        error: sheet.error ?? 'Payment failed',
      );
    }

    // 3. The webhook lands on the server "any moment now" — poll for up to
    //    20 s. If it never flips, ask the user to refresh later.
    for (var i = 0; i < 10; i++) {
      try {
        final s = await ApiClient.instance.dio
            .get('/payments/payhere/status/$orderId');
        final status = s.data['status']?.toString() ?? '';
        if (status == 'completed') {
          return PayHereResult(completed: true, paid: true, orderId: orderId);
        }
        if (status == 'failed' || status == 'cancelled') {
          return PayHereResult(
            completed: true, paid: false,
            orderId: orderId,
            error: 'Payment $status',
          );
        }
      } on DioException {
        // ignore and retry
      }
      await Future.delayed(const Duration(seconds: 2));
    }
    return PayHereResult(
      completed: true, paid: false, orderId: orderId,
      error: 'Still processing. Refresh your wallet in a minute.',
    );
  }
}

class _SheetOutcome {
  final bool success;
  final bool dismissed;
  final String? paymentId;
  final String? error;
  const _SheetOutcome._({
    this.success = false,
    this.dismissed = false,
    this.paymentId,
    this.error,
  });
  factory _SheetOutcome.success(String id) =>
      _SheetOutcome._(success: true, paymentId: id);
  factory _SheetOutcome.failure(String err) =>
      _SheetOutcome._(success: false, error: err);
  factory _SheetOutcome.dismissed() => const _SheetOutcome._(dismissed: true);
}
