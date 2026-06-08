import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/notifications/fcm_service.dart';
import '../../core/storage/token_storage.dart';

enum AuthStatus { unauthenticated, authenticating, authenticated, error }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unauthenticated;
  String? _token;
  String? _role;
  int? _userId;
  String? _phoneNumber;
  String? _fullName;
  String? _email;
  String? _birthday;
  String? _gender;
  String? _language;
  String? _emergencyContactName;
  String? _emergencyContactNumber;
  String? _lastError;
  String? _devOtp;

  AuthStatus get status => _status;
  String? get token => _token;
  String? get role => _role;
  int? get userId => _userId;
  String? get phoneNumber => _phoneNumber;
  String? get fullName => _fullName;
  String? get email => _email;
  String? get birthday => _birthday;
  String? get gender => _gender;
  String? get language => _language;
  String? get emergencyContactName => _emergencyContactName;
  String? get emergencyContactNumber => _emergencyContactNumber;
  String? get lastError => _lastError;
  String? get devOtp => _devOtp;

  Future<void> bootstrap() async {
    final t = await TokenStorage.getToken();
    final r = await TokenStorage.getRole();
    final uid = await TokenStorage.getUserId();
    if (t != null && r != null) {
      _token = t;
      _role = r;
      _userId = uid;
      _status = AuthStatus.authenticated;
      notifyListeners();
      await _refreshMe();
    }
  }

  Future<bool> sendOTP(String phoneNumber) async {
    _lastError = null;
    try {
      final resp = await ApiClient.instance.dio.post(
        '/auth/send-otp',
        data: {'phone_number': phoneNumber},
      );
      _devOtp = resp.data['dev_otp'] as String?;
      _phoneNumber = phoneNumber;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> verifyOTP(
    String phoneNumber,
    String otp,
    String role, {
    String? fullName,
  }) async {
    _status = AuthStatus.authenticating;
    _lastError = null;
    notifyListeners();

    try {
      final resp = await ApiClient.instance.dio.post(
        '/auth/verify-otp',
        data: {
          'phone_number': phoneNumber,
          'otp': otp,
          'role': role,
          if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
        },
      );
      _token = resp.data['access_token'] as String;
      _role = resp.data['role'] as String;
      _userId = resp.data['user_id'] as int;
      _phoneNumber = phoneNumber;
      await TokenStorage.save(token: _token!, role: _role!, userId: _userId!);

      _status = AuthStatus.authenticated;
      notifyListeners();
      await _refreshMe();

      // Push the FCM token to the backend now that the JWT is set so realtime
      // events also arrive via Firebase when the WebSocket is unavailable
      // (app backgrounded, phone asleep). Fire-and-forget — no-op if
      // Firebase isn't configured on this build.
      unawaited(FcmService.instance.registerWithBackend());

      return true;
    } on DioException catch (e) {
      _lastError = e.response?.data?['detail']?.toString() ?? e.message;
      _status = AuthStatus.error;
      notifyListeners();
      return false;
    }
  }

  // BRD: CD-34 — profile completeness {percent, completed[], missing[]}
  Map<String, dynamic>? _completeness;
  Map<String, dynamic>? get completeness => _completeness;

  Future<void> _refreshMe() async {
    try {
      final resp = await ApiClient.instance.dio.get('/auth/me');
      _fullName = resp.data['full_name'] as String?;
      _email = resp.data['email'] as String?;
      _phoneNumber = resp.data['phone_number'] as String?;
      _birthday = resp.data['birthday'] as String?;
      _gender = resp.data['gender'] as String?;
      _language = resp.data['language'] as String?;
      _emergencyContactName = resp.data['emergency_contact_name'] as String?;
      _emergencyContactNumber = resp.data['emergency_contact_number'] as String?;
      _completeness = resp.data['profile_completeness'] is Map
          ? Map<String, dynamic>.from(resp.data['profile_completeness'] as Map)
          : null;
      notifyListeners();
    } catch (_) {}
  }

  /// BRD: CD-32 — Delete the current account. Returns the human-readable
  /// erasure-notice text from the server, which the UI should show before
  /// signing the user out.
  Future<String?> deleteAccount() async {
    try {
      final r = await ApiClient.instance.dio.delete('/customer/me');
      final msg = (r.data is Map) ? (r.data['message']?.toString()) : null;
      await logout();
      return msg ?? 'Account deleted.';
    } on DioException catch (e) {
      return null;
    }
  }

  Future<void> updateProfile({
    String? fullName,
    String? email,
    String? birthday,
    String? gender,
    String? language,
    String? emergencyContactName,
    String? emergencyContactNumber,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (email != null) body['email'] = email;
    if (birthday != null) body['birthday'] = birthday;
    if (gender != null) body['gender'] = gender;
    if (language != null) body['language'] = language;
    if (emergencyContactName != null) body['emergency_contact_name'] = emergencyContactName;
    if (emergencyContactNumber != null) body['emergency_contact_number'] = emergencyContactNumber;
    
    if (body.isEmpty) return;
    final resp = await ApiClient.instance.dio.patch('/customer/profile', data: body);
    _fullName = resp.data['full_name'] as String?;
    _email = resp.data['email'] as String?;
    _birthday = resp.data['birthday'] as String?;
    _gender = resp.data['gender'] as String?;
    _language = resp.data['language'] as String?;
    _emergencyContactName = resp.data['emergency_contact_name'] as String?;
    _emergencyContactNumber = resp.data['emergency_contact_number'] as String?;
    notifyListeners();
  }

  Future<void> logout() async {
    // Unregister the FCM token BEFORE clearing the JWT so the PUT goes out
    // with the auth header still attached. Best-effort — failure here must
    // not block logout.
    try {
      await FcmService.instance.clearOnBackend();
    } catch (_) {}

    _status = AuthStatus.unauthenticated;
    _token = null;
    _role = null;
    _userId = null;
    _phoneNumber = null;
    _fullName = null;
    _email = null;
    await TokenStorage.clear();
    notifyListeners();
  }
}
