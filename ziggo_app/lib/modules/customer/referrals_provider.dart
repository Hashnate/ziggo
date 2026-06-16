import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';

class ReferralsProvider extends ChangeNotifier {
  String _referralCode = '';
  int _totalReferred = 0;
  double _earnedAmount = 0.0;
  double _pendingAmount = 0.0;
  List<Map<String, dynamic>> _friends = const [];
  bool _loading = false;

  String get referralCode => _referralCode;
  int get totalReferred => _totalReferred;
  double get earnedAmount => _earnedAmount;
  double get pendingAmount => _pendingAmount;
  List<Map<String, dynamic>> get friends => _friends;
  bool get loading => _loading;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      final resp = await ApiClient.instance.dio.get('/customer/referrals');
      final data = resp.data;
      _referralCode = data['referral_code'] as String? ?? '';
      _totalReferred = data['total_referred'] as int? ?? 0;
      _earnedAmount = (data['earned_amount'] as num?)?.toDouble() ?? 0.0;
      _pendingAmount = (data['pending_amount'] as num?)?.toDouble() ?? 0.0;
      _friends = List<Map<String, dynamic>>.from(data['friends'] as List? ?? []);
    } on DioException {
      // swallow; UI will show last known state
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> applyReferralCode(String code) async {
    try {
      await ApiClient.instance.dio.patch('/customer/profile', data: {
        'referred_by_code': code.trim().toUpperCase(),
      });
      return true;
    } on DioException {
      return false;
    }
  }
}
