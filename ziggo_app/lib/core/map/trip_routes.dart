import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import 'maps_service.dart';
import 'route_progress.dart';

/// The road route for one booking leg, as the server worked it out.
class TripRoute {
  TripRoute({required this.bookingId, required this.version, required this.leg, required this.route})
      : fetchedAt = DateTime.now();

  final int bookingId;
  final int version;

  /// 'trip' (pickup → stops → drop) | 'to_pickup' | 'to_drop' | null.
  final String? leg;

  /// Null when there is nothing to draw (yet): the apps then draw a straight line.
  final DirectionsResult? route;
  final DateTime fetchedAt;

  late final RouteGeometry? geometry =
      route == null || route!.points.length < 2 ? null : RouteGeometry(route!.points, route!.steps);
}

/// The routes the server worked out for bookings (GET /bookings/{id}/route): one
/// per leg, the same for the driver's and the customer's app. The phone shrinks
/// the line itself as the driver moves. A new route is fetched only when the leg
/// changes, when the server has a newer one (a `route_changed` event or a higher
/// `route_version` on the booking), or when an empty answer is 30 s old.
class TripRoutes {
  static const Duration _retryAfter = Duration(seconds: 30);
  static const Duration _minGap = Duration(seconds: 5);

  final Map<int, TripRoute> _routes = {};
  final Map<int, DateTime> _askedAt = {};
  final Map<int, DateTime> _failedAt = {};
  final Set<int> _loading = {};

  TripRoute? operator [](Object? bookingId) => bookingId is int ? _routes[bookingId] : null;

  /// The leg the server draws for a booking status.
  static String? legFor(String? status) {
    switch (status) {
      case 'searching':
        return 'trip';
      case 'accepted':
      case 'arrived':
        return 'to_pickup';
      case 'started':
        return 'to_drop';
    }
    return null;
  }

  /// The stored route for [booking] if it is for the booking's current leg.
  TripRoute? current(Map<String, dynamic>? booking) {
    final have = this[booking?['id']];
    if (have == null || have.leg != legFor(booking?['status']?.toString())) return null;
    return have;
  }

  /// Fetches [booking]'s route when the phone needs a new one. Cheap when it
  /// doesn't, so screens may call it on every build. True when the route changed.
  Future<bool> ensure(Map<String, dynamic>? booking) async {
    final id = booking?['id'];
    if (id is! int) return false;
    final leg = legFor(booking!['status']?.toString());
    if (leg == null) return false;
    final now = DateTime.now();
    final have = _routes[id];
    final serverVersion = (booking['route_version'] as num?)?.toInt();
    final needed = have == null ||
        have.leg != leg ||
        (serverVersion != null && serverVersion > have.version) ||
        (have.route == null && now.difference(have.fetchedAt) >= _retryAfter);
    if (!needed) return false;
    final failed = _failedAt[id];
    if (failed != null && now.difference(failed) < _retryAfter) return false;
    final asked = _askedAt[id];
    if (asked != null && now.difference(asked) < _minGap) return false;
    return fetch(id);
  }

  /// The route preview for a ride request: asked about a second after it
  /// arrives (the server may still be saving the booking), once more 2 s later
  /// if there was nothing yet. True when a route arrived.
  Future<bool> preview(int bookingId) async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await fetch(bookingId);
    if (_routes[bookingId]?.route == null) {
      await Future<void>.delayed(const Duration(seconds: 2));
      await fetch(bookingId);
    }
    return _routes[bookingId]?.route != null;
  }

  /// Fetches the booking's route now. True when it changed.
  Future<bool> fetch(int bookingId) async {
    if (_loading.contains(bookingId)) return false;
    _loading.add(bookingId);
    _askedAt[bookingId] = DateTime.now();
    try {
      final resp = await ApiClient.instance.dio.get('/bookings/$bookingId/route');
      final data = resp.data;
      if (data is! Map) {
        _failedAt[bookingId] = DateTime.now();
        return false;
      }
      final raw = data['route'];
      final next = TripRoute(
        bookingId: bookingId,
        version: (data['version'] as num?)?.toInt() ?? 0,
        leg: data['leg']?.toString(),
        route: raw is Map ? DirectionsResult.fromServer(Map<String, dynamic>.from(raw)) : null,
      );
      final before = _routes[bookingId];
      _routes[bookingId] = next;
      _failedAt.remove(bookingId);
      if (_routes.length > 30) {
        final oldest = _routes.values.reduce((a, b) => a.fetchedAt.isBefore(b.fetchedAt) ? a : b);
        _routes.remove(oldest.bookingId);
      }
      return before == null ||
          before.version != next.version ||
          before.leg != next.leg ||
          (before.route == null) != (next.route == null);
    } catch (e) {
      if (kDebugMode) debugPrint('[route] booking $bookingId: $e');
      _failedAt[bookingId] = DateTime.now();
      return false;
    } finally {
      _loading.remove(bookingId);
    }
  }
}
