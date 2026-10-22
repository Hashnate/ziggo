import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Discovers the Ziggo backend's reachable URL at runtime.
///
/// Production: Uses the secure https://ziggo.lk endpoint exclusively.
/// Dev / staging: override with `--dart-define=API_HOST=https://test.ziggo.lk`.
/// An override is final: if that host is down the app shows connection errors
/// instead of switching to production, so test builds never touch live data.
class HostResolver {
  HostResolver._();

  static const String productionHost = 'https://ziggo.lk';
  static const String _prefsKey = 'ziggo_api_host';
  static const String _envHost =
      String.fromEnvironment('API_HOST', defaultValue: '');

  /// Used until [resolve] completes; startup only waits a few seconds for it.
  static String get fallbackHost =>
      _envHost.isNotEmpty ? _envHost : productionHost;

  /// Corner-banner text for builds pointed away from production, else null.
  static String? get bannerLabel {
    if (_envHost.isEmpty || _envHost == productionHost) return null;
    return _envHost.contains('test.ziggo.lk') ? 'STAGING' : 'DEV';
  }

  static String? _cached;
  static Future<String>? _inFlight;

  static String? get cached => _cached;

  static Future<String> resolve({bool forceRefresh = false}) {
    if (forceRefresh) {
      _cached = null;
      _inFlight = null;
    }
    if (_cached != null) return Future.value(_cached!);
    return _inFlight ??= _resolve()
      ..whenComplete(() => _inFlight = null);
  }

  static Future<String> _resolve() async {
    // 1. Explicit override via --dart-define. Not probed on purpose: falling
    // back to production when a test server is down would let a staging
    // build create real bookings.
    if (_envHost.isNotEmpty) {
      _cached = _envHost;
      return _envHost;
    }

    // 2. Wipe any stale raw-IP or legacy port entries from SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        if (saved.contains('187.127.152.141') ||
            saved.contains(':8000') ||
            saved.contains(':8030') ||
            saved.startsWith('http://')) {
          await prefs.remove(_prefsKey);
        }
      }
    } catch (_) {}

    // 3. Dev-only: probe localhost / Android emulator gateway in debug mode
    if (!kIsWeb && kDebugMode) {
      final devHosts = <String>[
        'http://localhost:8030',
        'http://10.0.2.2:8030',
      ];
      final devResult = await _probeMany(devHosts);
      if (devResult != null) return _save(devResult);
    }

    // 4. Default to secure production HTTPS domain
    _cached = productionHost;
    return productionHost;
  }

  static Future<String> _save(String host) async {
    _cached = host;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, host);
    } catch (_) {}
    return host;
  }

  static Future<bool> _probe(
    String host, {
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? const Duration(milliseconds: 3000);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: effectiveTimeout,
        receiveTimeout: effectiveTimeout,
        sendTimeout: effectiveTimeout,
      ));
      if (!kIsWeb) {
        (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
          final client = HttpClient();
          client.badCertificateCallback = (cert, host, port) => true;
          return client;
        };
      }
      final r = await dio.getUri(Uri.parse('$host/health'));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _probeMany(List<String> hosts) async {
    if (hosts.isEmpty) return null;
    final completer = Completer<String?>();
    var remaining = hosts.length;
    for (final h in hosts) {
      _probe(h).then((ok) {
        if (completer.isCompleted) return;
        if (ok) {
          completer.complete(h);
        } else {
          remaining--;
          if (remaining == 0) completer.complete(null);
        }
      });
    }
    return completer.future;
  }

  static Future<void> override(String host) async {
    final clean = host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    await _save(clean);
  }

  static Future<void> clearCache() async {
    _cached = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }
}
