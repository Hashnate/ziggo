import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Discovers the Ziggo backend's reachable URL at runtime so the app keeps
/// working even when the dev PC's LAN IP changes (router reboot, new Wi-Fi).
///
/// Resolution order:
///   1. `--dart-define=API_HOST=http://x.x.x.x:8030` (explicit override)
///   2. Last-known good host from SharedPreferences
///   3. Parallel probe of common dev hosts (localhost, hard-coded LAN IP,
///      Android emulator gateway 10.0.2.2)
///   4. Scan the phone's current /24 subnet for any host serving `/health`
///   5. Fall back to the hard-coded default (will surface a clear error)
class HostResolver {
  HostResolver._();

  static const int _port = 8030;
  static const String _prefsKey = 'ziggo_api_host';
  static const String _envHost =
      String.fromEnvironment('API_HOST', defaultValue: '');
  // Production server (nginx with SSL → backend container). Override at
  // build time with `--dart-define=API_HOST=http://your-dev-pc:8030` when
  // you want the app to hit a local dev backend instead.
  static const String fallbackHost = 'https://ziggo.lk';

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
    if (_envHost.isNotEmpty && await _probe(_envHost)) {
      return _save(_envHost);
    }

    String? saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getString(_prefsKey);
      if (saved != null && (saved.contains(':8000') || saved.contains(':8030') || saved.startsWith('http://187.127.152.141'))) {
        await prefs.remove(_prefsKey);
        saved = null;
      }
    } catch (_) {}
    if (saved != null && saved.isNotEmpty && await _probe(saved)) {
      _cached = saved;
      return saved;
    }

    final defaults = <String>{
      'http://localhost:$_port',
      fallbackHost,
      'http://187.127.152.141',
      if (!kIsWeb) 'http://10.0.2.2:$_port',
    }.toList();
    final fromDefaults = await _probeMany(defaults);
    if (fromDefaults != null) return _save(fromDefaults);

    final scanned = await _scanLocalSubnet();
    if (scanned != null) return _save(scanned);

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
    final isLocal = _isLocalHost(host);
    final effectiveTimeout = timeout ?? (isLocal
        ? const Duration(milliseconds: 700)
        : const Duration(milliseconds: 3000));
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

  static Future<String?> _scanLocalSubnet() async {
    if (kIsWeb) return null;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (!_isPrivate(ip)) continue;
          final parts = ip.split('.');
          if (parts.length != 4) continue;
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          final hosts = <String>[
            for (var i = 1; i < 255; i++) 'http://$prefix.$i:$_port',
          ];
          for (var i = 0; i < hosts.length; i += 32) {
            final end = (i + 32) > hosts.length ? hosts.length : (i + 32);
            final chunk = hosts.sublist(i, end);
            final found = await _probeMany(chunk);
            if (found != null) return found;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static bool _isPrivate(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.')[1]) ?? -1;
      return second >= 16 && second <= 31;
    }
    return false;
  }

  static bool _isLocalHost(String host) {
    try {
      final uri = Uri.tryParse(host);
      if (uri == null) return false;
      final h = uri.host;
      if (h == 'localhost' || h == '127.0.0.1') return true;
      return _isPrivate(h);
    } catch (_) {
      return false;
    }
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
