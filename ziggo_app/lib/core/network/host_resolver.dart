import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Discovers the Ziggo backend's reachable URL at runtime.
///
/// Production: uses the direct IP (DNS-free, works on all mobile carriers)
/// as the guaranteed fallback. Prefers the domain if DNS resolves.
/// Dev: override with `--dart-define=API_HOST=http://your-dev-pc:8030`.
class HostResolver {
  HostResolver._();

  static const int _port = 8030;
  static const String _prefsKey = 'ziggo_api_host';
  static const String _envHost =
      String.fromEnvironment('API_HOST', defaultValue: '');

  // Direct IP on port 80 (nginx) — guaranteed to work on ALL carriers
  // because it bypasses DNS resolution entirely.
  static const String fallbackHost = 'http://187.127.152.141';

  // Preferred HTTPS domain — used when the phone's DNS can resolve it.
  static const String _preferredHost = 'https://ziggo.lk';

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
    // 1. Explicit override via --dart-define
    if (_envHost.isNotEmpty && await _probe(_envHost)) {
      return _save(_envHost);
    }

    // 2. Previously-resolved host from SharedPreferences (skip stale entries)
    String? saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getString(_prefsKey);
      // Wipe stale entries: old port-based URLs or plain-HTTP remote hosts
      if (saved != null) {
        if (saved.contains(':8000') || saved.contains(':8030')) {
          await prefs.remove(_prefsKey);
          saved = null;
        }
      }
    } catch (_) {}
    if (saved != null && saved.isNotEmpty && await _probe(saved)) {
      _cached = saved;
      return saved;
    }

    // 3. Probe production hosts — IP first (DNS-free, fastest), then domain
    final prodHosts = <String>[
      fallbackHost,     // http://187.127.152.141 — no DNS needed, always works
      _preferredHost,   // https://ziggo.lk — preferred but needs DNS
    ];
    final prodResult = await _probeMany(prodHosts);
    if (prodResult != null) return _save(prodResult);

    // 4. Dev-only: probe localhost / Android emulator gateway
    if (!kIsWeb) {
      final devHosts = <String>[
        'http://localhost:$_port',
        'http://10.0.2.2:$_port',
      ];
      final devResult = await _probeMany(devHosts);
      if (devResult != null) return _save(devResult);
    }

    // 5. Last resort — use the IP directly (don't waste time scanning subnet)
    _cached = fallbackHost;
    return fallbackHost;
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
