import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'places.dart';

/// A Google Places autocomplete prediction (no coordinates — those are
/// resolved on selection via [MapsService.placeLatLng]).
class PlacePrediction {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlacePrediction({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  String get description =>
      secondaryText.isEmpty ? mainText : '$mainText, $secondaryText';
}

/// Result of a Directions API call.
class DirectionsResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;

  const DirectionsResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
  });
}

/// Thin client over the Google Maps web-service APIs (Places + Directions).
///
/// NOTE: the API key is shipped in the app binary here. That's fine for local
/// development, but for production these calls should be proxied through the
/// FastAPI backend (which already has a `GOOGLE_MAPS_API_KEY` setting) so the
/// key never leaves the server.
class MapsService {
  MapsService._();
  static final MapsService instance = MapsService._();

  static const String _apiKey = 'AIzaSyAxGlCCI4yoOn3umPPyX1VypSzL2Sutz9U';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  /// Places Autocomplete — biased to Sri Lanka.
  Future<List<PlacePrediction>> autocomplete(String query, {LatLng? near}) async {
    if (query.trim().length < 2) return const [];
    try {
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json',
        queryParameters: {
          'input': query.trim(),
          'key': _apiKey,
          'components': 'country:lk',
          if (near != null) 'location': '${near.latitude},${near.longitude}',
          if (near != null) 'radius': 50000,
        },
      );
      final preds = (resp.data['predictions'] as List?) ?? const [];
      return preds.map<PlacePrediction>((p) {
        final sf = (p['structured_formatting'] as Map?) ?? const {};
        return PlacePrediction(
          placeId: (p['place_id'] ?? '').toString(),
          mainText: (sf['main_text'] ?? p['description'] ?? '').toString(),
          secondaryText: (sf['secondary_text'] ?? '').toString(),
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Resolves a place_id to its coordinates.
  Future<LatLng?> placeLatLng(String placeId) async {
    try {
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/place/details/json',
        queryParameters: {
          'place_id': placeId,
          'key': _apiKey,
          'fields': 'geometry',
        },
      );
      final loc = resp.data['result']?['geometry']?['location'];
      if (loc == null) return null;
      return LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Reverse-geocode a coordinate to a human-readable address.
  ///
  /// Plus codes (e.g. "G52J+XF5, B541") get filtered out at two levels:
  /// (a) results whose `types` contains `plus_code` are skipped, and
  /// (b) any `formatted_address` that still leads with a plus-code prefix has
  ///     that prefix stripped. If nothing readable is left, the address is
  ///     rebuilt from `address_components` (route / sublocality / locality).
  Future<String?> reverseGeocode(LatLng point) async {
    try {
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '${point.latitude},${point.longitude}',
          'key': _apiKey,
        },
      );
      final results = (resp.data['results'] as List?) ?? const [];
      final plusCodeRe = RegExp(r'^[A-Z0-9]{4,8}\+[A-Z0-9]{2,3}\b');

      String stripPlusPrefix(String s) {
        var out = s;
        if (plusCodeRe.hasMatch(out)) {
          out = out.replaceFirst(plusCodeRe, '').trim();
          if (out.startsWith(',')) out = out.substring(1).trim();
        }
        return out;
      }

      for (final r in results) {
        final types = (r['types'] as List?)?.cast<String>() ?? const [];
        if (types.contains('plus_code')) continue;
        final addr = r['formatted_address']?.toString() ?? '';
        final cleaned = stripPlusPrefix(addr);
        if (cleaned.isNotEmpty) return cleaned;
      }

      // Fallback: rebuild from address_components on the first result.
      if (results.isNotEmpty) {
        final comps =
            (results.first['address_components'] as List?) ?? const [];
        String? route, neighborhood, sublocality, locality;
        for (final c in comps) {
          final t = (c['types'] as List?)?.cast<String>() ?? const [];
          final name = c['long_name']?.toString() ?? '';
          if (name.isEmpty) continue;
          if (t.contains('route')) route ??= name;
          if (t.contains('neighborhood')) neighborhood ??= name;
          if (t.contains('sublocality')) sublocality ??= name;
          if (t.contains('locality')) locality ??= name;
        }
        final primary = route ?? neighborhood ?? sublocality ?? locality;
        final secondary = locality ?? sublocality ?? neighborhood;
        if (primary != null) {
          return secondary != null && secondary != primary
              ? '$primary, $secondary'
              : primary;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Directions between two points — returns the decoded route polyline plus
  /// the road distance and duration.
  Future<DirectionsResult?> directions(LatLng origin, LatLng dest) async {
    try {
      final resp = await _dio.get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '${origin.latitude},${origin.longitude}',
          'destination': '${dest.latitude},${dest.longitude}',
          'key': _apiKey,
        },
      );
      final routes = (resp.data['routes'] as List?) ?? const [];
      if (routes.isEmpty) return null;
      final route = routes.first;
      final legs = (route['legs'] as List?) ?? const [];
      if (legs.isEmpty) return null;
      final leg = legs.first;
      final encoded = route['overview_polyline']?['points'] as String?;
      return DirectionsResult(
        points: encoded == null ? const [] : _decodePolyline(encoded),
        distanceKm: ((leg['distance']?['value'] as num?) ?? 0) / 1000.0,
        durationMin: (((leg['duration']?['value'] as num?) ?? 0) / 60).round(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Resolve the device's current GPS position into a [Place], reverse-geocoded
  /// for a readable address.
  ///
  /// To stay responsive: first tries `getLastKnownPosition` (instant on devices
  /// that have any recent fix), and falls back to a fresh fix with an 8-second
  /// time limit so we never hang. Reverse-geocoding failure is non-fatal — the
  /// returned [Place] just shows "Current location" in that case.
  Future<Place?> currentLocationAsPlace() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return null;
      }

      Position? pos;
      try {
        pos = await Geolocator.getLastKnownPosition();
      } catch (_) {}

      pos ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final point = LatLng(pos.latitude, pos.longitude);
      final addr = await reverseGeocode(point);
      if (addr == null || addr.isEmpty) {
        return Place('Current location', 'Live GPS', point);
      }
      final parts = addr.split(',').map((s) => s.trim()).toList();
      final name = parts.first;
      final area = parts.length > 1 ? parts[1] : 'Live GPS';
      return Place(name, area, point);
    } catch (_) {
      return null;
    }
  }

  /// Standard Google "encoded polyline algorithm" decoder.
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0, lat = 0, lng = 0;
    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
