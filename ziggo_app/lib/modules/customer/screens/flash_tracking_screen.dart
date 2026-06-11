import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/ziggo_map.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/pulse_dot.dart';
import '../booking_provider.dart';
import 'rating_screen.dart';

/// Parcel-delivery tracker. Same status state-machine as a ride but labelled
/// for couriers — the customer sees "Courier collecting parcel" / "Parcel in
/// transit" / "Delivered" instead of generic ride wording.
class FlashTrackingScreen extends StatefulWidget {
  const FlashTrackingScreen({super.key});

  @override
  State<FlashTrackingScreen> createState() => _FlashTrackingScreenState();
}

class _FlashTrackingScreenState extends State<FlashTrackingScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();

  // While the booking is in SEARCHING we poll /driver/nearby every 6 s so the
  // customer sees wandering vehicle pins around the pickup (same UX as ride
  // tracking — visual reassurance that couriers exist).
  Timer? _nearbyTimer;
  List<Map<String, dynamic>> _nearbyDrivers = const [];
  bool _navigatedToRating = false;
  List<LatLng> _routePoints = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookingProvider>().loadActive();
    });
  }

  Future<void> _fetchRoute(LatLng pickup, LatLng drop) async {
    final dir = await MapsService.instance.directions(pickup, drop);
    if (mounted && dir != null && dir.points.isNotEmpty) {
      setState(() => _routePoints = dir.points);
    }
  }

  @override
  void dispose() {
    _nearbyTimer?.cancel();
    super.dispose();
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
      // Silent — match fare_estimate / ride_tracking behavior.
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
          label: 'Finding a courier',
          hint: 'Matching your parcel with the nearest courier',
          color: AppColors.warning,
          icon: Icons.search_rounded,
        );
      case 'accepted':
        return (
          label: 'Courier on the way',
          hint: 'Your courier is heading to pickup',
          color: AppColors.flash,
          icon: Icons.directions_bike_rounded,
        );
      case 'arrived':
        return (
          label: 'Collecting parcel',
          hint: 'Courier is at the pickup location',
          color: AppColors.success,
          icon: Icons.inventory_2_rounded,
        );
      case 'started':
        return (
          label: 'Parcel in transit',
          hint: 'On the way to the receiver',
          color: AppColors.primary,
          icon: Icons.local_shipping_rounded,
        );
      case 'completed':
        return (
          label: 'Delivered',
          hint: 'Parcel handed over successfully',
          color: AppColors.success,
          icon: Icons.check_circle_rounded,
        );
      case 'cancelled':
        return (
          label: 'Cancelled',
          hint: '',
          color: AppColors.error,
          icon: Icons.cancel_rounded,
        );
      default:
        return (
          label: 'Loading…',
          hint: '',
          color: AppColors.textTertiary,
          icon: Icons.hourglass_top_rounded,
        );
    }
  }

  static const _stages = [
    ('searching', 'Looking for courier', Icons.search_rounded),
    ('accepted', 'Courier assigned', Icons.directions_bike_rounded),
    ('arrived', 'Picking up parcel', Icons.inventory_2_rounded),
    ('started', 'In transit', Icons.local_shipping_rounded),
    ('completed', 'Delivered', Icons.check_circle_rounded),
  ];

  int _stageIndex(String? s) {
    final i = _stages.indexWhere((e) => e.$1 == s);
    return i < 0 ? 0 : i;
  }

  Future<void> _callReceiver(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
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
    final driverLatLng = (driverLat != null && driverLng != null)
        ? LatLng(driverLat.toDouble(), driverLng.toDouble())
        : null;

    final status = active['status'] as String?;
    final meta = _statusMeta(status);
    final currentStage = _stageIndex(status);
    final isCourier = active['is_courier'] == true;
    final isParcel = active['is_flash'] == true || isCourier;
    final parcelType = (active['parcel_type'] ?? 'parcel').toString();
    final receiverName = active['receiver_name']?.toString() ?? 'Receiver';
    final receiverPhone = active['receiver_phone']?.toString();
    final parcelWeight = active['parcel_weight_kg'];
    final serviceType = active['service_type'] as String?;

    // Show wandering courier pins only while we're still hunting one. Once a
    // courier accepts, only their assigned pin remains on the map.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (status == 'searching') {
        _startNearbyPolling(pickup, serviceType);
      } else {
        _stopNearbyPolling();
      }
    });

    // Once the courier marks the parcel delivered, the backend drops it from
    // /bookings/active and activeBooking becomes null — without this jump the
    // screen would be stuck on a spinner forever. Mirror ride_tracking_screen.
    if (status == 'completed' && !_navigatedToRating) {
      _navigatedToRating = true;
      _stopNearbyPolling();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => RatingScreen(bookingId: active['id'] as int),
          ),
        );
      });
    }

    if (_routePoints.isEmpty) {
      _fetchRoute(pickup, drop);
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
                // Wandering couriers (only while SEARCHING) — drawn first so
                // pickup/drop pins paint on top.
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
                  icon: Icons.inventory_2_rounded,
                  color: AppColors.success,
                  label: 'Sender | ${active['pickup_address'] ?? 'Pickup Location'}',
                ),
                pinMarker(
                  point: drop,
                  icon: Icons.location_on_rounded,
                  color: AppColors.error,
                  label: 'Receiver | ${active['drop_address'] ?? 'Delivery Location'}',
                ),
                if (driverLatLng != null)
                  pinMarker(
                    point: driverLatLng,
                    icon: Icons.directions_bike_rounded,
                    color: Colors.black,
                    assetPath: _vehicleAsset(driver?['vehicle_type'] as String?),
                    rotation: (driver?['current_heading'] as num?)?.toDouble() ?? 0.0,
                  ),
              ],
              polylines: [
                ZiggoPolyline(
                  points: activeRoutePoints,
                  strokeWidth: 4,
                  color: AppColors.primary,
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
                  const Spacer(),
                  GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    radius: 100,
                    blur: 18,
                    tint: Colors.white.withOpacity(0.6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PulseDot(color: meta.color, size: 8, pulseSize: 18),
                        const SizedBox(width: 8),
                        Text(
                          isCourier ? 'ZIGGO COURIER' : 'ZIGGO FLASH',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Bottom card
          Align(
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
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Status header
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: meta.color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(meta.icon, color: meta.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  meta.label,
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                                ),
                                if (meta.hint.isNotEmpty)
                                  Text(
                                    meta.hint,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Stage timeline (dotted line + 5 dots)
                      _StageTimeline(currentStage: currentStage, stages: _stages),
                      const SizedBox(height: 16),
                      // Parcel card
                      if (isParcel)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.primary.withOpacity(0.15)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'PARCEL DETAILS',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textTertiary,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.inventory_2_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          parcelType.toUpperCase(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                        Text(
                                          parcelWeight != null
                                              ? '${parcelWeight.toString()} kg'
                                              : '— kg',
                                          style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        receiverName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        receiverPhone ?? '',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 8),
                                  if (receiverPhone != null && receiverPhone.isNotEmpty)
                                    GestureDetector(
                                      onTap: () => _callReceiver(receiverPhone),
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(
                                          color: AppColors.success,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.phone_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if ((active['parcel_instructions'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.notes_rounded,
                                        size: 14,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          active['parcel_instructions'].toString(),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      // Booking ref pill + cancel/fare row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.receipt_long_rounded,
                                  size: 13,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  active['booking_ref']?.toString() ?? '',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Rs.${(active['final_amount'] ?? 0).toString()}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Cancel button if applicable
                      if (status == 'searching' || status == 'accepted')
                        GestureDetector(
                          onTap: () async {
                            await context.read<BookingProvider>().cancelActive();
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Text(
                              'CANCEL DELIVERY',
                              style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StageTimeline extends StatelessWidget {
  final int currentStage;
  final List<(String, String, IconData)> stages;
  const _StageTimeline({required this.currentStage, required this.stages});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(stages.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final done = (i ~/ 2) < currentStage;
          return Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: done ? AppColors.primary : AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }
        final idx = i ~/ 2;
        final done = idx <= currentStage;
        final current = idx == currentStage;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: current ? 30 : 24,
              height: current ? 30 : 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? AppColors.primary : AppColors.surfaceMuted,
                shape: BoxShape.circle,
                boxShadow: current
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                stages[idx].$3,
                size: current ? 16 : 13,
                color: done ? Colors.white : AppColors.textTertiary,
              ),
            ),
          ],
        );
      }),
    );
  }
}
