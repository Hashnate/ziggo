import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'maps_service.dart';

/// Where a point is along a route.
class RoutePosition {
  /// The route segment it is nearest to (between points[segment] and points[segment + 1]).
  final int segment;

  /// Metres from the start of the route to the nearest point on it.
  final double along;

  /// Metres from the point to the route.
  final double offMeters;

  const RoutePosition(this.segment, this.along, this.offMeters);
}

/// A route's shape, worked out once per route: the distance along it to every
/// point and to every step's start. With it the phone shrinks the line and finds
/// the next turn as the driver moves, without asking the server or Google again.
class RouteGeometry {
  RouteGeometry(this.points, this.steps) {
    _cum = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      _cum[i] = _cum[i - 1] + _meters(points[i - 1], points[i]);
    }
    _stepAlong = [for (final s in steps) points.length < 2 ? 0.0 : locate(s.startLocation).along];
  }

  final List<LatLng> points;
  final List<DirectionStep> steps;
  late final List<double> _cum;
  late final List<double> _stepAlong;

  /// Length of the route in metres.
  double get length => _cum.isEmpty ? 0 : _cum.last;

  static double _meters(LatLng a, LatLng b) {
    final kx = 111320.0 * math.cos(a.latitude * math.pi / 180);
    final dx = (b.longitude - a.longitude) * kx;
    final dy = (b.latitude - a.latitude) * 110540.0;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Where [at] is along the route (flat-earth maths; fine at city scale and cheap
  /// enough for every animation frame).
  RoutePosition locate(LatLng at) {
    if (points.length < 2) {
      return RoutePosition(0, 0, points.isEmpty ? double.infinity : _meters(at, points.first));
    }
    final kx = 111320.0 * math.cos(at.latitude * math.pi / 180);
    const ky = 110540.0;
    var bestSeg = 0;
    var bestT = 0.0;
    var best = double.infinity;
    var ax = (points[0].longitude - at.longitude) * kx;
    var ay = (points[0].latitude - at.latitude) * ky;
    for (var i = 0; i < points.length - 1; i++) {
      final bx = (points[i + 1].longitude - at.longitude) * kx;
      final by = (points[i + 1].latitude - at.latitude) * ky;
      final dx = bx - ax;
      final dy = by - ay;
      final seg = dx * dx + dy * dy;
      final t = seg == 0 ? 0.0 : (-(ax * dx + ay * dy) / seg).clamp(0.0, 1.0);
      final px = ax + t * dx;
      final py = ay + t * dy;
      final d = math.sqrt(px * px + py * py);
      if (d < best) {
        best = d;
        bestSeg = i;
        bestT = t;
      }
      ax = bx;
      ay = by;
    }
    final along = _cum[bestSeg] + bestT * (_cum[bestSeg + 1] - _cum[bestSeg]);
    return RoutePosition(bestSeg, along, best);
  }

  /// The part of the route still ahead of [at], starting at [at].
  List<LatLng> remaining(LatLng at) {
    if (points.length < 2) return points;
    final p = locate(at);
    return [at, ...points.sublist(p.segment + 1)];
  }

  /// The next turn ahead of [at], with [DirectionStep.distanceM] set to the
  /// distance to it. Past the last turn: the last step, with the distance to the
  /// end of the route. Null when the route has no steps.
  DirectionStep? nextTurn(LatLng at) {
    if (steps.isEmpty) return null;
    final along = locate(at).along;
    for (var i = 1; i < steps.length; i++) {
      if (_stepAlong[i] > along + 5) {
        return _withDistance(steps[i], _stepAlong[i] - along);
      }
    }
    return _withDistance(steps.last, math.max(0, length - along));
  }

  static DirectionStep _withDistance(DirectionStep s, double meters) => DirectionStep(
        instruction: s.instruction,
        maneuver: s.maneuver,
        distanceM: meters,
        durationS: s.durationS,
        startLocation: s.startLocation,
        endLocation: s.endLocation,
      );
}
