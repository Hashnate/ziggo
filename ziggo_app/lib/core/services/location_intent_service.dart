import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../map/maps_service.dart';
import '../map/places.dart';
import '../notifications/notification_router.dart';
import '../../modules/auth/auth_provider.dart';
import '../../modules/customer/booking_provider.dart';
import '../../modules/customer/screens/vehicle_selection_screen.dart';

/// Service to handle external location intents (e.g. WhatsApp, Google Maps, SMS)
/// delivered via Android's `geo:` and Google Maps implicit intent filters.
class LocationIntentService {
  LocationIntentService._();
  static final LocationIntentService instance = LocationIntentService._();

  static const MethodChannel _channel = MethodChannel('lk.ziggo.app/location_intent');

  bool _initialized = false;
  String? _lastHandledUri;
  DateTime? _lastHandledTime;
  String? _queuedUri;

  /// Call once when the customer environment is mounted (e.g. in CustomerShell or _Root)
  void init(BuildContext context) {
    if (_initialized) {
      _processQueuedIntentIfNeeded();
      return;
    }
    _initialized = true;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLocationReceived') {
        final uriString = call.arguments as String?;
        if (uriString != null && uriString.trim().isNotEmpty) {
          await handleIncomingUri(uriString.trim());
        }
      }
    });

    // Check cold-start intent
    _checkInitialIntent();
  }

  Future<void> _checkInitialIntent() async {
    try {
      final initialUri = await _channel.invokeMethod<String>('getInitialLocation');
      if (initialUri != null && initialUri.trim().isNotEmpty) {
        await handleIncomingUri(initialUri.trim());
      }
    } catch (e) {
      debugPrint('[LocationIntentService] Error fetching initial intent: $e');
    }
  }

  void _processQueuedIntentIfNeeded() {
    if (_queuedUri != null) {
      final uri = _queuedUri!;
      _queuedUri = null;
      handleIncomingUri(uri);
    }
  }

  /// Entry point to process any incoming raw location URI
  Future<void> handleIncomingUri(String rawUri) async {
    final now = DateTime.now();
    // Debounce duplicate events within 2.5 seconds
    if (_lastHandledUri == rawUri &&
        _lastHandledTime != null &&
        now.difference(_lastHandledTime!).inMilliseconds < 2500) {
      return;
    }
    _lastHandledUri = rawUri;
    _lastHandledTime = now;

    final navContext = rootNavigatorKey.currentContext;
    if (navContext == null) {
      _queuedUri = rawUri;
      return;
    }

    try {
      final target = await parseLocationUri(rawUri);
      if (target == null) return;

      // Ensure user has auth or guest access before opening booking flow
      final auth = navContext.read<AuthProvider>();
      if (auth.status != AuthStatus.authenticated && !auth.isGuest) {
        _queuedUri = rawUri;
        return;
      }

      // Check if user has an active ride in progress
      final bookingProv = navContext.read<BookingProvider>();
      final active = bookingProv.activeBooking;
      final isRideActive = active != null &&
          (active['status'] == 'searching' ||
              active['status'] == 'accepted' ||
              active['status'] == 'arrived' ||
              active['status'] == 'started');

      if (isRideActive) {
        _showActiveRideAlert(navContext);
        return;
      }

      // 1. Resolve Drop-off Place from incoming coordinates
      Place dropPlace;
      if (target.coordinates != null) {
        final point = target.coordinates!;
        String? resolvedAddress;
        try {
          resolvedAddress = await MapsService.instance.reverseGeocode(point);
        } catch (_) {}

        if (resolvedAddress != null && resolvedAddress.trim().isNotEmpty) {
          final parts = resolvedAddress.split(',').map((s) => s.trim()).toList();
          final name = target.label ?? parts.first;
          final area = parts.length > 1 ? parts.sublist(1).join(', ') : 'Shared Location';
          dropPlace = Place(name, area, point);
        } else {
          dropPlace = Place(
            target.label ?? 'Shared Location',
            'Lat: ${point.latitude.toStringAsFixed(4)}, Lng: ${point.longitude.toStringAsFixed(4)}',
            point,
          );
        }
      } else if (target.queryText != null && target.queryText!.isNotEmpty) {
        final searchResults = searchPlaces(target.queryText!);
        if (searchResults.isNotEmpty) {
          dropPlace = searchResults.first;
        } else {
          return;
        }
      } else {
        return;
      }

      // 2. Resolve Pickup Place from user's live GPS
      final pickupPlace = await MapsService.instance.currentLocationAsPlace() ??
          const Place('Current Location', 'Live GPS', LatLng(6.9271, 79.8420));

      // 3. Navigate to ride vehicle selection screen
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => VehicleSelectionScreen(
            pickup: pickupPlace,
            drop: dropPlace,
            tripType: 'one_way',
          ),
        ),
      );
    } catch (e) {
      debugPrint('[LocationIntentService] Error handling location intent: $e');
    }
  }

  void _showActiveRideAlert(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You have an active ride in progress. Complete or cancel it before booking another.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  /// Parses geo:, google.navigation:, and Google Maps URLs into coordinates and labels
  Future<ParsedLocationTarget?> parseLocationUri(String rawUri) async {
    final uri = Uri.tryParse(rawUri);
    if (uri == null) return null;

    final scheme = uri.scheme.toLowerCase();

    // 1. Handle geo: scheme
    if (scheme == 'geo') {
      return _parseGeoScheme(uri);
    }

    // 2. Handle google.navigation: scheme
    if (scheme == 'google.navigation') {
      final q = uri.queryParameters['q'];
      if (q != null) {
        final coords = _extractCoords(q);
        if (coords != null) return ParsedLocationTarget(coordinates: coords);
      }
    }

    // 3. Handle Google Maps Web URLs
    if (scheme == 'http' || scheme == 'https') {
      final host = uri.host.toLowerCase();
      if (host.contains('maps.google.') || host.contains('goo.gl')) {
        return _parseMapsUrl(uri);
      }
    }

    return null;
  }

  ParsedLocationTarget? _parseGeoScheme(Uri uri) {
    // A geo URI can be formatted as:
    // geo:6.9271,79.8420
    // geo:6.9271,79.8420?q=6.9271,79.8420
    // geo:0,0?q=6.9271,79.8420(Label)
    // geo:0,0?q=Colombo+Fort
    final q = uri.queryParameters['q'];
    if (q != null && q.isNotEmpty) {
      String? label;
      final labelMatch = RegExp(r'\((.*?)\)').firstMatch(q);
      if (labelMatch != null) {
        label = Uri.decodeComponent(labelMatch.group(1) ?? '').trim();
        if (label.length > 80) label = label.substring(0, 80);
      }

      final coords = _extractCoords(q);
      if (coords != null) {
        return ParsedLocationTarget(coordinates: coords, label: label);
      }

      final cleanQuery = Uri.decodeComponent(q.replaceAll(RegExp(r'\(.*?\)'), '').trim());
      if (cleanQuery.isNotEmpty) {
        return ParsedLocationTarget(queryText: cleanQuery);
      }
    }

    // If q is not present or didn't yield coords, parse schemeSpecificPart
    final ssp = uri.schemeSpecificPart;
    final coords = _extractCoords(ssp);
    if (coords != null) {
      return ParsedLocationTarget(coordinates: coords);
    }

    return null;
  }

  Future<ParsedLocationTarget?> _parseMapsUrl(Uri uri) async {
    // Strictly restrict allowed domains for redirects to prevent SSRF
    final host = uri.host.toLowerCase();
    if (host == 'goo.gl' || host == 'maps.app.goo.gl') {
      try {
        final dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 4),
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
          ),
        );
        final res = await dio.get(uri.toString());
        final redirectLocation = res.headers.value('location');
        if (redirectLocation != null) {
          final redirectedUri = Uri.tryParse(redirectLocation);
          if (redirectedUri != null &&
              (redirectedUri.host.contains('maps.google.') || redirectedUri.host.contains('google.com'))) {
            return _parseMapsUrl(redirectedUri);
          }
        }
      } catch (_) {}
    }

    final q = uri.queryParameters['q'] ??
        uri.queryParameters['daddr'] ??
        uri.queryParameters['destination'] ??
        uri.queryParameters['query'];
    if (q != null) {
      final coords = _extractCoords(q);
      if (coords != null) return ParsedLocationTarget(coordinates: coords);
    }

    // Check for @latitude,longitude in URL path
    final pathMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(uri.path);
    if (pathMatch != null) {
      final lat = double.tryParse(pathMatch.group(1)!);
      final lng = double.tryParse(pathMatch.group(2)!);
      if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
        return ParsedLocationTarget(coordinates: LatLng(lat, lng));
      }
    }

    return null;
  }

  LatLng? _extractCoords(String input) {
    final match = RegExp(r'(-?\d+\.\d+),\s*(-?\d+\.\d+)').firstMatch(input);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      if (lat != null && lng != null && _isValidCoordinate(lat, lng)) {
        return LatLng(lat, lng);
      }
    }
    return null;
  }

  bool _isValidCoordinate(double lat, double lng) {
    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }
}

class ParsedLocationTarget {
  final LatLng? coordinates;
  final String? label;
  final String? queryText;

  ParsedLocationTarget({this.coordinates, this.label, this.queryText});
}

