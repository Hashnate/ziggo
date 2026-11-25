import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../network/api_client.dart';
import '../storage/token_storage.dart';
import 'places.dart';

/// A place suggestion (no coordinates — those are resolved on selection via
/// [MapsService.placeLatLng]).
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

/// One step in a turn-by-turn route (BRD: Turn-by-turn navigation).
class DirectionStep {
  final String instruction;   // HTML-stripped human text ("Turn right onto X")
  final String maneuver;      // Google's maneuver key ("turn-right", "merge"…)
  final double distanceM;     // meters for this leg
  final int durationS;        // seconds for this leg
  final LatLng startLocation;
  final LatLng endLocation;

  const DirectionStep({
    required this.instruction,
    required this.maneuver,
    required this.distanceM,
    required this.durationS,
    required this.startLocation,
    required this.endLocation,
  });
}

/// A road route: the line to draw, its distance and duration, and its steps.
class DirectionsResult {
  final List<LatLng> points;
  final double distanceKm;
  final int durationMin;
  // BRD: Turn-by-turn navigation
  final List<DirectionStep> steps;

  const DirectionsResult({
    required this.points,
    required this.distanceKm,
    required this.durationMin,
    this.steps = const [],
  });

  /// From the server's route JSON: {polyline, distance_m, duration_s, steps}.
  factory DirectionsResult.fromServer(Map<String, dynamic> json) {
    LatLng at(List<dynamic> v) =>
        LatLng((v[0] as num).toDouble(), (v[1] as num).toDouble());

    final steps = <DirectionStep>[];
    for (final s in (json['steps'] as List?) ?? const []) {
      if (s is! Map) continue;
      final start = s['start'];
      final end = s['end'];
      if (start is! List || end is! List || start.length < 2 || end.length < 2) continue;
      steps.add(DirectionStep(
        instruction: (s['instruction'] ?? '').toString(),
        maneuver: (s['maneuver'] ?? '').toString(),
        distanceM: ((s['distance_m'] as num?) ?? 0).toDouble(),
        durationS: ((s['duration_s'] as num?) ?? 0).toInt(),
        startLocation: at(start),
        endLocation: at(end),
      ));
    }
    return DirectionsResult(
      points: decodePolyline((json['polyline'] ?? '').toString()),
      distanceKm: ((json['distance_m'] as num?) ?? 0) / 1000.0,
      durationMin: (((json['duration_s'] as num?) ?? 0) / 60).round(),
      steps: steps,
    );
  }
}

/// Google Maps through the Ziggo server (/api/v1/maps). The app holds no Google
/// web-service key; the server shares answers between users and counts the calls.
///
/// A login is needed. Guests get empty answers, and the screens fall back to the
/// built-in landmarks, "Current location" and straight lines — as they always did
/// when Google gave nothing back.
class MapsService {
  MapsService._();
  static final MapsService instance = MapsService._();

  static const double _reuseAddressMeters = 30;
  static const Duration _reuseAddressFor = Duration(minutes: 10);

  // The last current-location address, reused while the phone stays near it so
  // opening the app or a screen again doesn't look the same place up again.
  LatLng? _hereAt;
  String? _hereAddress;
  DateTime? _hereWhen;

  Future<bool> _signedIn() async {
    final token = await TokenStorage.getToken();
    return token != null && token.isNotEmpty;
  }

  /// A new token for one place search: the suggestions typed for it and the
  /// place finally picked count as a single search with Google.
  static String newSessionToken() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// The device's last known position, without prompting or waiting for a fix.
  Future<LatLng?> _lastKnownPoint() async {
    try {
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  /// Place suggestions in Sri Lanka, biased to [near] or else to where the
  /// device is. Pass the same [sessionToken] for every search of one pick.
  Future<List<PlacePrediction>> autocomplete(
    String query, {
    LatLng? near,
    String? sessionToken,
  }) async {
    final text = query.trim();
    if (text.length < 2 || !await _signedIn()) return const [];
    near ??= await _lastKnownPoint();
    try {
      final resp = await ApiClient.instance.dio.get(
        '/maps/autocomplete',
        queryParameters: {
          'input': text,
          if (sessionToken != null) 'session': sessionToken,
          if (near != null) 'lat': near.latitude,
          if (near != null) 'lng': near.longitude,
        },
      );
      final data = resp.data;
      final preds = (data is Map ? data['predictions'] as List? : null) ?? const [];
      return preds
          .whereType<Map>()
          .map((p) => PlacePrediction(
                placeId: (p['place_id'] ?? '').toString(),
                mainText: (p['main_text'] ?? '').toString(),
                secondaryText: (p['secondary_text'] ?? '').toString(),
              ))
          .where((p) => p.placeId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Coordinates of a picked suggestion. Pass the search's [sessionToken].
  Future<LatLng?> placeLatLng(String placeId, {String? sessionToken}) async {
    if (placeId.isEmpty || !await _signedIn()) return null;
    try {
      final resp = await ApiClient.instance.dio.get(
        '/maps/place',
        queryParameters: {
          'place_id': placeId,
          if (sessionToken != null) 'session': sessionToken,
        },
      );
      final data = resp.data;
      final loc = data is Map ? data['location'] : null;
      if (loc is! Map || loc['lat'] == null || loc['lng'] == null) return null;
      return LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
    } catch (_) {
      return null;
    }
  }

  /// A readable address for a point (plus codes and far-away matches are
  /// filtered out by the server), or null.
  Future<String?> reverseGeocode(LatLng point) async {
    if (!await _signedIn()) return null;
    try {
      final resp = await ApiClient.instance.dio.get(
        '/maps/reverse-geocode',
        queryParameters: {'lat': point.latitude, 'lng': point.longitude},
      );
      final data = resp.data;
      final address = data is Map ? data['address'] : null;
      return address is String && address.trim().isNotEmpty ? address.trim() : null;
    } catch (_) {
      return null;
    }
  }

  /// Road route from [origin] to [dest].
  Future<DirectionsResult?> directions(LatLng origin, LatLng dest) =>
      route([origin, dest]);

  /// Road route through [points] in order (start, stops, end), as one request.
  Future<DirectionsResult?> route(List<LatLng> points) async {
    if (points.length < 2 || points.length > 12 || !await _signedIn()) return null;
    try {
      final resp = await ApiClient.instance.dio.post(
        '/maps/route',
        data: {
          'points': [
            for (final p in points) {'lat': p.latitude, 'lng': p.longitude},
          ],
        },
      );
      final data = resp.data;
      final raw = data is Map ? data['route'] : null;
      if (raw is! Map) return null;
      final result = DirectionsResult.fromServer(Map<String, dynamic>.from(raw));
      return result.points.length < 2 ? null : result;
    } catch (_) {
      return null;
    }
  }

  /// Resolve the device's current GPS position into a [Place], with a readable
  /// address when one can be found.
  ///
  /// To stay responsive: first tries `getLastKnownPosition` (instant on devices
  /// that have any recent fix), and falls back to a fresh fix with an 8-second
  /// time limit so we never hang. The address is reused while the phone stays
  /// within 30 m of where it was looked up (for 10 minutes). Without an address
  /// the returned [Place] just shows "Current location".
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
      final now = DateTime.now();
      final reuse = _hereAt != null &&
          _hereAddress != null &&
          _hereWhen != null &&
          now.difference(_hereWhen!) < _reuseAddressFor &&
          Geolocator.distanceBetween(
                _hereAt!.latitude, _hereAt!.longitude, point.latitude, point.longitude) <=
              _reuseAddressMeters;
      String? addr;
      if (reuse) {
        addr = _hereAddress;
      } else {
        addr = await reverseGeocode(point);
        if (addr != null) {
          _hereAt = point;
          _hereAddress = addr;
          _hereWhen = now;
        }
      }
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
}

/// Google's "encoded polyline" format -> points.
List<LatLng> decodePolyline(String encoded) {
  final List<LatLng> points = [];
  int index = 0, lat = 0, lng = 0;
  final len = encoded.length;
  while (index < len) {
    int b, shift = 0, result = 0;
    do {
      if (index >= len) return points;
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    shift = 0;
    result = 0;
    do {
      if (index >= len) return points;
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
