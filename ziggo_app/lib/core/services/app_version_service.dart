import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Reads, normalizes, and caches the installed app version name (e.g. "1.1.5").
class AppVersionService {
  AppVersionService._();

  static String? _cachedVersion;
  static Future<String>? _inFlight;
  static Future<String> Function()? _testLoader;

  /// Cached app version name (e.g. "1.1.5"), or null if not yet loaded.
  static String? get cachedVersion => _cachedVersion;

  /// Returns the installed app version name (without a leading "v").
  ///
  /// Deduplicates concurrent lookups and returns an empty string if platform
  /// package metadata cannot be read.
  static Future<String> getVersion() {
    final cached = _cachedVersion;
    if (cached != null && cached.isNotEmpty) {
      return Future.value(cached);
    }
    return _inFlight ??= _loadVersion();
  }

  static Future<String> _loadVersion() async {
    try {
      final raw = _testLoader != null
          ? await _testLoader!()
          : (await PackageInfo.fromPlatform()).version;
      final normalized = normalize(raw);
      if (normalized.isNotEmpty) {
        _cachedVersion = normalized;
      }
      return normalized;
    } catch (_) {
      return '';
    } finally {
      _inFlight = null;
    }
  }

  /// Normalizes a version string by stripping whitespace, an optional leading
  /// "v"/"V" prefix, and any trailing "+build" metadata.
  static String normalize(String raw) => raw
      .trim()
      .replaceFirst(RegExp(r'^[vV](?=\d)'), '')
      .split('+')
      .first
      .trim();

  /// Overrides version loading in unit/widget tests.
  @visibleForTesting
  static void setLoaderForTesting(Future<String> Function()? loader) {
    _testLoader = loader;
    _cachedVersion = null;
    _inFlight = null;
  }
}
