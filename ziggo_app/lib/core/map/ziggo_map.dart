import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  // Optional label to render a custom bubble marker instead of a default pin
  final String? label;
  final double rotation;
  
  const ZiggoMarker({
    required this.point,
    required this.icon,
    required this.color,
    this.size = 36,
    this.assetPath,
    this.label,
    this.rotation = 0.0,
  });
}

ZiggoMarker pinMarker({
  required LatLng point,
  required IconData icon,
  required Color color,
  double size = 36,
  String? assetPath,
  String? label,
  double rotation = 0.0,
}) {
  return ZiggoMarker(
    point: point,
    icon: icon,
    color: color,
    size: size,
    assetPath: assetPath,
    label: label,
    rotation: rotation,
  );
}

class CustomMarkerData {
  final gmaps.BitmapDescriptor bitmap;
  final Offset anchor;
  CustomMarkerData(this.bitmap, this.anchor);
}

Future<CustomMarkerData> _createCustomMarkerBitmap(String label, Color color) async {
  final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(pictureRecorder);
  
  String pillText = '';
  String mainText = label;
  bool isSplit = false;
  if (label.contains('|')) {
    final parts = label.split('|');
    pillText = parts[0].trim();
    mainText = parts[1].trim();
    isSplit = true;
  }

  if (isSplit) {
    final TextPainter pillPainter = TextPainter(textDirection: TextDirection.ltr);
    pillPainter.text = TextSpan(
      text: pillText,
      style: const TextStyle(
        fontSize: 12,
        color: Colors.white,
        fontWeight: FontWeight.w800,
      ),
    );
    pillPainter.layout();

    String displayMainText = mainText;
    if (displayMainText.length > 22) {
      displayMainText = '${displayMainText.substring(0, 20)}...';
    }

    final TextPainter mainPainter = TextPainter(textDirection: TextDirection.ltr);
    mainPainter.text = TextSpan(
      text: displayMainText,
      style: const TextStyle(
        fontSize: 12,
        color: Colors.black87,
        fontWeight: FontWeight.w700,
      ),
    );
    mainPainter.layout();

    final double pillTextWidth = pillPainter.width;
    final double pillTextHeight = pillPainter.height;
    final double mainTextWidth = mainPainter.width;
    final double mainTextHeight = mainPainter.height;

    final double pillPaddingX = 10.0;
    final double pillPaddingY = 5.0;
    final double pillWidth = pillTextWidth + (pillPaddingX * 2);
    final double pillHeight = pillTextHeight + (pillPaddingY * 2);

    final double bubblePaddingX = 8.0;
    final double bubblePaddingY = 6.0;
    final double gap = 8.0;
    
    final double bubbleWidth = bubblePaddingX + pillWidth + gap + mainTextWidth + bubblePaddingX;
    final double bubbleHeight = pillHeight + (bubblePaddingY * 2);

    final double width = bubbleWidth + 24;
    final double height = bubbleHeight + 60;

    final double centerX = width / 2;
    final double centerY = height - 20;

    // Draw background outer glow
    final Paint circlePaint = Paint()
      ..color = color.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), 20, circlePaint);

    // Draw center dot outer white border
    final Paint dotOuterPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), 7.5, dotOuterPaint);

    // Draw center dot inner fill
    final Paint dotInnerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), 4.5, dotInnerPaint);

    // Draw bubble shadow
    final double bubbleY = 8.0;
    final double bubbleX = (width - bubbleWidth) / 2;
    final RRect bubbleRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bubbleX, bubbleY, bubbleWidth, bubbleHeight),
      Radius.circular(bubbleHeight / 2),
    );

    final Paint shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(bubbleRect.shift(const Offset(0, 2)), shadowPaint);

    // Draw bubble white background
    final Paint bgPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRRect(bubbleRect, bgPaint);

    // Draw bubble outline border
    final Paint borderPaint = Paint()
      ..color = Colors.grey.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(bubbleRect, borderPaint);

    // Draw colored pill background
    final double pillX = bubbleX + bubblePaddingX;
    final double pillY = bubbleY + bubblePaddingY;
    final RRect pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pillX, pillY, pillWidth, pillHeight),
      Radius.circular(pillHeight / 2),
    );
    final Paint pillBgPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(pillRect, pillBgPaint);

    // Draw pill text
    pillPainter.paint(
      canvas,
      Offset(
        pillX + pillPaddingX,
        pillY + pillPaddingY,
      ),
    );

    // Draw main text
    mainPainter.paint(
      canvas,
      Offset(
        pillX + pillWidth + gap,
        bubbleY + (bubbleHeight - mainTextHeight) / 2,
      ),
    );

    final ui.Image img = await pictureRecorder.endRecording().toImage(
      width.toInt(),
      height.toInt(),
    );
    final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List uint8List = byteData!.buffer.asUint8List();

    return CustomMarkerData(
      gmaps.BitmapDescriptor.fromBytes(uint8List),
      Offset(0.5, centerY / height),
    );
  }

  // Fallback / legacy format (no '|' delimiter)
  // 1. Measure the text first to determine canvas dimensions
  final TextPainter textPainter = TextPainter(
    textDirection: TextDirection.ltr,
  );
  textPainter.text = TextSpan(
    text: label,
    style: const TextStyle(
      fontSize: 16,
      color: Colors.white,
      fontWeight: FontWeight.w900,
    ),
  );
  textPainter.layout();
  
  final double textWidth = textPainter.width;
  final double textHeight = textPainter.height;
  
  // 2. Calculate dynamic dimensions
  final double bubbleWidth = textWidth + 30;
  final double bubbleHeight = textHeight + 16;
  
  final double width = (bubbleWidth > 70 ? bubbleWidth : 70) + 20;
  final double height = bubbleHeight + 60;
  
  final double centerX = width / 2;
  final double centerY = height - 30;
  
  // 3. Draw Background translucent circle
  final Paint circlePaint = Paint()
    ..color = color.withOpacity(0.15)
    ..style = PaintingStyle.fill;
  canvas.drawCircle(Offset(centerX, centerY), 28, circlePaint);
  
  // 4. Draw Center dot outer white border
  final Paint dotOuterPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  canvas.drawCircle(Offset(centerX, centerY), 9, dotOuterPaint);
  
  // 5. Draw Center dot inner fill
  final Paint dotInnerPaint = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.fill;
  canvas.drawCircle(Offset(centerX, centerY), 5.5, dotInnerPaint);
  
  // 6. Define bubble rect and tail path
  final double bubbleY = 8;
  final double bubbleX = (width - bubbleWidth) / 2;
  
  final RRect bubbleRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(bubbleX, bubbleY, bubbleWidth, bubbleHeight),
    Radius.circular(bubbleHeight / 2),
  );
  
  final ui.Path tailPath = ui.Path();
  final double tailTop = bubbleY + bubbleHeight;
  tailPath.moveTo(centerX - 7, tailTop);
  tailPath.lineTo(centerX + 7, tailTop);
  tailPath.lineTo(centerX, tailTop + 10);
  tailPath.close();

  // Combine into a single shape
  final ui.Path bubblePath = ui.Path()..addRRect(bubbleRect);
  final ui.Path combinedPath = ui.Path.combine(ui.PathOperation.union, bubblePath, tailPath);

  // 7. Draw the white border stroke
  final Paint borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0
    ..strokeJoin = StrokeJoin.round;
  canvas.drawPath(combinedPath, borderPaint);

  // 8. Draw the colored fill
  final Paint bubblePaint = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  canvas.drawPath(combinedPath, bubblePaint);
  
  // 9. Draw text
  textPainter.paint(
    canvas,
    Offset(
      centerX - textWidth / 2,
      bubbleY + (bubbleHeight - textHeight) / 2,
    ),
  );
  
  // 10. Render to image
  final ui.Image img = await pictureRecorder.endRecording().toImage(
    width.toInt(),
    height.toInt(),
  );
  final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  final Uint8List uint8List = byteData!.buffer.asUint8List();
  
  return CustomMarkerData(
    gmaps.BitmapDescriptor.fromBytes(uint8List),
    Offset(0.5, centerY / height),
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
  static final Map<String, gmaps.BitmapDescriptor> _customLabelCache = {};
  static final Map<String, Offset> _customLabelAnchors = {};
  final Set<String> _loadingAssets = {};
  final Set<String> _loadingLabels = {};

  @override
  void initState() {
    super.initState();
    if (widget.showMyLocation) _ensureLocationPermission();
  }

  Future<void> _ensureLabelIcon(String label, Color color) async {
    final key = '$label-${color.value}';
    if (_customLabelCache.containsKey(key) || _loadingLabels.contains(key)) {
      return;
    }
    _loadingLabels.add(key);
    try {
      final data = await _createCustomMarkerBitmap(label, color);
      _customLabelCache[key] = data.bitmap;
      _customLabelAnchors[key] = data.anchor;
      if (mounted) setState(() {});
    } catch (_) {
    } finally {
      _loadingLabels.remove(key);
    }
  }

  Future<Uint8List> _getBytesFromAsset(String path, int width) async {
    final ByteData data = await rootBundle.load(path);
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ByteData? byteData = await fi.image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _ensureIcon(String assetPath, int width) async {
    final key = '$assetPath-$width';
    if (_iconCache.containsKey(key) || _loadingAssets.contains(key)) {
      return;
    }
    _loadingAssets.add(key);
    try {
      final Uint8List markerIcon = await _getBytesFromAsset(assetPath, width);
      final desc = gmaps.BitmapDescriptor.fromBytes(markerIcon);
      _iconCache[key] = desc;
      if (mounted) setState(() {});
    } catch (_) {
      // Asset missing or decode failed — leave the slot empty so the marker
      // falls back to the default colored pin.
    } finally {
      _loadingAssets.remove(key);
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
      
      if (m.label != null) {
        final key = '${m.label}-${m.color.value}';
        final cached = _customLabelCache[key];
        if (cached != null) {
          icon = cached;
          anchor = _customLabelAnchors[key] ?? const Offset(0.5, 0.70);
        } else {
          _ensureLabelIcon(m.label!, m.color);
          icon = gmaps.BitmapDescriptor.defaultMarkerWithHue(_hueFor(m.color));
        }
      } else if (m.assetPath != null) {
        final targetWidth = (m.size * 1.5).round();
        final key = '${m.assetPath!}-$targetWidth';
        final cached = _iconCache[key];
        if (cached != null) {
          icon = cached;
          // PNG vehicle pin is centred on the location, not stem-anchored.
          anchor = const Offset(0.5, 0.5);
        } else {
          // Kick off the load; rebuild will pick it up when ready.
          _ensureIcon(m.assetPath!, targetWidth);
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
          rotation: m.rotation,
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
