import 'dart:convert';

import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'places.dart';

/// Lightweight on-device cache of the places a user has recently picked, so the
/// location search UIs can show "recent locations" under the search bar without
/// any backend round-trip. Persisted via SharedPreferences; kept in memory so
/// the picker can read it synchronously after the first [load].
class RecentPlaces {
  RecentPlaces._();

  static const _key = 'recent_places_v1';
  static const _max = 8;

  static List<Place> _cache = const [];
  static bool _loaded = false;

  static List<Place> get items => List.unmodifiable(_cache);

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key) ?? const [];
      _cache = raw.map(_decode).whereType<Place>().toList();
    } catch (_) {}
  }

  /// Records a chosen place at the top of the recent list (most-recent-first),
  /// de-duplicating by name + area and trimming to [_max].
  static Future<void> add(Place place) async {
    if (place.name.trim().isEmpty || place.name == '__SET_ON_MAP__') return;
    await load();
    final next = List<Place>.from(_cache)
      ..removeWhere((p) => p.name == place.name && p.area == place.area);
    next.insert(0, place);
    _cache = next.length > _max ? next.sublist(0, _max) : next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _cache.map(_encode).toList());
    } catch (_) {}
  }

  static Future<void> clear() async {
    _cache = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }

  static String _encode(Place p) => jsonEncode({
        'name': p.name,
        'area': p.area,
        'lat': p.location.latitude,
        'lng': p.location.longitude,
      });

  static Place? _decode(String s) {
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return Place(
        m['name'] as String,
        m['area'] as String,
        LatLng((m['lat'] as num).toDouble(), (m['lng'] as num).toDouble()),
      );
    } catch (_) {
      return null;
    }
  }
}
