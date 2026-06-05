import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/payments/payhere_service.dart';
import 'screens/payhere_checkout_screen.dart';

class PaymentMethodsProvider extends ChangeNotifier {
  Map<String, dynamic>? _corporateProfile;
  List<Map<String, dynamic>> _cards = [];
  bool _isLoading = false;

  List<Map<String, dynamic>> get cards => _cards;
  Map<String, dynamic>? get corporateProfile => _corporateProfile;
  bool get isLoading => _isLoading;

  Future<void> fetchCards() async {
    _isLoading = true;
    notifyListeners();
    try {
      final r = await ApiClient.instance.dio.get('/payments/methods');
      _cards = List<Map<String, dynamic>>.from(r.data as List);
    } on DioException {
      // swallow
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchCorporateProfile() async {
    try {
      final r = await ApiClient.instance.dio.get('/corporate/profile');
      _corporateProfile = Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        _corporateProfile = null;
      }
    } finally {
      notifyListeners();
    }
  }

  Future<String?> addCardViaPayHere(BuildContext context) async {
    final enabled = await PayHereService.instance.isEnabled();
    if (!enabled) {
      _isLoading = true;
      notifyListeners();
      try {
        await ApiClient.instance.dio.post('/payments/methods/mock');
        await fetchCards();
        return null;
      } on DioException catch (e) {
        return e.response?.data?['detail']?.toString() ?? 'Failed to add mock card';
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }

    final Map<String, dynamic> session;
    try {
      final r = await ApiClient.instance.dio.post(
        '/payments/payhere/preapprove',
        data: {
          'return_url': 'https://ziggo.app/payhere/return',
          'cancel_url': 'https://ziggo.app/payhere/cancel',
        },
      );
      session = Map<String, dynamic>.from(r.data as Map);
    } on DioException catch (e) {
      return e.response?.data?['detail']?.toString() ?? 'Failed to start authorization';
    }

    final orderId = session['order_id']?.toString();
    final url = session['url']?.toString();
    final fields = (session['fields'] is Map)
        ? Map<String, dynamic>.from(session['fields'] as Map)
        : <String, dynamic>{};
    if (orderId == null || url == null || fields.isEmpty) {
      return 'Malformed pre-approval response';
    }

    if (!context.mounted) return 'cancelled';
    final bool? webResult = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PayHereCheckoutScreen(
          checkoutUrl: url,
          formFields: fields,
        ),
      ),
    );

    if (webResult != true) {
      return 'Authorization cancelled';
    }

    _isLoading = true;
    notifyListeners();
    
    final int oldLength = _cards.length;
    for (int i = 0; i < 8; i++) {
      await Future.delayed(const Duration(seconds: 1));
      try {
        final r = await ApiClient.instance.dio.get('/payments/methods');
        final currentCards = List<Map<String, dynamic>>.from(r.data as List);
        if (currentCards.length > oldLength) {
          _cards = currentCards;
          _isLoading = false;
          notifyListeners();
          return null; 
        }
      } on DioException {
        // ignore
      }
    }
    
    await fetchCards();
    return null;
  }

  Future<bool> setAsDefault(int cardId) async {
    try {
      await ApiClient.instance.dio.post('/payments/methods/$cardId/default');
      await fetchCards();
      return true;
    } on DioException {
      return false;
    }
  }

  Future<bool> deleteCard(int cardId) async {
    try {
      await ApiClient.instance.dio.delete('/payments/methods/$cardId');
      await fetchCards();
      return true;
    } on DioException {
      return false;
    }
  }
}
