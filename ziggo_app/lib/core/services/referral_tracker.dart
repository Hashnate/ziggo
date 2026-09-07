import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/api_client.dart';

/// Tracks, captures, and manages referral codes when a user downloads the app
/// via an invite link (supporting Google Play Store install referrer on Android,
/// deferred IP-attribution on iOS/Web, and clipboard detection as fallback).
class ReferralTracker {
  ReferralTracker._();

  static const String _pendingReferralKey = 'pending_referral_code';
  static const String _alreadyAttributedKey = 'referral_already_attributed';
  static const MethodChannel _channel = MethodChannel('lk.ziggo.app/install_referrer');

  static String? _cachedCode;

  /// Call early on app startup (e.g. from main.dart or SplashScreen).
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedCode = prefs.getString(_pendingReferralKey);
      if (_cachedCode != null && _cachedCode!.isNotEmpty) {
        return;
      }

      final alreadyAttributed = prefs.getBool(_alreadyAttributedKey) ?? false;
      if (alreadyAttributed) {
        return;
      }

      // 1. Check Android Google Play Install Referrer (if Android)
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final String? rawReferrer = await _channel.invokeMethod<String>('getInstallReferrer');
          if (rawReferrer != null && rawReferrer.isNotEmpty) {
            final parsed = _extractCode(rawReferrer);
            if (parsed != null && parsed.isNotEmpty) {
              await savePendingReferralCode(parsed);
              return;
            }
          }
        } catch (e) {
          debugPrint('[ReferralTracker] Error reading native install referrer: $e');
        }
      }

      // 2. Check Backend Deferred IP Attribution (especially for iOS)
      try {
        final resp = await ApiClient.instance.dio.get('/public/match-referral');
        if (resp.statusCode == 200 && resp.data is Map) {
          final code = resp.data['referral_code'] as String?;
          if (code != null && code.trim().isNotEmpty) {
            await savePendingReferralCode(code.trim().toUpperCase());
            return;
          }
        }
      } catch (e) {
        // Backend match lookup failed or not found; proceed to clipboard
      }

      // 3. Fallback: Check clipboard for referral code pattern
      try {
        final clipData = await Clipboard.getData(Clipboard.kTextPlain);
        final text = clipData?.text;
        if (text != null && text.isNotEmpty) {
          final parsed = _extractCode(text);
          if (parsed != null && parsed.isNotEmpty) {
            await savePendingReferralCode(parsed);
            return;
          }
        }
      } catch (e) {
        debugPrint('[ReferralTracker] Clipboard check error: $e');
      }
    } catch (e) {
      debugPrint('[ReferralTracker] Init error: $e');
    }
  }

  /// Extracts referral code from text, URL, or referrer query string.
  static String? _extractCode(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return null;

    // Pattern 1: URL query param ref=XYZ or referrer=ref%3DXYZ or code=XYZ
    final uriRegExp = RegExp(r'(?:ref|referrer|code)=([A-Za-z0-9%_-]+)', caseSensitive: false);
    final uriMatch = uriRegExp.firstMatch(clean);
    if (uriMatch != null) {
      String raw = Uri.decodeComponent(uriMatch.group(1) ?? '');
      if (raw.startsWith('ref=')) raw = raw.substring(4);
      final sanitized = raw.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
      if (sanitized.length >= 4 && sanitized.length <= 16) {
        return sanitized;
      }
    }

    // Pattern 2: Standard Ziggo referral code format (e.g. ZGB12345 or ZGBPFP9V)
    final ziggoRegExp = RegExp(r'\b(ZGB[A-Z0-9]{4,12})\b', caseSensitive: false);
    final ziggoMatch = ziggoRegExp.firstMatch(clean);
    if (ziggoMatch != null) {
      return ziggoMatch.group(1)!.toUpperCase();
    }

    // Pattern 3: Text like "referral code ABC123"
    final textRegExp = RegExp(r'(?:referral\s*code|invite\s*code)[\s:=]+([A-Za-z0-9]{4,16})', caseSensitive: false);
    final textMatch = textRegExp.firstMatch(clean);
    if (textMatch != null) {
      return textMatch.group(1)!.toUpperCase();
    }

    // Pattern 4: If single word matching 6-12 uppercase alphanumeric characters
    if (RegExp(r'^[A-Z0-9]{6,12}$').hasMatch(clean)) {
      return clean;
    }

    return null;
  }

  /// Retrieve the current pending referral code if available.
  static Future<String?> getPendingReferralCode() async {
    if (_cachedCode != null && _cachedCode!.isNotEmpty) {
      return _cachedCode;
    }
    final prefs = await SharedPreferences.getInstance();
    _cachedCode = prefs.getString(_pendingReferralKey);
    return _cachedCode;
  }

  /// Save detected referral code to SharedPreferences.
  static Future<void> savePendingReferralCode(String code) async {
    final sanitized = code.trim().toUpperCase();
    if (sanitized.isEmpty) return;
    _cachedCode = sanitized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingReferralKey, sanitized);
    debugPrint('[ReferralTracker] Saved pending referral code: $sanitized');
  }

  /// Mark referral code as consumed/attributed.
  static Future<void> markAttributed() async {
    _cachedCode = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingReferralKey);
    await prefs.setBool(_alreadyAttributedKey, true);
  }
}
