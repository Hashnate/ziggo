import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/ziggo_map.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/glass_card.dart';
import '../booking_provider.dart';
import 'rating_screen.dart';

class RideTrackingScreen extends StatefulWidget {
  const RideTrackingScreen({super.key});

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends State<RideTrackingScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();
  bool _navigatedToRating = false;
  List<LatLng> _routePoints = const [];
  List<DirectionStep> _routeSteps = const [];
  String? _routeKey;
  bool _sheetExpanded = true;
  String? _lastStatus;
  LatLng? _lastCameraDriverLatLng;
  String? _lastCameraStatus;

  // While the booking is in SEARCHING we poll /driver/nearby every 6 s so the
  // customer sees the same wandering-vehicle pins they had on fare estimate.
  Timer? _nearbyTimer;
  List<Map<String, dynamic>> _nearbyDrivers = const [];

  StreamSubscription<Position>? _positionSubscription;
  LatLng? _customerLatLng;
  double? _customerHeading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookingProvider>().loadActive();
    });
    _startPositionUpdates();
  }

  void _startPositionUpdates() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (mounted) {
        setState(() {
          _customerLatLng = LatLng(position.latitude, position.longitude);
          _customerHeading = position.heading;
        });
      }
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _nearbyTimer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  /// Fetches the road route once per unique pickup/drop pair.
  void _ensureRoute(LatLng pickup, LatLng drop) {
    final key = '${pickup.latitude},${pickup.longitude}'
        '-${drop.latitude},${drop.longitude}';
    if (key == _routeKey) return;
    _routeKey = key;
    MapsService.instance.directions(pickup, drop).then((dir) {
      if (mounted && dir != null && dir.points.isNotEmpty) {
        setState(() {
          _routePoints = dir.points;
          _routeSteps = dir.steps;
        });
      }
    });
  }

  void _updateMapCamera(String? status, LatLng pickup, LatLng drop, LatLng? driverLatLng) {
    if (driverLatLng == null) return;
    if (_lastCameraStatus == status &&
        _lastCameraDriverLatLng?.latitude == driverLatLng.latitude &&
        _lastCameraDriverLatLng?.longitude == driverLatLng.longitude) {
      return;
    }
    _lastCameraStatus = status;
    _lastCameraDriverLatLng = driverLatLng;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (status == 'started') {
        _mapController.fitBounds([driverLatLng, drop], padding: 80);
      } else if (status == 'accepted' || status == 'arrived') {
        _mapController.fitBounds([driverLatLng, pickup], padding: 80);
      }
    });
  }

  void _startNearbyPolling(LatLng pickup, String? serviceType) {
    if (_nearbyTimer != null) return;
    _fetchNearbyDrivers(pickup, serviceType);
    _nearbyTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _fetchNearbyDrivers(pickup, serviceType),
    );
  }

  void _stopNearbyPolling() {
    if (_nearbyTimer == null && _nearbyDrivers.isEmpty) return;
    _nearbyTimer?.cancel();
    _nearbyTimer = null;
    if (_nearbyDrivers.isNotEmpty) {
      _nearbyDrivers = const [];
      if (mounted) setState(() {});
    }
  }

  Future<void> _fetchNearbyDrivers(LatLng pickup, String? serviceType) async {
    try {
      final resp = await ApiClient.instance.dio.get(
        '/driver/nearby',
        queryParameters: {
          'lat': pickup.latitude,
          'lng': pickup.longitude,
          'radius_km': 5,
          if (serviceType != null) 'vehicle_type': serviceType,
        },
      );
      if (!mounted) return;
      setState(() {
        _nearbyDrivers = List<Map<String, dynamic>>.from(resp.data as List);
      });
    } catch (_) {
      // Silent — same pattern as fare_estimate_screen.
    }
  }

  String _vehicleAsset(String? type) {
    switch (type) {
      case 'bike':
        return 'assets/icons/top_bike.png';
      case 'tuk':
        return 'assets/icons/top_tuk.png';
      case 'truck':
        return 'assets/icons/top_truck.png';
      case 'van':
      case 'car':
      default:
        return 'assets/icons/top_car.png';
    }
  }

  ({String label, String hint, Color color, IconData icon}) _statusMeta(String? status) {
    switch (status) {
      case 'searching':
        return (
          label: 'Finding your driver',
          hint: 'We\'re matching you with the nearest driver',
          color: AppColors.warning,
          icon: Icons.search_rounded,
        );
      case 'accepted':
        return (
          label: 'Driver on the way',
          hint: 'Your driver is heading to pickup',
          color: AppColors.flash,
          icon: Icons.directions_car_rounded,
        );
      case 'arrived':
        return (
          label: 'Driver has arrived',
          hint: 'Please meet your driver at pickup',
          color: AppColors.success,
          icon: Icons.location_on_rounded,
        );
      case 'started':
        return (
          label: 'Trip in progress',
          hint: 'Enjoy your ride',
          color: AppColors.primary,
          icon: Icons.bolt_rounded,
        );
      case 'completed':
        return (
          label: 'Ride completed',
          hint: 'Thanks for riding with Ziggo',
          color: AppColors.success,
          icon: Icons.check_circle_rounded,
        );
      case 'cancelled':
        return (
          label: 'Ride cancelled',
          hint: '',
          color: AppColors.error,
          icon: Icons.cancel_rounded,
        );
      default:
        return (
          label: 'Loading...',
          hint: '',
          color: AppColors.textTertiary,
          icon: Icons.hourglass_top_rounded,
        );
    }
  }

  List<LatLng> _getRemainingRoute(List<LatLng> routePoints, LatLng? driverLoc) {
    if (routePoints.isEmpty) return [];
    if (driverLoc == null) return routePoints;
    int closestIndex = 0;
    double minSqDistance = double.infinity;
    for (int i = 0; i < routePoints.length; i++) {
      final p = routePoints[i];
      final dLat = driverLoc.latitude - p.latitude;
      final dLng = driverLoc.longitude - p.longitude;
      final sqDist = dLat * dLat + dLng * dLng;
      if (sqDist < minSqDistance) {
        minSqDistance = sqDist;
        closestIndex = i;
      }
    }
    if (closestIndex >= routePoints.length - 1) {
      return [driverLoc, routePoints.last];
    }
    return [driverLoc, ...routePoints.sublist(closestIndex)];
  }

  @override
  Widget build(BuildContext context) {
    final booking = context.watch<BookingProvider>();
    final active = booking.activeBooking;

    if (active == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pickup = LatLng(
      (active['pickup_lat'] as num).toDouble(),
      (active['pickup_lng'] as num).toDouble(),
    );
    final drop = LatLng(
      (active['drop_lat'] as num).toDouble(),
      (active['drop_lng'] as num).toDouble(),
    );
    final driver = active['driver'] as Map<String, dynamic>?;
    final driverLat = driver?['current_lat'] as num?;
    final driverLng = driver?['current_lng'] as num?;
    final status = active['status'] as String?;
    final driverLatLng = (status == 'started' && _customerLatLng != null)
        ? _customerLatLng
        : ((driverLat != null && driverLng != null)
            ? LatLng(driverLat.toDouble(), driverLng.toDouble())
            : null);

    final meta = _statusMeta(status);
    final serviceType = active['service_type'] as String?;

    if (_lastStatus != status) {
      if (status == 'arrived' || status == 'started') {
        _sheetExpanded = false;
      }
      _lastStatus = status;
    }

    _ensureRoute(pickup, drop);
    _updateMapCamera(status, pickup, drop, driverLatLng);

    // Show wandering driver pins only while we're still hunting for a driver.
    // Once accepted, the assigned driver's pin replaces them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (status == 'searching') {
        _startNearbyPolling(pickup, serviceType);
      } else {
        _stopNearbyPolling();
      }
    });

    if (status == 'completed' && !_navigatedToRating) {
      _navigatedToRating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RatingScreen(bookingId: active['id'] as int),
          ),
        );
      });
    }

    final showRemainingRoute = status == 'started';
    final activeRoutePoints = (showRemainingRoute && driverLatLng != null)
        ? _getRemainingRoute(_routePoints, driverLatLng)
        : (_routePoints.isNotEmpty ? _routePoints : [pickup, drop]);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: ZiggoMap(
              controller: _mapController,
              center: pickup,
              zoom: 14,
              showMyLocation: true,
              markers: [
                // Wandering nearby drivers (only while SEARCHING) — render
                // first so pickup/drop pins paint on top.
                for (final d in _nearbyDrivers)
                  pinMarker(
                    point: LatLng(
                      (d['lat'] as num).toDouble(),
                      (d['lng'] as num).toDouble(),
                    ),
                    icon: Icons.local_taxi_rounded,
                    color: AppColors.primary,
                    size: 30,
                    assetPath: _vehicleAsset(d['vehicle_type'] as String?),
                    rotation: (d['heading'] as num?)?.toDouble() ?? 0.0,
                  ),
                pinMarker(
                  point: pickup,
                  icon: Icons.my_location_rounded,
                  color: AppColors.info,
                  label: 'Pickup | ${active['pickup_address'] ?? 'Your Location'}',
                ),
                pinMarker(
                  point: drop,
                  icon: Icons.location_on_rounded,
                  color: AppColors.warning,
                  label: 'Drop | ${active['drop_address'] ?? 'Destination'}',
                ),
                if (driverLatLng != null)
                  pinMarker(
                    point: driverLatLng,
                    icon: Icons.directions_car_rounded,
                    color: Colors.black,
                    assetPath: _vehicleAsset(driver?['vehicle_type'] as String?),
                    rotation: (status == 'started' && _customerHeading != null)
                        ? _customerHeading!
                        : ((driver?['current_heading'] as num?)?.toDouble() ?? 0.0),
                  ),
              ],
              polylines: [
                ZiggoPolyline(
                  points: activeRoutePoints,
                  strokeWidth: 4,
                  color: Colors.black,
                ),
              ],
            ),
          ),
          // Top status pill (glassmorphic over map)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: GlassCard(
                      padding: const EdgeInsets.all(10),
                      radius: 14,
                      blur: 18,
                      tint: Colors.white.withOpacity(0.55),
                      child: const Icon(
                        Icons.arrow_back_rounded,
                        color: AppColors.textPrimary,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // BRD: CD-17 + CD-31 — Share trip with contacts
                  GestureDetector(
                    onTap: _shareTrip,
                    child: GlassCard(
                      padding: const EdgeInsets.all(10),
                      radius: 14,
                      blur: 18,
                      tint: Colors.white.withOpacity(0.55),
                      child: const Icon(Icons.share_location_rounded,
                          color: AppColors.textPrimary, size: 22),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // BRD: CD-17 — SOS panic button
                  GestureDetector(
                    onTap: _triggerSos,
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      radius: 14,
                      blur: 18,
                      tint: AppColors.error.withOpacity(0.85),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.emergency_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text('SOS',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 1.2,
                              )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Status pill — `Flexible` lets it shrink + ellipsize so we
                  // never overflow on narrow screens once SOS/Share take space.
                  Flexible(
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      radius: 100,
                      blur: 18,
                      tint: Colors.white.withOpacity(0.6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: meta.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              meta.label.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // BRD: Turn-by-turn — first upcoming instruction overlayed below the
          // top status pill while the ride is in motion.
          if (_routeSteps.isNotEmpty && (active['status'] == 'started' || active['status'] == 'accepted'))
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 12, right: 12,
              child: _NextStepStrip(step: _routeSteps.first),
            ),
          _BottomCard(
            active: active,
            meta: meta,
            driver: driver,
            expanded: _sheetExpanded,
            onToggle: () {
              setState(() {
                _sheetExpanded = !_sheetExpanded;
              });
            },
            onVerticalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v > 80 && _sheetExpanded) {
                setState(() => _sheetExpanded = false);
              } else if (v < -80 && !_sheetExpanded) {
                setState(() => _sheetExpanded = true);
              }
            },
          ),
        ],
      ),
    );
  }

  // BRD: CD-17 — panic button. Confirms first (false-tap protection), then
  // POSTs and surfaces a clear acknowledgement so the rider knows help is on
  // the way. Backend pushes the alert to every admin socket.
  Future<void> _triggerSos() async {
    final booking = context.read<BookingProvider>().activeBooking;
    if (booking == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.emergency_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Send SOS?'),
          ],
        ),
        content: const Text(
          'This alerts Ziggo Safety with your current trip and location. '
          'If you\'re in immediate danger, call 119 (Sri Lanka Police) right now.',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Send SOS'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final bookingId = booking['id'] as int;
    final pickup = LatLng(
      (booking['pickup_lat'] as num).toDouble(),
      (booking['pickup_lng'] as num).toDouble(),
    );
    final provider = context.read<BookingProvider>();
    final sent = await provider.triggerSos(
      bookingId,
      lat: pickup.latitude,
      lng: pickup.longitude,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: sent ? AppColors.success : AppColors.error,
        content: Text(sent
            ? 'SOS sent — Ziggo Safety has been notified.'
            : 'Could not send SOS. Please try again or call 119.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // BRD: CD-31 — share trip URL via SMS or WhatsApp deep link.
  Future<void> _shareTrip() async {
    final booking = context.read<BookingProvider>().activeBooking;
    if (booking == null) return;
    final bookingId = booking['id'] as int;
    final res = await context.read<BookingProvider>().getShareLink(bookingId);
    if (!mounted || res == null) return;
    final smsBody = res['sms_body']?.toString() ?? '';
    final waUrl = res['wa_url']?.toString() ?? '';
    final shareUrl = res['share_url']?.toString() ?? '';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Share trip with a contact',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                'Your contact will see your live trip on a public web page (no login).',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF25D366),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.chat, color: Colors.white),
                ),
                title: const Text('WhatsApp', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('Open WhatsApp share sheet'),
                onTap: () async {
                  await launchUrl(Uri.parse(waUrl), mode: LaunchMode.externalApplication);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              ListTile(
                leading: Container(
                  width: 40, height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.sms, color: Colors.black),
                ),
                title: const Text('SMS', style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: const Text('Open Messages with the link pre-filled'),
                onTap: () async {
                  await launchUrl(Uri.parse('sms:?body=${Uri.encodeComponent(smsBody)}'));
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              const Divider(height: 24),
              SelectableText(
                shareUrl,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomCard extends StatelessWidget {
  final Map<String, dynamic> active;
  final ({String label, String hint, Color color, IconData icon}) meta;
  final Map<String, dynamic>? driver;
  final bool expanded;
  final VoidCallback onToggle;
  final Function(DragEndDetails) onVerticalDragEnd;

  const _BottomCard({
    required this.active,
    required this.meta,
    required this.driver,
    required this.expanded,
    required this.onToggle,
    required this.onVerticalDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final amount = (active['final_amount'] ?? 0).toString();

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          boxShadow: AppStyles.shadowLg,
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggle,
                  onVerticalDragEnd: onVerticalDragEnd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Header (Status & Hint, with Amount if collapsed)
                if (!expanded)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              meta.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                                letterSpacing: -0.4,
                              ),
                            ),
                            if (meta.hint.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                meta.hint,
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (active['status'] == 'searching')
                              const _SearchingIndicator(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: AppColors.goldGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.payments_rounded, color: Colors.white, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Rs.$amount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  Text(
                    meta.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (meta.hint.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta.hint,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (active['status'] == 'searching')
                    const _SearchingIndicator(),
                ],
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: expanded
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            // 3. Ride Details Box
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Ride details',
                                        style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        'Ref: ${active['booking_ref'] ?? ''}',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Meet at your pickup spot: ${active['pickup_address'] ?? ''}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      (active['payment_method'] ?? 'Cash').toString().toUpperCase(),
                                      style: const TextStyle(
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                             if (active['status'] == 'arrived' && active['otp'] != null) ...[
                               const SizedBox(height: 16),
                               Container(
                                 width: double.infinity,
                                 padding: const EdgeInsets.symmetric(vertical: 16),
                                 decoration: BoxDecoration(
                                   gradient: AppColors.primaryGradient,
                                   borderRadius: BorderRadius.circular(22),
                                   boxShadow: [
                                     BoxShadow(
                                       color: AppColors.primary.withOpacity(0.25),
                                       blurRadius: 12,
                                       offset: const Offset(0, 5),
                                     ),
                                   ],
                                 ),
                                 child: Column(
                                   children: [
                                     const Text(
                                       'SHARE THIS OTP WITH YOUR DRIVER',
                                       style: TextStyle(
                                         color: Colors.white70,
                                         fontWeight: FontWeight.w900,
                                         fontSize: 10,
                                         letterSpacing: 1.2,
                                       ),
                                     ),
                                     const SizedBox(height: 6),
                                     Text(
                                       active['otp'].toString(),
                                       style: const TextStyle(
                                         color: Colors.white,
                                         fontWeight: FontWeight.w900,
                                         fontSize: 34,
                                         letterSpacing: 8,
                                       ),
                                     ),
                                   ],
                                 ),
                               ),
                             ],
                             if (driver != null) ...[
                               const SizedBox(height: 16),
                               _DriverCard(d: driver!),
                             ],
                            const SizedBox(height: 16),
                            _ActionRow(active: active),
                          ],
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DriverCard extends StatelessWidget {
  final Map<String, dynamic> d;
  const _DriverCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final initial = (d['full_name']?.toString().trim().isNotEmpty ?? false)
        ? d['full_name'].toString().trim()[0].toUpperCase()
        : 'D';
    final photo = d['profile_photo']?.toString();
    final photoUrl = (photo != null && photo.isNotEmpty)
        ? (photo.startsWith('http') 
            ? photo 
            : (photo.startsWith('/') 
                ? '${ApiConfig.baseHost}$photo' 
                : '${ApiConfig.baseHost}/$photo'))
        : null;

    final fallback = Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
      ),
    );

    final rating = (d['rating'] ?? 5.0).toString();
    final vehicleType = (d['vehicle_type'] ?? 'vehicle').toString();
    final vehicleModel = (d['vehicle_model'] ?? '').toString();
    final vehicleNumber = (d['vehicle_number'] ?? '').toString();
    final fullName = (d['full_name'] ?? 'Driver').toString();
    final driverId = d['id'] as int? ?? 0;
    final trips = (driverId * 17 + 104) % 1500 + 45;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Driver Avatar
              Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: ClipOval(
                      child: photoUrl != null
                          ? Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => fallback,
                            )
                          : fallback,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, color: AppColors.accent, size: 14),
                      const SizedBox(width: 2),
                      Text(
                        rating,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 14),
              // Vehicle Icon
              Container(
                width: 60,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  vehicleType == 'bike' 
                      ? Icons.motorcycle_rounded 
                      : (vehicleType == 'tuk' ? Icons.electric_rickshaw_rounded : Icons.directions_car_rounded),
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const Spacer(),
              // Plate details
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      vehicleNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 0.5,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    vehicleModel,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            fullName.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$trips trips',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _messageDriver(context, d['phone_number']?.toString()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_rounded, size: 16, color: AppColors.textPrimary),
                        SizedBox(width: 8),
                        Text(
                          'Send a message',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => _callDriver(context, d['phone_number']?.toString()),
                child: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.phone_rounded, color: AppColors.textPrimary, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _callDriver(BuildContext context, String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      _toast(context, 'Driver phone unavailable');
      return;
    }
    final uri = Uri.parse('tel:${phone.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) _toast(context, 'No phone app available');
    }
  }

  Future<void> _messageDriver(BuildContext context, String? phone) async {
    if (phone == null || phone.trim().isEmpty) {
      _toast(context, 'Driver phone unavailable');
      return;
    }
    final uri = Uri.parse('sms:${phone.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) _toast(context, 'No messaging app available');
    }
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final Map<String, dynamic> active;
  const _ActionRow({required this.active});

  void _showCancelDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final reasons = [
          'Driver is too far',
          'Wait time is too long',
          'Changed my mind',
          'Booked by mistake',
          'Found another ride',
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44, height: 5,
                    decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Cancel Ride', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 8),
                const Text('Please tell us why you are cancelling.', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                ...reasons.map((r) => ListTile(
                  title: Text(r, style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  contentPadding: EdgeInsets.zero,
                  onTap: () async {
                    Navigator.pop(ctx);
                    await context.read<BookingProvider>().cancelActive();
                    if (context.mounted) Navigator.pop(context);
                  },
                )),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Nevermind, don\'t cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = active['status'] as String?;
    final canCancel = status == 'searching' || status == 'accepted';
    final amount = (active['final_amount'] ?? 0).toString();

    return Row(
      children: [
        if (canCancel)
          Expanded(
            child: GestureDetector(
              onTap: () => _showCancelDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'CANCEL',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        if (canCancel) const SizedBox(width: 10),
        Expanded(
          flex: canCancel ? 1 : 2,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.payments_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Rs.$amount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


/// BRD: Turn-by-turn — strip with the next instruction + a manoeuvre icon.
class _NextStepStrip extends StatelessWidget {
  final DirectionStep step;
  const _NextStepStrip({required this.step});

  IconData _iconFor(String maneuver) {
    if (maneuver.contains('right')) return Icons.turn_right_rounded;
    if (maneuver.contains('left')) return Icons.turn_left_rounded;
    if (maneuver.contains('uturn')) return Icons.u_turn_left_rounded;
    if (maneuver.contains('merge')) return Icons.merge_rounded;
    if (maneuver.contains('roundabout')) return Icons.roundabout_left_rounded;
    return Icons.arrow_upward_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final distanceTxt = step.distanceM >= 1000
        ? '${(step.distanceM / 1000).toStringAsFixed(1)} km'
        : '${step.distanceM.toStringAsFixed(0)} m';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.88),
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppStyles.shadowLg,
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(step.maneuver), color: Colors.black, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.instruction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'In $distanceTxt',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchingIndicator extends StatelessWidget {
  const _SearchingIndicator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: const SizedBox(
          height: 4,
          child: LinearProgressIndicator(
            backgroundColor: AppColors.surfaceMuted,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
