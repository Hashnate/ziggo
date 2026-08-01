import 'dart:ui' as ui;

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

Future<CustomMarkerData> _createCustomMarkerBitmap(String label, Color color, IconData? icon, double pixelRatio) async {
  final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(pictureRecorder);
  canvas.scale(pixelRatio);
  
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

    if (icon != null) {
      final TextPainter iconPainter = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 12.0,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      iconPainter.layout();
      iconPainter.paint(
        canvas,
        Offset(centerX - iconPainter.width / 2, centerY - iconPainter.height / 2),
      );
    } else {
      // Draw center dot inner fill
      final Paint dotInnerPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(centerX, centerY), 4.5, dotInnerPaint);
    }

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
      (width * pixelRatio).toInt(),
      (height * pixelRatio).toInt(),
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
  
  if (icon != null) {
    final TextPainter iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 14.0,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    iconPainter.layout();
    iconPainter.paint(
      canvas,
      Offset(centerX - iconPainter.width / 2, centerY - iconPainter.height / 2),
    );
  } else {
    // 5. Draw Center dot inner fill
    final Paint dotInnerPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), 5.5, dotInnerPaint);
  }
  
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
    (width * pixelRatio).toInt(),
    (height * pixelRatio).toInt(),
  );
  final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  final Uint8List uint8List = byteData!.buffer.asUint8List();
  
  return CustomMarkerData(
    gmaps.BitmapDescriptor.fromBytes(uint8List),
    Offset(0.5, centerY / height),
  );
}

Future<CustomMarkerData> _createIconOnlyMarkerBitmap(IconData icon, Color color, double size, double pixelRatio) async {
  final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(pictureRecorder);
  canvas.scale(pixelRatio);

  final double width = size + 20;
  final double height = size + 30;
  final double centerX = width / 2;
  final double centerY = size / 2 + 5;

  // Shadow
  final Paint shadowPaint = Paint()
    ..color = Colors.black.withOpacity(0.12)
    ..style = PaintingStyle.fill;
  canvas.drawCircle(Offset(centerX, centerY + 3), size / 2, shadowPaint);

  // Background circle
  final Paint circlePaint = Paint()
    ..color = color
    ..style = PaintingStyle.fill;
  canvas.drawCircle(Offset(centerX, centerY), size / 2, circlePaint);
  
  // White border
  final Paint borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3.0;
  canvas.drawCircle(Offset(centerX, centerY), size / 2, borderPaint);

  // Icon
  final TextPainter iconPainter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.6,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  );
  iconPainter.layout();
  iconPainter.paint(
    canvas,
    Offset(centerX - iconPainter.width / 2, centerY - iconPainter.height / 2),
  );

  // Shadow for dot
  final Paint dotShadowPaint = Paint()
    ..color = Colors.black.withOpacity(0.2)
    ..style = PaintingStyle.fill;
  canvas.drawCircle(Offset(centerX, height - 8), 5, dotShadowPaint);

  // Small black dot at bottom
  final Paint dotPaint = Paint()
    ..color = Colors.black
    ..style = PaintingStyle.fill;
  
  // White border for dot
  final Paint dotBorderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;
  
  canvas.drawCircle(Offset(centerX, height - 10), 7, dotBorderPaint);
  canvas.drawCircle(Offset(centerX, height - 10), 4.5, dotPaint);

  final ui.Image img = await pictureRecorder.endRecording().toImage(
    (width * pixelRatio).toInt(),
    (height * pixelRatio).toInt(),
  );
  final ByteData? byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  final Uint8List uint8List = byteData!.buffer.asUint8List();

  return CustomMarkerData(
    gmaps.BitmapDescriptor.fromBytes(uint8List),
    Offset(0.5, (height - 10) / height),
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

class ZiggoPolygon {
  final List<LatLng> points;
  final Color fillColor;
  final Color strokeColor;
  final int strokeWidth;
  const ZiggoPolygon({
    required this.points,
    this.fillColor = const Color(0x33DC3545),
    this.strokeColor = const Color(0x88DC3545),
    this.strokeWidth = 2,
  });
}

class ZiggoCircle {
  final LatLng center;
  final double radius;
  final Color fillColor;
  final Color strokeColor;
  final int strokeWidth;
  const ZiggoCircle({
    required this.center,
    required this.radius,
    this.fillColor = const Color(0x220099FF),
    this.strokeColor = const Color(0x660099FF),
    this.strokeWidth = 2,
  });
}

class ZiggoMapController {
  gmaps.GoogleMapController? _c;

  void _attach(gmaps.GoogleMapController c) => _c = c;

  bool get isReady => _c != null;

  Future<void> moveTo(LatLng target, {double zoom = 15}) async {
    try {
      await _c?.animateCamera(gmaps.CameraUpdate.newLatLngZoom(_g(target), zoom));
    } catch (e) {
      debugPrint("ZiggoMapController.moveTo error: $e");
    }
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
    try {
      await _c?.animateCamera(gmaps.CameraUpdate.newLatLngBounds(bounds, padding));
    } catch (e) {
      debugPrint("ZiggoMapController.fitBounds error: $e");
    }
  }

  Future<void> startNavigation(LatLng target, {double zoom = 18.5, double tilt = 45.0, double bearing = 0.0}) async {
    try {
      await _c?.animateCamera(gmaps.CameraUpdate.newCameraPosition(
        gmaps.CameraPosition(
          target: _g(target),
          zoom: zoom,
          tilt: tilt,
          bearing: bearing,
        ),
      ));
    } catch (e) {
      debugPrint("ZiggoMapController.startNavigation error: $e");
    }
  }

  void dispose() => _c = null;
}

double _hueFor(Color color) {
  if (color.computeLuminance() < 0.16) {
    return gmaps.BitmapDescriptor.hueViolet;
  }
  return HSLColor.fromColor(color).hue;
}

/// Google Maps "night" style — dark canvas used on the driver home map to
/// mirror the PickMe driver look. Applied via [ZiggoMap.darkMode].
const String kDarkMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#1d2c4d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8ec3b9"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#1a3646"}]},
  {"featureType":"administrative.country","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},
  {"featureType":"administrative.land_parcel","elementType":"labels.text.fill","stylers":[{"color":"#64779e"}]},
  {"featureType":"administrative.province","elementType":"geometry.stroke","stylers":[{"color":"#4b6878"}]},
  {"featureType":"landscape.man_made","elementType":"geometry.stroke","stylers":[{"color":"#334e87"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#023e58"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#283d6a"}]},
  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#6f9ba5"}]},
  {"featureType":"poi","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"poi.park","elementType":"geometry.fill","stylers":[{"color":"#023e58"}]},
  {"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#3C7680"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#304a7d"}]},
  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
  {"featureType":"road","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#2c6675"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#255763"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#b0d5ce"}]},
  {"featureType":"road.highway","elementType":"labels.text.stroke","stylers":[{"color":"#023e58"}]},
  {"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#98a5be"}]},
  {"featureType":"transit","elementType":"labels.text.stroke","stylers":[{"color":"#1d2c4d"}]},
  {"featureType":"transit.line","elementType":"geometry.fill","stylers":[{"color":"#283d6a"}]},
  {"featureType":"transit.station","elementType":"geometry","stylers":[{"color":"#3a4762"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0e1626"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#4e6d70"}]}
]
''';

class ZiggoMap extends StatefulWidget {
  final ZiggoMapController? controller;
  final LatLng center;
  final double zoom;
  final List<ZiggoMarker> markers;
  final List<ZiggoPolyline> polylines;
  final List<ZiggoPolygon> polygons;
  final List<ZiggoCircle> circles;
  final bool interactive;
  final bool showMyLocation;
  final bool darkMode;
  final void Function(LatLng)? onTap;
  final void Function(LatLng)? onPositionChanged;
  final VoidCallback? onMapCreated;

  const ZiggoMap({
    super.key,
    this.controller,
    this.center = kColomboCenter,
    this.zoom = 14,
    this.markers = const [],
    this.polylines = const [],
    this.polygons = const [],
    this.circles = const [],
    this.interactive = true,
    this.showMyLocation = false,
    this.darkMode = false,
    this.onTap,
    this.onPositionChanged,
    this.onMapCreated,
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

  @override
  void dispose() {
    widget.controller?.dispose();
    super.dispose();
  }

  Future<void> _ensureLabelIcon(String label, Color color, IconData? icon, double pixelRatio) async {
    final key = '$label-${color.value}-$pixelRatio-${icon?.codePoint}';
    if (_customLabelCache.containsKey(key) || _loadingLabels.contains(key)) {
      return;
    }
    _loadingLabels.add(key);
    try {
      final data = await _createCustomMarkerBitmap(label, color, icon, pixelRatio);
      _customLabelCache[key] = data.bitmap;
      _customLabelAnchors[key] = data.anchor;
      if (mounted) setState(() {});
    } catch (_) {
    } finally {
      _loadingLabels.remove(key);
    }
  }

  Future<void> _ensureIconMarker(IconData icon, Color color, double size, double pixelRatio) async {
    final key = 'icon-${icon.codePoint}-${color.value}-$size-$pixelRatio';
    if (_customLabelCache.containsKey(key) || _loadingLabels.contains(key)) {
      return;
    }
    _loadingLabels.add(key);
    try {
      final data = await _createIconOnlyMarkerBitmap(icon, color, size, pixelRatio);
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
    final double pixelRatio = MediaQuery.of(context).devicePixelRatio;
    final gMarkers = <gmaps.Marker>{};
    for (var i = 0; i < widget.markers.length; i++) {
      final m = widget.markers[i];
      gmaps.BitmapDescriptor icon;
      Offset anchor = const Offset(0.5, 1.0);
      
      if (m.label != null) {
        final key = '${m.label}-${m.color.value}-$pixelRatio-${m.icon.codePoint}';
        final cached = _customLabelCache[key];
        if (cached != null) {
          icon = cached;
          anchor = _customLabelAnchors[key] ?? const Offset(0.5, 0.70);
        } else {
          _ensureLabelIcon(m.label!, m.color, m.icon, pixelRatio);
          icon = gmaps.BitmapDescriptor.defaultMarkerWithHue(_hueFor(m.color));
        }
      } else if (m.assetPath != null) {
        final targetWidth = (m.size * 1.5 * pixelRatio).round();
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
        final key = 'icon-${m.icon.codePoint}-${m.color.value}-${m.size}-$pixelRatio';
        final cached = _customLabelCache[key];
        if (cached != null) {
          icon = cached;
          anchor = _customLabelAnchors[key] ?? const Offset(0.5, 0.70);
        } else {
          _ensureIconMarker(m.icon, m.color, m.size, pixelRatio);
          icon = gmaps.BitmapDescriptor.defaultMarkerWithHue(_hueFor(m.color));
        }
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

    final gPolygons = <gmaps.Polygon>{};
    for (var i = 0; i < widget.polygons.length; i++) {
      final p = widget.polygons[i];
      gPolygons.add(
        gmaps.Polygon(
          polygonId: gmaps.PolygonId('poly$i'),
          points: p.points.map(_g).toList(),
          fillColor: p.fillColor,
          strokeColor: p.strokeColor,
          strokeWidth: p.strokeWidth,
        ),
      );
    }

    final gCircles = <gmaps.Circle>{};
    for (var i = 0; i < widget.circles.length; i++) {
      final c = widget.circles[i];
      gCircles.add(
        gmaps.Circle(
          circleId: gmaps.CircleId('c$i'),
          center: _g(c.center),
          radius: c.radius,
          fillColor: c.fillColor,
          strokeColor: c.strokeColor,
          strokeWidth: c.strokeWidth,
        ),
      );
    }

    final showMe = widget.showMyLocation && _locationGranted;

    return gmaps.GoogleMap(
      initialCameraPosition:
          gmaps.CameraPosition(target: _g(widget.center), zoom: widget.zoom),
      style: widget.darkMode ? kDarkMapStyle : null,
      markers: gMarkers,
      polylines: gPolylines,
      polygons: gPolygons,
      circles: gCircles,
      myLocationEnabled: showMe,
      myLocationButtonEnabled: false,
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
      onCameraMove: widget.onPositionChanged == null
          ? null
          : (pos) => widget.onPositionChanged!(LatLng(pos.target.latitude, pos.target.longitude)),
      onMapCreated: (c) {
        widget.controller?._attach(c);
        widget.onMapCreated?.call();
      },
    );
  }
}
