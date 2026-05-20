import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

const LatLng kColomboCenter = LatLng(6.9271, 79.8612);

gmaps.LatLng _g(LatLng p) => gmaps.LatLng(p.latitude, p.longitude);

class ZiggoMarker {
  final LatLng point;
  final IconData icon;
  final Color color;
  final double size;
  // Optional rasterised image (PNG asset) shown instead of the default colored
  // pin. Used for nearby-driver vehicle markers on the customer map.
  final String? assetPath;
  const ZiggoMarker({
    required this.point,
    required this.icon,
    required this.color,
    this.size = 36,
    this.assetPath,
  });
}

ZiggoMarker pinMarker({
  required LatLng point,
  required IconData icon,
  required Color color,
  double size = 36,
  String? assetPath,
}) {
  return ZiggoMarker(
    point: point,
    icon: icon,
    color: color,
    size: size,
    assetPath: assetPath,
  );
}

class ZiggoPolyline {
  final List<LatLng> points;
  final double strokeWidth;
  final Color color;
  const ZiggoPolyline({
    required this.points,
    this.strokeWidth = 4,
    required this.color,
  });
}

class ZiggoMapController {
  gmaps.GoogleMapController? _c;

  void _attach(gmaps.GoogleMapController c) => _c = c;

  bool get isReady => _c != null;

  Future<void> moveTo(LatLng target, {double zoom = 15}) async {
    await _c?.animateCamera(gmaps.CameraUpdate.newLatLngZoom(_g(target), zoom));
  }

  Future<void> fitBounds(List<LatLng> points, {double padding = 60}) async {
    if (_c == null || points.isEmpty) return;
    if (points.length == 1) {
      await moveTo(points.first, zoom: 15);
      return;
    }
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final bounds = gmaps.LatLngBounds(
      southwest: gmaps.LatLng(minLat, minLng),
      northeast: gmaps.LatLng(maxLat, maxLng),
    );
    await _c?.animateCamera(gmaps.CameraUpdate.newLatLngBounds(bounds, padding));
  }

  void dispose() => _c = null;
}

double _hueFor(Color color) {
  if (color.computeLuminance() < 0.16) {
    return gmaps.BitmapDescriptor.hueViolet;
  }
  return HSLColor.fromColor(color).hue;
}

class ZiggoMap extends StatefulWidget {
  final ZiggoMapController? controller;
  final LatLng center;
  final double zoom;
  final List<ZiggoMarker> markers;
  final List<ZiggoPolyline> polylines;
  final bool interactive;
  final bool showMyLocation;
  final void Function(LatLng)? onTap;

  const ZiggoMap({
    super.key,
    this.controller,
    this.center = kColomboCenter,
    this.zoom = 14,
    this.markers = const [],
    this.polylines = const [],
    this.interactive = true,
    this.showMyLocation = false,
    this.onTap,
  });

  @override
  State<ZiggoMap> createState() => _ZiggoMapState();
}

class _ZiggoMapState extends State<ZiggoMap> {
  bool _locationGranted = false;

  // Process-wide cache so flipping screens or polling drivers every 6 s
  // doesn't re-decode the same PNG over and over.
  static final Map<String, gmaps.BitmapDescriptor> _iconCache = {};
  final Set<String> _loadingAssets = {};

  @override
  void initState() {
    super.initState();
    if (widget.showMyLocation) _ensureLocationPermission();
  }

  Future<void> _ensureIcon(String assetPath) async {
    if (_iconCache.containsKey(assetPath) || _loadingAssets.contains(assetPath)) {
      return;
    }
    _loadingAssets.add(assetPath);
    try {
      final desc = await gmaps.BitmapDescriptor.asset(
        const ImageConfiguration(size: Size(40, 40), devicePixelRatio: 2.5),
        assetPath,
      );
      _iconCache[assetPath] = desc;
      if (mounted) setState(() {});
    } catch (_) {
      // Asset missing or decode failed — leave the slot empty so the marker
      // falls back to the default colored pin.
    } finally {
      _loadingAssets.remove(assetPath);
    }
  }

  Future<void> _ensureLocationPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      final granted = perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
      if (!mounted) return;
      if (granted != _locationGranted) {
        setState(() => _locationGranted = granted);
      }
    } catch (_) {
      // GPS not available (emulator without location, web, etc.) — silently no-op.
    }
  }

  @override
  Widget build(BuildContext context) {
    final gMarkers = <gmaps.Marker>{};
    for (var i = 0; i < widget.markers.length; i++) {
      final m = widget.markers[i];
      gmaps.BitmapDescriptor icon;
      Offset anchor = const Offset(0.5, 1.0);
      if (m.assetPath != null) {
        final cached = _iconCache[m.assetPath!];
        if (cached != null) {
          icon = cached;
          // PNG vehicle pin is centred on the location, not stem-anchored.
          anchor = const Offset(0.5, 0.5);
        } else {
          // Kick off the load; rebuild will pick it up when ready.
          _ensureIcon(m.assetPath!);
          icon = gmaps.BitmapDescriptor.defaultMarkerWithHue(_hueFor(m.color));
        }
      } else {
        icon = gmaps.BitmapDescriptor.defaultMarkerWithHue(_hueFor(m.color));
      }
      gMarkers.add(
        gmaps.Marker(
          markerId: gmaps.MarkerId('m$i'),
          position: _g(m.point),
          icon: icon,
          anchor: anchor,
        ),
      );
    }

    final gPolylines = <gmaps.Polyline>{};
    for (var i = 0; i < widget.polylines.length; i++) {
      final p = widget.polylines[i];
      gPolylines.add(
        gmaps.Polyline(
          polylineId: gmaps.PolylineId('p$i'),
          points: p.points.map(_g).toList(),
          width: p.strokeWidth.round(),
          color: p.color,
        ),
      );
    }

    final showMe = widget.showMyLocation && _locationGranted;

    return gmaps.GoogleMap(
      initialCameraPosition:
          gmaps.CameraPosition(target: _g(widget.center), zoom: widget.zoom),
      markers: gMarkers,
      polylines: gPolylines,
      myLocationEnabled: showMe,
      myLocationButtonEnabled: showMe,
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      scrollGesturesEnabled: widget.interactive,
      zoomGesturesEnabled: widget.interactive,
      onTap: widget.onTap == null
          ? null
          : (pos) => widget.onTap!(LatLng(pos.latitude, pos.longitude)),
      onMapCreated: (c) => widget.controller?._attach(c),
    );
  }
}
