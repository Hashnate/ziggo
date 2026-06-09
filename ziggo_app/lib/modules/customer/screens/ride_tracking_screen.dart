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
import '../../../core/widgets/ambient_orbs.dart';
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

  // While the booking is in SEARCHING we poll /driver/nearby every 6 s so the
  // customer sees the same wandering-vehicle pins they had on fare estimate.
  Timer? _nearbyTimer;
  List<Map<String, dynamic>> _nearbyDrivers = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookingProvider>().loadActive();
    });
  }

  @override
  void dispose() {
    _nearbyTimer?.cancel();
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
    final serviceType = active['service_type'] as String?;

    _ensureRoute(pickup, drop);

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
                  ),
              ],
              polylines: [
                ZiggoPolyline(
                  points: _routePoints.isNotEmpty
                      ? _routePoints
                      : [pickup, drop],
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
          _BottomCard(active: active, meta: meta, driver: driver),
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
  const _BottomCard({required this.active, required this.meta, required this.driver});

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded,
                          size: 13, color: AppColors.textSecondary),
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
                if (driver != null) ...[
                  const SizedBox(height: 14),
                  _DriverCard(d: driver!),
                ],
                const SizedBox(height: 14),
                _ActionRow(active: active),
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
          color: Colors.black,
          fontWeight: FontWeight.w900,
          fontSize: 22,
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          // Base gradient — Positioned.fill so the navy actually covers the
          // whole card (without this, the unsized Container collapses and the
          // shimmer overlay hides the driver text against the parent's white).
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0B1437), Color(0xFF1E40AF)],
                ),
              ),
            ),
          ),
          // Drifting orbs (subtle, low-count)
          const Positioned.fill(
            child: AmbientOrbs(
              colors: [
                AppColors.primaryLight,
                AppColors.accent,
              ],
              count: 2,
            ),
          ),
          // (The old ShimmerHighlight here painted an opaque white band on
          // top of the card content via srcATop on a white Container — it
          // hid the driver's name. Removed; orbs alone give enough motion.)
          // Content
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: AppColors.goldGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: photoUrl != null
                        ? Image.network(
                            photoUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => fallback,
                          )
                        : fallback,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (d['full_name']?.toString().trim().isNotEmpty ?? false)
                            ? d['full_name'].toString()
                            : 'Driver',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: AppColors.accent, size: 14),
                          const SizedBox(width: 2),
                          Text(
                            (d['rating'] ?? 5.0).toString(),
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.18),
                              ),
                            ),
                            child: Text(
                              '${d['vehicle_type'] ?? ''}'.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 9,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Builder(builder: (_) {
                        final model = (d['vehicle_model'] ?? '').toString().trim();
                        final plate = (d['vehicle_number'] ?? '').toString().trim();
                        final parts = [
                          if (model.isNotEmpty) model,
                          if (plate.isNotEmpty) plate,
                        ];
                        return Text(
                          parts.isEmpty ? 'Vehicle details unavailable' : parts.join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _circleAction(
                      Icons.phone_rounded,
                      AppColors.success,
                      () => _callDriver(context, d['phone_number']?.toString()),
                    ),
                    const SizedBox(width: 8),
                    _circleAction(
                      Icons.chat_rounded,
                      AppColors.flash,
                      () => _messageDriver(context, d['phone_number']?.toString()),
                    ),
                  ],
                ),
              ],
            ),
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
    final uri = Uri(scheme: 'tel', path: phone.trim());
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
    final uri = Uri(scheme: 'sms', path: phone.trim());
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

  Widget _circleAction(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
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
                const Icon(Icons.payments_rounded, color: Colors.black, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Rs.$amount',
                  style: const TextStyle(
                    color: Colors.black,
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
