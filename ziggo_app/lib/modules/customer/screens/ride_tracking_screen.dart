import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/ws_client.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/notifications/fcm_service.dart';
import '../../common/screens/ride_chat_screen.dart';
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
  bool _driverCancelled = false;
  bool _userCancelled = false;
  List<LatLng> _routePoints = const [];
  List<DirectionStep> _routeSteps = const [];
  String? _routeKey;
  bool _sheetExpanded = true;
  String? _lastStatus;
  bool _otpDialogShown = false;
  LatLng? _lastCameraDriverLatLng;
  String? _lastCameraStatus;

  // While the booking is in SEARCHING we poll /driver/nearby every 6 s so the
  // customer sees the same wandering-vehicle pins they had on fare estimate.
  Timer? _nearbyTimer;
  List<Map<String, dynamic>> _nearbyDrivers = const [];

  StreamSubscription<Position>? _positionSubscription;
  LatLng? _customerLatLng;
  double? _customerHeading;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookingProvider>().loadActive();
    });
    _startPositionUpdates();
    _wsSub = WsClient.instance.events.listen((msg) {
      if (msg['event'] == 'chat_message') {
        final data = msg['data'] as Map<String, dynamic>?;
        if (data != null && data['message'] != null && data['sender_type'] != 'customer') {
          if (!RideChatScreen.isOpen) {
            FcmService.instance.showChatNotification('Message from Driver', data['message']);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Driver: ${data['message']}'),
                  backgroundColor: AppColors.primary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
        }
      }
    });
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
    _wsSub?.cancel();
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
      if (_driverCancelled) {
        return const Scaffold(body: SizedBox.shrink());
      }
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
      if (status == 'arrived') {
        _sheetExpanded = true;
      }
      if (status == 'started') {
        _sheetExpanded = false;
      }
      if (status != 'arrived') {
        _otpDialogShown = false;
      }
      if (status == 'arrived' && active['otp'] != null && !_otpDialogShown) {
        _otpDialogShown = true;
        // Don't show popup dialog anymore, show inline in the sheet instead
      }
      if (status == 'cancelled') {
        if (!_userCancelled) {
          _driverCancelled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showDriverCancelledDialog();
          });
        }
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
                  if (active == null || active['service_type'] == null || d['vehicle_type'] == active['service_type'])
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
            onCancel: () {
              setState(() {
                _userCancelled = true;
              });
            },
          ),
        ],
      ),
    );
  }

  void _showDriverCancelledDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, color: AppColors.error, size: 32),
            SizedBox(width: 10),
            Text(
              'Ride Cancelled',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.error,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Unfortunately, the driver has cancelled your ride. Please try booking another ride.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                if (mounted) {
                  context.read<BookingProvider>().clearActiveBookingLocally();
                  Navigator.popUntil(context, (r) => r.isFirst);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'GO HOME',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showArrivedOtpDialog(String otp) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 28),
            SizedBox(width: 8),
            Text('Driver Arrived!', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Your driver is at the pickup point. Share this OTP with the driver to start your trip:',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                otp,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 36,
                  letterSpacing: 6,
                ),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('GOT IT', style: TextStyle(fontWeight: FontWeight.bold)),
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
  final VoidCallback? onCancel;

  const _BottomCard({
    required this.active,
    required this.meta,
    required this.driver,
    required this.expanded,
    required this.onToggle,
    required this.onVerticalDragEnd,
    this.onCancel,
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
                            if ((active['status'] == 'accepted' || active['status'] == 'arrived') && active['otp'] != null) ...[
                              const SizedBox(height: 14),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF2563EB), width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF2563EB).withOpacity(0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      'Share PIN',
                                      style: TextStyle(
                                        color: Color(0xFF2563EB),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Row(
                                      children: active['otp'].toString().split('').map((digit) => Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        width: 28,
                                        height: 32,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF2563EB),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          digit,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      )).toList(),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
                                  IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          width: 50,
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('PICKUP', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: AppColors.primary, letterSpacing: 0.5)),
                                              if ((active['stops'] as List?)?.isNotEmpty == true)
                                                for (int i = 0; i < (active['stops'] as List).length; i++)
                                                  Text('STOP ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: AppColors.primary, letterSpacing: 0.5)),
                                              const Text('DROP', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10, color: AppColors.primary, letterSpacing: 0.5)),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 16,
                                          child: Stack(
                                            alignment: Alignment.topCenter,
                                            children: [
                                              // The continuous line
                                              Positioned(
                                                top: 6, bottom: 6,
                                                child: Container(width: 2, color: AppColors.primary),
                                              ),
                                              // The dots
                                              Column(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Container(
                                                    width: 12, height: 12,
                                                    margin: const EdgeInsets.only(top: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: AppColors.primary, width: 2.5),
                                                    ),
                                                  ),
                                                  if ((active['stops'] as List?)?.isNotEmpty == true)
                                                    for (int i = 0; i < (active['stops'] as List).length; i++)
                                                      Container(
                                                        width: 12, height: 12,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          shape: BoxShape.circle,
                                                          border: Border.all(color: AppColors.primary, width: 2.5),
                                                        ),
                                                      ),
                                                  Container(
                                                    width: 12, height: 12,
                                                    margin: const EdgeInsets.only(bottom: 2),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: AppColors.primary, width: 2.5),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                active['pickup_address']?.toString() ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.black87),
                                              ),
                                              if ((active['stops'] as List?)?.isNotEmpty == true)
                                                for (final stop in (active['stops'] as List)) ...[
                                                  const SizedBox(height: 12),
                                                  Text(
                                                    stop['address']?.toString() ?? '',
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textSecondary),
                                                  ),
                                                ],
                                              const SizedBox(height: 12),
                                              Text(
                                                active['drop_address']?.toString() ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
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
                                      if (active['distance_km'] != null || active['duration_min'] != null)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (active['distance_km'] != null) ...[
                                              const Icon(Icons.straighten_rounded, size: 14, color: AppColors.textSecondary),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${double.tryParse(active['distance_km'].toString())?.toStringAsFixed(1) ?? active['distance_km']} km',
                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                            if (active['distance_km'] != null && active['duration_min'] != null)
                                              const Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 6),
                                                child: Text('•', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                              ),
                                            if (active['duration_min'] != null) ...[
                                              const Icon(Icons.access_time_rounded, size: 14, color: AppColors.textSecondary),
                                              const SizedBox(width: 4),
                                              Text(
                                                '${double.tryParse(active['duration_min'].toString())?.round() ?? active['duration_min']} mins',
                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                             if (driver != null) ...[
                               const SizedBox(height: 16),
                               _DriverCard(d: driver!),
                             ],
                             if (active['status'] == 'started' || active['status'] == 'accepted') ...[
                               const SizedBox(height: 16),
                               GestureDetector(
                                 onTap: () async {
                                   final action = await showModalBottomSheet<String>(
                                     context: context,
                                     shape: const RoundedRectangleBorder(
                                       borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                     ),
                                     builder: (ctx) {
                                       return SafeArea(
                                         child: Padding(
                                           padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                                               const SizedBox(height: 24),
                                               const Text('Update Trip', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
                                               const SizedBox(height: 16),
                                               ListTile(
                                                 leading: const CircleAvatar(
                                                   backgroundColor: AppColors.surfaceMuted,
                                                   child: Icon(Icons.add_location_alt_rounded, color: AppColors.primary),
                                                 ),
                                                 title: const Text('Add a Stop', style: TextStyle(fontWeight: FontWeight.w700)),
                                                 subtitle: const Text('Add an intermediate stop before your final destination', style: TextStyle(fontSize: 12)),
                                                 onTap: () => Navigator.pop(ctx, 'add_stop'),
                                               ),
                                               ListTile(
                                                 leading: const CircleAvatar(
                                                   backgroundColor: AppColors.surfaceMuted,
                                                   child: Icon(Icons.edit_location_alt_rounded, color: AppColors.primary),
                                                 ),
                                                 title: const Text('Change Destination', style: TextStyle(fontWeight: FontWeight.w700)),
                                                 subtitle: const Text('Update your final drop-off location', style: TextStyle(fontSize: 12)),
                                                 onTap: () => Navigator.pop(ctx, 'change_destination'),
                                               ),
                                             ],
                                           ),
                                         ),
                                       );
                                     },
                                   );

                                   if (action == null || !context.mounted) return;

                                   final p = await showPlaceSearch(context, title: action == 'add_stop' ? 'Add a Stop' : 'Change Destination');
                                   if (p != null && context.mounted) {
                                     final provider = context.read<BookingProvider>();
                                     
                                     bool ok = false;
                                     if (action == 'add_stop') {
                                       final currentStops = (active['stops'] as List? ?? const [])
                                           .map((e) => Map<String, dynamic>.from(e))
                                           .toList();
                                       currentStops.add({
                                         'lat': p.location.latitude,
                                         'lng': p.location.longitude,
                                         'address': p.name,
                                       });
                                       ok = await provider.updateDestination(
                                         active['id'] as int,
                                         LatLng(double.parse(active['drop_lat'].toString()), double.parse(active['drop_lng'].toString())),
                                         active['drop_address'].toString(),
                                         stops: currentStops,
                                       );
                                     } else {
                                       ok = await provider.updateDestination(
                                         active['id'] as int,
                                         p.location,
                                         p.name,
                                         stops: (active['stops'] as List? ?? const [])
                                           .map((e) => Map<String, dynamic>.from(e))
                                           .toList(),
                                       );
                                     }
                                     
                                     if (context.mounted) {
                                       ScaffoldMessenger.of(context).showSnackBar(
                                         SnackBar(
                                           content: Text(ok ? 'Trip updated successfully' : 'Failed to update trip'),
                                           backgroundColor: ok ? AppColors.success : AppColors.error,
                                           behavior: SnackBarBehavior.floating,
                                         ),
                                       );
                                     }
                                   }
                                 },
                                 child: Container(
                                   padding: const EdgeInsets.symmetric(vertical: 14),
                                   alignment: Alignment.center,
                                   decoration: BoxDecoration(
                                     color: AppColors.surfaceMuted,
                                     border: Border.all(color: AppColors.divider),
                                     borderRadius: BorderRadius.circular(14),
                                   ),
                                   child: const Row(
                                     mainAxisAlignment: MainAxisAlignment.center,
                                     children: [
                                       Icon(Icons.edit_location_alt_rounded, color: AppColors.textPrimary, size: 20),
                                       SizedBox(width: 8),
                                       Text(
                                         'Add Stop / Change Destination',
                                         style: TextStyle(
                                           color: AppColors.textPrimary,
                                           fontWeight: FontWeight.w800,
                                           fontSize: 14,
                                         ),
                                       ),
                                     ],
                                   ),
                                 ),
                               ),
                             ],
                             const SizedBox(height: 16),
                             _ActionRow(
                               active: active,
                               onCancel: onCancel,
                             ),
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

    final vPhoto = d['vehicle_photo_url']?.toString();
    final vehiclePhotoUrl = (vPhoto != null && vPhoto.isNotEmpty)
        ? (vPhoto.startsWith('http') 
            ? vPhoto 
            : (vPhoto.startsWith('/') 
                ? '${ApiConfig.baseHost}$vPhoto' 
                : '${ApiConfig.baseHost}/$vPhoto'))
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
    final profile = d['profile'] as Map<String, dynamic>?;
    final rawColor = (d['vehicle_color'] ?? profile?['vehicle_color'] ?? '').toString().trim();
    final vehicleColor = rawColor.isNotEmpty 
        ? '${rawColor[0].toUpperCase()}${rawColor.substring(1)}'
        : '';

    int parseTrips(dynamic val) {
      if (val == null) return -1;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val.toString()) ?? -1;
      return -1;
    }

    int trips = -1;
    final keys = ['completed_trips', 'total_trips', 'total_rides', 'trips', 'rides', 'rides_completed', 'trips_completed', 'rides_count', 'completed_rides'];
    for (final k in keys) {
      final v = parseTrips(d[k]);
      if (v >= 0) { trips = v; break; }
    }
    if (trips < 0 && profile != null) {
      for (final k in keys..add('today_rides')) {
        final v = parseTrips(profile[k]);
        if (v >= 0) { trips = v; break; }
      }
    }

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
              // Combined Driver Avatar + Rating Badge + Vehicle Photo (overlapping)
              SizedBox(
                width: 116,
                height: 64,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 1. Vehicle Photo (Layered behind)
                    Positioned(
                      left: 42,
                      top: 0,
                      child: SizedBox(
                        width: 76,
                        height: 64,
                        child: vehiclePhotoUrl != null
                            ? Image.network(
                                vehiclePhotoUrl,
                                fit: BoxFit.contain,
                                width: 76,
                                height: 64,
                                errorBuilder: (context, error, stackTrace) => Image.asset(
                                  'assets/icons/${vehicleType == 'van' ? 'car' : (['bike', 'car', 'tuk', 'truck'].contains(vehicleType) ? vehicleType : 'car')}.png',
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Image.asset(
                                'assets/icons/${vehicleType == 'van' ? 'car' : (['bike', 'car', 'tuk', 'truck'].contains(vehicleType) ? vehicleType : 'car')}.png',
                                fit: BoxFit.contain,
                              ),
                      ),
                    ),
                    // 2. Driver Avatar + Rating Badge (Layered on top)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: photoUrl != null
                                ? CircleAvatar(
                                    radius: 27,
                                    backgroundColor: AppColors.primary.withOpacity(0.1),
                                    backgroundImage: NetworkImage(photoUrl),
                                    onBackgroundImageError: (exception, stackTrace) {
                                      debugPrint('Error loading driver photo: $exception');
                                    },
                                  )
                                : fallback,
                          ),
                          // Rating Badge
                          Positioned(
                            bottom: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.grey.shade200, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, color: AppColors.accent, size: 12),
                                  const SizedBox(width: 1),
                                  Text(
                                    rating,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                    vehicleColor.isNotEmpty ? '$vehicleColor $vehicleModel' : vehicleModel,
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
          if (trips >= 0) ...[
            const SizedBox(height: 2),
            Text(
              '$trips trips',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ] else ...[
            const SizedBox(height: 2),
            Text(
              'Backend not reloaded! Missing completed_trips key. Keys present: ${d.keys.join(", ")}',
              maxLines: 10,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ],
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
    final booking = context.read<BookingProvider>().activeBooking;
    if (booking == null) return;
    
    final driver = booking['driver'];
    final driverName = driver != null ? (driver['name'] ?? 'Driver') : 'Driver';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RideChatScreen(
          bookingId: booking['id'],
          otherParticipantName: driverName,
          isDriver: false,
        ),
      ),
    );
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
  final VoidCallback? onCancel;
  const _ActionRow({required this.active, this.onCancel});

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
                    final provider = context.read<BookingProvider>();
                    final navigator = Navigator.of(context);
                    Navigator.pop(ctx);
                    onCancel?.call();
                    
                    final bookingId = provider.activeBooking?['id'] as int?;
                    provider.clearActiveBookingLocally();
                    navigator.popUntil((r) => r.isFirst);
                    
                    if (bookingId != null) {
                      await provider.cancelActiveSilently(bookingId: bookingId, reason: r);
                    }
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconFor(step.maneuver), color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.instruction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'In $distanceTxt',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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
