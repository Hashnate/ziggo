import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/notifications/fcm_service.dart';
import '../../core/storage/token_storage.dart';

enum AuthStatus { unauthenticated, authenticating, authenticated, error }

/// Pull a human-readable message out of a DioException without assuming the
/// error body is JSON. FastAPI normally returns `{"detail": ...}`, but a 500
/// HTML page / proxy error / plain-text body comes back as a String — indexing
/// that with `['detail']` used to crash the whole app.
String? _dioMessage(DioException e) {
  final data = e.response?.data;
  if (data is Map) return data['detail']?.toString();
  if (data is String && data.trim().isNotEmpty && !data.contains('<')) {
    return data;
  }
  return e.message;
}

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.unauthenticated;
  String? _token;
  String? _role;
  int? _userId;
  String? _phoneNumber;
  String? _fullName;
  String? _email;
  String? _lastError;
  String? _devOtp;
  bool _isNewUser = false;
  String? _birthday;
  String? _gender;
  String? _emergencyContact;
  String? _profilePhoto;
  String? _referralCode;
  int? _referredByUserId;

  AuthStatus get status => _status;
  String? get token => _token;
  String? get role => _role;
  int? get userId => _userId;
  String? get phoneNumber => _phoneNumber;
  String? get fullName => _fullName;
  String? get email => _email;
  String? get lastError => _lastError;
  String? get devOtp => _devOtp;
  String? get referralCode => _referralCode;
  int? get referredByUserId => _referredByUserId;
  /// True only for the first-ever OTP verification on this phone (signup).
  /// Used to route new users through the "Your details" screen before home.
  bool get isNewUser => _isNewUser;
  String? get birthday => _birthday;
  String? get gender => _gender;
  String? get emergencyContact => _emergencyContact;
  String? get profilePhoto => _profilePhoto;

  bool _isCustomerMode = false;
  bool get isCustomerMode => _isCustomerMode;

  void toggleCustomerMode() {
    _isCustomerMode = !_isCustomerMode;
    notifyListeners();
  }

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
      _devOtp = resp.data is Map ? resp.data['dev_otp'] as String? : null;
      _phoneNumber = phoneNumber;
      notifyListeners();
      return true;
    } on DioException catch (e) {
      final baseUrl = ApiClient.instance.dio.options.baseUrl;
      _lastError = '${_dioMessage(e)} (URL: $baseUrl)';
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
      _isNewUser = resp.data['is_new'] as bool? ?? false;
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
      final baseUrl = ApiClient.instance.dio.options.baseUrl;
      _lastError = '${_dioMessage(e)} (URL: $baseUrl)';
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
      _fullName = resp.data['full_name'] as String? ?? _fullName;
      _email = resp.data['email'] as String? ?? _email;
      _phoneNumber = resp.data['phone_number'] as String? ?? _phoneNumber;
      _birthday = resp.data['birthday'] as String? ?? _birthday;
      _gender = resp.data['gender'] as String? ?? _gender;
      _emergencyContact = resp.data['emergency_contact'] as String? ?? _emergencyContact;
      _profilePhoto = resp.data['profile_photo'] as String? ?? _profilePhoto;
      _referralCode = resp.data['referral_code'] as String? ?? _referralCode;
      _referredByUserId = resp.data['referred_by_user_id'] as int? ?? _referredByUserId;
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
    String? emergencyContact,
    String? profilePhoto,
    String? phoneNumber,
    String? referredByCode,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (email != null) body['email'] = email;
    if (birthday != null) body['birthday'] = birthday;
    if (gender != null) body['gender'] = gender;
    if (emergencyContact != null) body['emergency_contact'] = emergencyContact;
    if (profilePhoto != null) body['profile_photo'] = profilePhoto;
    if (phoneNumber != null) body['phone_number'] = phoneNumber;
    if (referredByCode != null && referredByCode.trim().isNotEmpty) {
      body['referred_by_code'] = referredByCode.trim().toUpperCase();
    }
    if (body.isEmpty) return;
    
    final resp = await ApiClient.instance.dio.patch('/customer/profile', data: body);
    _fullName = resp.data['full_name'] as String? ?? fullName ?? _fullName;
    _email = resp.data['email'] as String? ?? email ?? _email;
    _birthday = resp.data['birthday'] as String? ?? birthday ?? _birthday;
    _gender = resp.data['gender'] as String? ?? gender ?? _gender;
    _emergencyContact = resp.data['emergency_contact'] as String? ?? emergencyContact ?? _emergencyContact;
    _profilePhoto = resp.data['profile_photo'] as String? ?? profilePhoto ?? _profilePhoto;
    _phoneNumber = resp.data['phone_number'] as String? ?? phoneNumber ?? _phoneNumber;
    _referredByUserId = resp.data['referred_by_user_id'] as int? ?? _referredByUserId;
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
    _birthday = null;
    _gender = null;
    _emergencyContact = null;
    _profilePhoto = null;
    await TokenStorage.clear();
    notifyListeners();
  }
}
