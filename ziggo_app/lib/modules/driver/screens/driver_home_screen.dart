import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/ziggo_map.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/pulse_dot.dart';
import '../../auth/auth_provider.dart';
import '../../customer/screens/support_screen.dart';
import '../driver_provider.dart';
import 'driver_history_screen.dart';
import 'driver_documents_screen.dart';
import 'driver_registration_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ZiggoMapController _mapController = ZiggoMapController();
  bool _bootstrapped = false;
  // BRD: speed display + mute toggle
  double _speedKmh = 0;          // updated by the geolocator stream
  double _heading = 0.0;         // updated by the geolocator stream to orient location arrow
  bool _muted = false;           // local-only — wired into TTS when we add it
  StreamSubscription<Position>? _speedSub;
  bool _isShowingRideRequest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    await _ensureLocationReady();
    if (!mounted) return;
    final auth = context.read<AuthProvider>();
    final driver = context.read<DriverProvider>();
    if (auth.token != null) {
      await driver.bootstrap(auth.token!);
      _centerOnDriver();
    }
    // BRD: live speed read-out — subscribe once, convert m/s → km/h.
    _speedSub ??= Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high, distanceFilter: 5,
      ),
    ).listen((p) {
      final kmh = (p.speed.isNaN || p.speed < 0) ? 0.0 : p.speed * 3.6;
      if (!mounted) return;
      setState(() {
        if ((kmh - _speedKmh).abs() >= 1) {
          _speedKmh = kmh;
        }
        if (p.heading >= 0 && p.heading <= 360) {
          _heading = p.heading;
        }
      });
    });
  }

  @override
  void dispose() {
    _speedSub?.cancel();
    super.dispose();
  }

  /// BRD: Incident reporting — driver taps a chip from a bottom sheet,
  /// we POST current location + selected kind to the backend.
  Future<void> _reportIncident() async {
    final kinds = const [
      ('accident', 'Accident', Icons.car_crash_rounded, Color(0xFFEF4444)),
      ('traffic', 'Heavy traffic', Icons.traffic_rounded, Color(0xFFF59E0B)),
      ('closure', 'Road closed', Icons.do_not_disturb_on_rounded, Color(0xFFEF4444)),
      ('police', 'Police checkpoint', Icons.shield_rounded, Color(0xFF3B82F6)),
      ('hazard', 'Hazard / debris', Icons.warning_amber_rounded, Color(0xFFF59E0B)),
      ('other', 'Other', Icons.report_rounded, Color(0xFF6B7280)),
    ];
    final chosen = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Report incident',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 4),
              const Text(
                'Other drivers near you will see your warning for the next hour.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  for (final (kind, label, icon, color) in kinds)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, kind),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: color.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, color: color, size: 18),
                            const SizedBox(width: 8),
                            Text(label,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                )),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      await ApiClient.instance.dio.post('/incidents', data: {
        'kind': chosen,
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text('Thanks — drivers near you have been warned.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.error,
          content: Text('Could not send incident. Check your connection.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Asks the driver to enable location services and grant permission. Drivers
  /// can't accept rides without an active location, so this prompt fires the
  /// moment they land on the home screen.
  Future<void> _ensureLocationReady() async {
    if (!mounted) return;

    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!mounted) return;
      final open = await _showLocationDialog(
        title: 'Turn on location',
        message:
            'Ziggo needs your location to send you nearby ride requests. Please turn on Location services.',
        actionLabel: 'Open settings',
      );
      if (open == true) {
        await Geolocator.openLocationSettings();
      }
      return;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      if (!mounted) return;
      final open = await _showLocationDialog(
        title: 'Location permission needed',
        message:
            'You have permanently denied location access. Open app settings to allow Ziggo to use your location.',
        actionLabel: 'Open app settings',
      );
      if (open == true) {
        await Geolocator.openAppSettings();
      }
    }
  }

  Future<bool?> _showLocationDialog({
    required String title,
    required String message,
    required String actionLabel,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.location_on, color: AppColors.primary, size: 36),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  void _centerOnDriver() {
    if (!mounted) return;
    final loc = context.read<DriverProvider>().currentLocation;
    if (loc != null) {
      _mapController.moveTo(loc, zoom: 16);
    }
  }

  Future<void> _handleToggleOnline(bool goingOnline) async {
    final driver = context.read<DriverProvider>();
    if (goingOnline) {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        final open = await _showLocationDialog(
          title: 'Turn on location to go online',
          message:
              'You need to enable Location services before you can receive ride requests.',
          actionLabel: 'Open settings',
        );
        if (open == true) {
          await Geolocator.openLocationSettings();
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (!mounted) return;
        await _showLocationDialog(
          title: 'Location permission needed',
          message:
              'Grant location permission so customers can find you on the map.',
          actionLabel: 'OK',
        );
        return;
      }
    }
    await driver.toggleOnline(goingOnline);
    if (!mounted) return;
    if (goingOnline) _centerOnDriver();
  }

  Future<void> _openNavigation(double lat, double lng) async {
    final uri = Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=17/$lat/$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = context.watch<DriverProvider>();

    if (driver.profile != null && !driver.profileComplete) {
      return const DriverRegistrationScreen();
    }
    if (driver.profile != null && driver.profileComplete && !driver.isApproved) {
      return _PendingApprovalScreen(
        profile: driver.profile!,
        onRefresh: () => driver.loadProfile(),
        onLogout: () => context.read<AuthProvider>().logout(),
      );
    }

    final ride = driver.activeRide;
    final food = driver.activeFoodOrder;
    final market = driver.activeMarketOrder;
    final pending = driver.pendingRequest;
    final loc = driver.currentLocation ?? kColomboCenter;

    if (pending != null && ride == null && food == null && market == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showRideRequest(pending));
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _Drawer(
        onHistory: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DriverHistoryScreen()),
          );
        },
        onDocuments: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DriverDocumentsScreen()),
          );
        },
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: driver.isOnline ? 1.0 : 0.55,
              child: ZiggoMap(
                controller: _mapController,
                center: loc,
                zoom: 14,
                showMyLocation: true,
                markers: [
                  pinMarker(
                    point: loc,
                    icon: Icons.navigation_rounded,
                    color: Colors.black,
                    assetPath: 'assets/icons/heading_indicator.png',
                    rotation: _heading,
                    size: 32,
                  ),
                  if (ride != null) ...[
                    pinMarker(
                      point: LatLng(
                        (ride['pickup_lat'] as num).toDouble(),
                        (ride['pickup_lng'] as num).toDouble(),
                      ),
                      icon: Icons.my_location_rounded,
                      color: AppColors.flash,
                    ),
                    pinMarker(
                      point: LatLng(
                        (ride['drop_lat'] as num).toDouble(),
                        (ride['drop_lng'] as num).toDouble(),
                      ),
                      icon: Icons.location_on_rounded,
                      color: AppColors.error,
                    ),
                  ],
                  if (ride == null && food != null) ...[
                    if (food['pickup_lat'] != null && food['pickup_lng'] != null)
                      pinMarker(
                        point: LatLng(
                          (food['pickup_lat'] as num).toDouble(),
                          (food['pickup_lng'] as num).toDouble(),
                        ),
                        icon: Icons.restaurant_rounded,
                        color: AppColors.flash,
                      ),
                    if (food['delivery_lat'] != null &&
                        food['delivery_lng'] != null)
                      pinMarker(
                        point: LatLng(
                          (food['delivery_lat'] as num).toDouble(),
                          (food['delivery_lng'] as num).toDouble(),
                        ),
                        icon: Icons.location_on_rounded,
                        color: AppColors.error,
                      ),
                  ],
                ],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: AppStyles.shadowSm,
                      ),
                      child: const Icon(Icons.menu_rounded, color: AppColors.textPrimary),
                    ),
                  ),
                  const Spacer(),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: driver.isOnline ? AppColors.success : Colors.black,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: AppStyles.shadowSm,
                    ),
                    child: Row(
                      children: [
                        if (driver.isOnline)
                          const PulseDot(color: Colors.white, size: 8, pulseSize: 18)
                        else
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white24,
                              shape: BoxShape.circle,
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          driver.isOnline ? 'ONLINE' : 'OFFLINE',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
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
          Align(
            alignment: Alignment.bottomCenter,
            child: _buildBottomCard(driver, ride, food, market),
          ),
          // BRD: speed display + mute toggle + incident-report quick action.
          // Only shown when the driver is online — same gating as the map.
          if (driver.isOnline)
            Positioned(
              right: 12,
              top: MediaQuery.of(context).padding.top + 12,
              child: _DriverHUD(
                speedKmh: _speedKmh,
                muted: _muted,
                onToggleMute: () => setState(() => _muted = !_muted),
                onReportIncident: _reportIncident,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomCard(
    DriverProvider driver,
    Map<String, dynamic>? ride,
    Map<String, dynamic>? food,
    Map<String, dynamic>? market,
  ) {
    return Container(
      width: double.infinity,
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
              if (ride != null)
                _activeRideView(driver, ride)
              else if (food != null)
                _activeFoodOrderView(driver, food, isMarket: false)
              else if (market != null)
                _activeFoodOrderView(driver, market, isMarket: true)
              else
                _idleView(driver),
            ],
          ),
        ),
      ),
    );
  }

  Widget _idleView(DriverProvider driver) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          driver.isOnline ? "You're online" : 'Ready to earn?',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.4),
        ),
        const SizedBox(height: 4),
        Text(
          driver.isOnline
              ? 'New ride requests will appear automatically'
              : 'Go online to start receiving ride requests',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 18),
        // Stats card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: _statBlock(
                  'Today',
                  'Rs.${(driver.profile?['today_earnings'] ?? 0).toString()}',
                  Colors.white,
                  Icons.payments_rounded,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _statBlock(
                  'Rides',
                  (driver.profile?['today_rides'] ?? 0).toString(),
                  Colors.white,
                  Icons.directions_car_rounded,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _statBlock(
                  'Rating',
                  (driver.profile?['rating'] ?? 0).toString(),
                  AppColors.accent,
                  Icons.star_rounded,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: driver.isOnline ? 'GO OFFLINE' : 'GO ONLINE',
          icon: driver.isOnline ? Icons.pause_rounded : Icons.bolt_rounded,
          gold: !driver.isOnline,
          onPressed: () => _handleToggleOnline(!driver.isOnline),
        ),
      ],
    );
  }

  Widget _activeRideView(DriverProvider driver, Map<String, dynamic> ride) {
    final status = ride['status'] as String?;
    final customerLat = (ride['pickup_lat'] as num).toDouble();
    final customerLng = (ride['pickup_lng'] as num).toDouble();
    final dropLat = (ride['drop_lat'] as num).toDouble();
    final dropLng = (ride['drop_lng'] as num).toDouble();

    String nextAction = 'COMPLETE';
    String nextStatus = 'completed';
    Color actionColor = AppColors.success;
    IconData actionIcon = Icons.check_rounded;
    switch (status) {
      case 'accepted':
        nextAction = "I'VE ARRIVED";
        nextStatus = 'arrived';
        actionColor = AppColors.flash;
        actionIcon = Icons.location_on_rounded;
        break;
      case 'arrived':
        nextAction = 'START TRIP';
        nextStatus = 'started';
        actionColor = AppColors.primary;
        actionIcon = Icons.play_arrow_rounded;
        break;
      case 'started':
        nextAction = 'COMPLETE TRIP';
        nextStatus = 'completed';
        actionColor = AppColors.success;
        actionIcon = Icons.check_rounded;
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.18),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ride['is_flash'] == true) ...[
                    const Icon(Icons.inventory_2_rounded,
                        color: AppColors.textPrimary, size: 12),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    ride['is_flash'] == true
                        ? 'PARCEL • ${(status ?? '').toUpperCase()}'
                        : (status ?? '').toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              'Rs.${ride['final_amount'] ?? 0}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
          ],
        ),
        if (ride['is_flash'] == true) ...[
          const SizedBox(height: 10),
          _parcelInfoBanner(ride),
        ],
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.my_location_rounded,
                      color: AppColors.flash, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ride['pickup_address']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ],
              ),
              // BRD: CD-19 — intermediate stops between pickup and drop
              for (final stop in (ride['stops'] as List? ?? const [])) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${stop['order_index'] ?? '·'}',
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        (stop['address'] ?? '').toString().isEmpty
                            ? 'Stop ${stop['order_index'] ?? ''}'
                            : stop['address'].toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.warning,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: AppColors.error, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      ride['drop_address']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => _openNavigation(
                  status == 'started' ? dropLat : customerLat,
                  status == 'started' ? dropLng : customerLng,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.navigation_rounded, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'NAVIGATE',
                        style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () {
                  if (nextStatus == 'completed') {
                    _handleCompleteTrip(driver, ride);
                  } else {
                    driver.updateRideStatus(nextStatus);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: actionColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: actionColor.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(actionIcon, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        nextAction,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleCompleteTrip(DriverProvider driver, Map<String, dynamic> ride) async {
    final paymentMethod = (ride['payment_method'] ?? 'cash').toString().toLowerCase();
    final amount = (ride['final_amount'] as num?)?.toDouble() ?? 0.0;

    if (paymentMethod == 'cash') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Collect Cash', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.payments_rounded, color: AppColors.success, size: 48),
              const SizedBox(height: 16),
              const Text('Please collect', style: TextStyle(color: AppColors.textSecondary)),
              Text('Rs.${amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
              const Text('from the customer.', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Confirm Payment'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    } else if (paymentMethod == 'wallet' || paymentMethod == 'card' || paymentMethod.startsWith('card')) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Digital Payment', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 48),
              const SizedBox(height: 16),
              const Text('Payment of', style: TextStyle(color: AppColors.textSecondary)),
              Text('Rs.${amount.toStringAsFixed(0)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.primary)),
              const Text('was successfully deducted from customer.', style: TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Complete Trip'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    
    driver.updateRideStatus('completed');
  }

  Widget _parcelInfoBanner(Map<String, dynamic> ride) {
    final type = (ride['parcel_type'] ?? 'parcel').toString();
    final weight = ride['parcel_weight_kg'];
    final receiverName = (ride['receiver_name'] ?? '').toString();
    final receiverPhone = (ride['receiver_phone'] ?? '').toString();
    final instructions = (ride['parcel_instructions'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.30)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.inventory_2_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${type.toUpperCase()}${weight != null ? ' • $weight kg' : ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
                if (receiverName.isNotEmpty || receiverPhone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'To: $receiverName'
                      '${receiverPhone.isNotEmpty ? ' • $receiverPhone' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                if (instructions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '"$instructions"',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (receiverPhone.isNotEmpty)
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('tel:$receiverPhone');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.call_rounded,
                    color: Colors.white, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _activeFoodOrderView(
    DriverProvider driver,
    Map<String, dynamic> order, {
    required bool isMarket,
  }) {
    final status = (order['status'] ?? '').toString();
    final pickupLat = (order['pickup_lat'] as num?)?.toDouble();
    final pickupLng = (order['pickup_lng'] as num?)?.toDouble();
    final dropLat = (order['delivery_lat'] as num?)?.toDouble();
    final dropLng = (order['delivery_lng'] as num?)?.toDouble();
    final originName = (order[isMarket ? 'vendor_name' : 'restaurant_name'] ??
            (isMarket ? 'Vendor' : 'Restaurant'))
        .toString();
    final originAddress =
        (order[isMarket ? 'vendor_address' : 'restaurant_address'] ?? '')
            .toString();
    final deliveryAddress = (order['delivery_address'] ?? '').toString();
    final customerName = (order['customer_name'] ?? 'Customer').toString();
    final customerPhone = (order['customer_phone'] ?? '').toString();
    final amount = (order['final_amount'] as num?)?.toDouble() ?? 0;
    final serviceLabel = isMarket ? 'MARKET' : 'FOOD';
    final originIcon =
        isMarket ? Icons.storefront_rounded : Icons.restaurant_rounded;

    // Until the rider picks the food up, "Navigate" goes to the restaurant.
    final headingToCustomer = status == 'out_for_delivery';
    final navLat = headingToCustomer ? dropLat : pickupLat;
    final navLng = headingToCustomer ? dropLng : pickupLng;

    String nextAction;
    String? nextStatus;
    Color actionColor;
    IconData actionIcon;
    switch (status) {
      case 'confirmed':
      case 'preparing':
      case 'ready_for_pickup':
        nextAction = 'PICKED UP — OUT FOR DELIVERY';
        nextStatus = 'out_for_delivery';
        actionColor = AppColors.primary;
        actionIcon = Icons.delivery_dining_rounded;
        break;
      case 'out_for_delivery':
        nextAction = 'MARK DELIVERED';
        nextStatus = 'delivered';
        actionColor = AppColors.success;
        actionIcon = Icons.check_rounded;
        break;
      default:
        nextAction = 'COMPLETE';
        nextStatus = null;
        actionColor = AppColors.success;
        actionIcon = Icons.check_rounded;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.18),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(originIcon, color: AppColors.primary, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    '$serviceLabel • ${status.replaceAll('_', ' ').toUpperCase()}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              'Rs.${amount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(originIcon, color: AppColors.flash, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      originName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ],
              ),
              if (originAddress.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 2),
                  child: Text(
                    originAddress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: AppColors.error, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      deliveryAddress,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 2),
                child: Text(
                  customerName +
                      (customerPhone.isNotEmpty ? ' • $customerPhone' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            if (navLat != null && navLng != null)
              Expanded(
                child: GestureDetector(
                  onTap: () => _openNavigation(navLat, navLng),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.navigation_rounded, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'NAVIGATE',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (navLat != null && navLng != null) const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: nextStatus == null
                    ? null
                    : () => isMarket
                        ? driver.updateMarketOrderStatus(nextStatus!)
                        : driver.updateFoodOrderStatus(nextStatus!),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: actionColor,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: actionColor.withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(actionIcon, color: Colors.white, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          nextAction,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statBlock(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white60,
          ),
        ),
      ],
    );
  }

  void _showRideRequest(Map<String, dynamic> request) {
    if (_isShowingRideRequest) return;
    _isShowingRideRequest = true;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RideRequestSheet(request: request),
    ).whenComplete(() {
      _isShowingRideRequest = false;
    });
  }
}

class _RideRequestSheet extends StatefulWidget {
  final Map<String, dynamic> request;
  const _RideRequestSheet({required this.request});

  @override
  State<_RideRequestSheet> createState() => _RideRequestSheetState();
}

class _RideRequestSheetState extends State<_RideRequestSheet>
    with SingleTickerProviderStateMixin {
  late int _secondsLeft;
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _secondsLeft = (widget.request['expires_in_seconds'] as num?)?.toInt() ?? 30;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _decline();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // booking_id is set for ride/parcel; food orders only carry food_order_id.
  // The provider's accept/decline routes by `is_food` flag and uses the right
  // path, so we just need an int that won't crash the call site.
  int get _requestId =>
      (widget.request['booking_id'] ?? 
       widget.request['food_order_id'] ?? 
       widget.request['market_order_id'] ?? 0) as int;

  bool get _isFood => widget.request['is_food'] == true;

  Future<void> _accept() async {
    if (_busy) return;
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    _timer?.cancel();
    bool ok = false;
    try {
      ok = await context.read<DriverProvider>().acceptRide(_requestId);
    } finally {
      if (mounted) Navigator.pop(context);
    }
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isFood
              ? 'Order already taken by another driver'
              : 'Ride already taken by another driver'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    _timer?.cancel();
    try {
      await context.read<DriverProvider>().declineRide(_requestId);
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final distance = (r['distance_km'] as num?)?.toDouble() ?? 0;
    final duration = (r['duration_min'] as num?)?.toInt() ?? 0;
    final fare = (r['fare'] as num?)?.toDouble() ?? 0;
    final earnings = (r['driver_earnings'] as num?)?.toDouble() ?? fare;
    final paymentMethodRaw = (r['payment_method'] ?? 'cash').toString().toUpperCase();
    final payment = paymentMethodRaw.startsWith('CARD') ? 'CARD' : paymentMethodRaw;
    final customer = (r['customer_name'] ?? 'Customer').toString();
    final initial =
        customer.isNotEmpty ? customer[0].toUpperCase() : 'C';
    final progress = _secondsLeft / 30.0;
    final isFlash = r['is_flash'] == true;
    final isFood = r['is_food'] == true;
    final isMarket = r['is_market'] == true;
    final badgeIcon = isMarket
        ? Icons.storefront_rounded
        : isFood
            ? Icons.restaurant_rounded
            : (isFlash ? Icons.inventory_2_rounded : Icons.bolt_rounded);
    final badgeLabel = isMarket
        ? 'MARKET DELIVERY'
        : isFood
            ? 'FOOD DELIVERY'
            : (isFlash ? 'PARCEL DELIVERY' : 'NEW RIDE');

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      decoration: BoxDecoration(
        gradient: AppColors.blackGradient,
        borderRadius: BorderRadius.circular(32),
        boxShadow: AppStyles.shadowLg,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with countdown
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          badgeIcon,
                          color: AppColors.primary,
                          size: 12,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          badgeLabel,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 36,
                        height: 36,
                        child: CircularProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          strokeWidth: 3,
                          color: _secondsLeft <= 10
                              ? AppColors.error
                              : AppColors.primary,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                      Text(
                        '$_secondsLeft',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Customer + fare
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          '${(r['service_type'] ?? '').toString().toUpperCase()} • $payment',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Rs.${fare.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'You earn Rs.${earnings.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Food banner (only when this is a food delivery)
              if (isFood) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.restaurant_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (r['restaurant_name'] ?? 'Restaurant').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                letterSpacing: 0.2,
                              ),
                            ),
                            Text(
                              '${r['items_count'] ?? 0} item(s) • Order ${r['order_ref'] ?? ''}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                            if ((r['instructions'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '"${r['instructions']}"',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Parcel banner (only when this is a flash delivery)
              if (isFlash) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.inventory_2_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${(r['parcel_type'] ?? 'parcel').toString().toUpperCase()}'
                              '${r['parcel_weight_kg'] != null ? ' • ${r['parcel_weight_kg']} kg' : ''}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 0.4,
                              ),
                            ),
                            if ((r['receiver_name'] ?? '').toString().isNotEmpty ||
                                (r['receiver_phone'] ?? '').toString().isNotEmpty)
                              Text(
                                'To: ${r['receiver_name'] ?? ''}'
                                '${(r['receiver_phone'] ?? '').toString().isNotEmpty ? ' • ${r['receiver_phone']}' : ''}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            if ((r['parcel_instructions'] ?? '').toString().isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  '“${r['parcel_instructions']}”',
                                  style: const TextStyle(
                                    color: Colors.white60,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Pickup + drop
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _addressRow(
                      icon: Icons.my_location_rounded,
                      color: AppColors.flash,
                      label: 'PICKUP',
                      value: (r['pickup_address'] ?? '').toString(),
                    ),
                    // BRD: CD-19 — intermediate stops in the expanded card
                    for (final stop in (r['stops'] as List? ?? const [])) ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 13, top: 6, bottom: 6),
                        child: Column(
                          children: List.generate(
                            2,
                            (_) => Container(
                              margin: const EdgeInsets.only(bottom: 2),
                              width: 2,
                              height: 4,
                              color: Colors.white24,
                            ),
                          ),
                        ),
                      ),
                      _addressRow(
                        icon: Icons.pin_drop_rounded,
                        color: AppColors.warning,
                        label: 'STOP ${stop['order_index'] ?? ''}',
                        value: (stop['address'] ?? '').toString().isEmpty
                            ? 'Stop ${stop['order_index'] ?? ''}'
                            : stop['address'].toString(),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(left: 13, top: 6, bottom: 6),
                      child: Column(
                        children: List.generate(
                          2,
                          (_) => Container(
                            margin: const EdgeInsets.only(bottom: 2),
                            width: 2,
                            height: 4,
                            color: Colors.white24,
                          ),
                        ),
                      ),
                    ),
                    _addressRow(
                      icon: Icons.location_on_rounded,
                      color: AppColors.error,
                      label: 'DROP-OFF',
                      value: (r['drop_address'] ?? '').toString(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Trip stats
              Row(
                children: [
                  _statChip(
                    icon: Icons.straighten_rounded,
                    label: '${distance.toStringAsFixed(1)} km',
                  ),
                  const SizedBox(width: 8),
                  _statChip(
                    icon: Icons.timer_rounded,
                    label: '$duration min',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Actions
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _busy ? null : _decline,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text(
                          'DECLINE',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _busy ? null : _accept,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.black,
                                  strokeWidth: 3,
                                ),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_rounded, color: Colors.black, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    'ACCEPT RIDE',
                                    style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addressRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white60, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _Drawer extends StatelessWidget {
  final VoidCallback onHistory;
  final VoidCallback onDocuments;
  const _Drawer({required this.onHistory, required this.onDocuments});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final driver = context.watch<DriverProvider>();
    final name = auth.fullName ?? 'Driver';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'D';
    final profile = driver.profile ?? const <String, dynamic>{};
    final photoPath = profile['profile_photo']?.toString();
    final photoUrl = (photoPath != null && photoPath.isNotEmpty)
        ? (photoPath.startsWith('http') ? photoPath : '${ApiConfig.baseHost}$photoPath')
        : null;
    final todayEarnings = (profile['today_earnings'] as num?)?.toDouble() ?? 0;
    final totalEarnings = (profile['total_earnings'] as num?)?.toDouble() ?? 0;
    final todayRides = (profile['today_rides'] as num?)?.toInt() ?? 0;
    final paidPayouts = (profile['paid_payouts'] as num?)?.toDouble() ?? 0;
    final pendingPayout = (profile['pending_payout'] as num?)?.toDouble() ?? 0;
    final rating = (profile['rating'] as num?)?.toDouble() ?? 0;
    final isOnline = driver.isOnline;
    final vehicleType = (profile['vehicle_type'] ?? '').toString().toUpperCase();
    final vehicleModel = (profile['vehicle_model'] ?? '').toString();
    final vehicleNumber = (profile['vehicle_number'] ?? '').toString();
    final phone = auth.phoneNumber ?? '';

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Hero card
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.32),
                    blurRadius: 22,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryDark.withOpacity(0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: photoUrl != null
                            ? Image.network(
                                photoUrl,
                                width: 58,
                                height: 58,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Text(
                                  initial,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 26,
                                  ),
                                ),
                              )
                            : Text(
                                initial,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 26,
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: Colors.white,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 13, color: AppColors.accent),
                                const SizedBox(width: 3),
                                Text(
                                  rating > 0 ? rating.toStringAsFixed(1) : '—',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (vehicleType.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(100),
                                    ),
                                    child: Text(
                                      vehicleType,
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: isOnline ? AppColors.success : Colors.white60,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isOnline ? 'ONLINE' : 'OFFLINE',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _heroStat(
                          label: 'TODAY',
                          value: 'Rs.${todayEarnings.toStringAsFixed(0)}',
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: Colors.white24,
                      ),
                      Expanded(
                        child: _heroStat(
                          label: 'RIDES',
                          value: todayRides.toString(),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 28,
                        color: Colors.white24,
                      ),
                      Expanded(
                        child: _heroStat(
                          label: 'TOTAL',
                          value: 'Rs.${totalEarnings.toStringAsFixed(0)}',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Menu
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                children: [
                  _sectionLabel('ACCOUNT'),
                  _menuItem(
                    icon: Icons.history_rounded,
                    color: AppColors.primary,
                    label: 'My Rides',
                    subtitle: 'History & earnings',
                    onTap: onHistory,
                  ),
                  // BRD: Driver document upload UI
                  _menuItem(
                    icon: Icons.badge_rounded,
                    color: AppColors.warning,
                    label: 'KYC Documents',
                    subtitle: 'NIC, license, vehicle reg, insurance',
                    onTap: onDocuments,
                  ),
                  _menuItem(
                    icon: Icons.payments_rounded,
                    color: AppColors.success,
                    label: 'Earnings breakdown',
                    subtitle: 'Today, total and trips',
                    onTap: () => _showEarningsSheet(
                      context,
                      todayEarnings: todayEarnings,
                      totalEarnings: totalEarnings,
                      todayRides: todayRides,
                      paidPayouts: paidPayouts,
                      pendingPayout: pendingPayout,
                    ),
                  ),
                  _menuItem(
                    icon: Icons.directions_car_filled_rounded,
                    color: AppColors.info,
                    label: 'Vehicle info',
                    subtitle: vehicleModel.isEmpty && vehicleNumber.isEmpty
                        ? 'Tap to view'
                        : '$vehicleModel${vehicleNumber.isNotEmpty ? ' • $vehicleNumber' : ''}',
                    onTap: () => _showVehicleSheet(context, profile, phone),
                  ),
                  const SizedBox(height: 14),
                  _sectionLabel('SUPPORT'),
                  _menuItem(
                    icon: Icons.support_agent_rounded,
                    color: AppColors.warning,
                    label: 'Help & Support',
                    subtitle: 'Contact our team',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SupportScreen(isDriver: true)),
                      );
                    },
                  ),
                  _menuItem(
                    icon: Icons.info_outline_rounded,
                    color: AppColors.textSecondary,
                    label: 'About Ziggo',
                    subtitle: 'Version 1.0.0',
                    onTap: () => _showAboutSheet(context),
                  ),
                ],
              ),
            ),
            // Logout
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: GestureDetector(
                onTap: () => _confirmLogout(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Log out',
                        style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _heroStat({required String label, required String value}) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  static Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, top: 4, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  static Widget _menuItem({
    required IconData icon,
    required Color color,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }

  static void _showEarningsSheet(
    BuildContext context, {
    required double todayEarnings,
    required double totalEarnings,
    required int todayRides,
    required double paidPayouts,
    required double pendingPayout,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
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
            const SizedBox(height: 18),
            const Text(
              'Earnings',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LIFETIME EARNINGS',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Rs.${totalEarnings.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _earnTile(
                    label: 'Today',
                    value: 'Rs.${todayEarnings.toStringAsFixed(0)}',
                    icon: Icons.today_rounded,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _earnTile(
                    label: 'Trips today',
                    value: todayRides.toString(),
                    icon: Icons.directions_car_rounded,
                    color: AppColors.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _earnTile(
                    label: 'Paid out',
                    value: 'Rs.${paidPayouts.toStringAsFixed(0)}',
                    icon: Icons.payments_rounded,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _earnTile(
                    label: 'Pending payout',
                    value: 'Rs.${pendingPayout.toStringAsFixed(0)}',
                    icon: Icons.hourglass_empty_rounded,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Tip — earnings update in real-time after each completed ride. Tap "My Rides" to see per-trip breakdowns.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _earnTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  static void _showVehicleSheet(
    BuildContext context,
    Map<String, dynamic> profile,
    String phone,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
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
            const SizedBox(height: 18),
            const Text(
              'Vehicle info',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            _kv('Type', (profile['vehicle_type'] ?? '-').toString().toUpperCase()),
            _kv('Model', (profile['vehicle_model'] ?? '-').toString()),
            _kv('Number', (profile['vehicle_number'] ?? '-').toString()),
            _kv('Color', (profile['vehicle_color'] ?? '-').toString()),
            _kv('License', (profile['license_number'] ?? '-').toString()),
            _kv('NIC', (profile['nic_number'] ?? '-').toString()),
            if (phone.isNotEmpty) _kv('Phone', phone),
            const SizedBox(height: 8),
            const Text(
              'Need to update? Contact support — vehicle details can only be changed by the admin team.',
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              k.toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.textTertiary,
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  static void _showAboutSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 26),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 18),
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Z',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ziggo',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
            ),
            const Text(
              'Version 1.0.0',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Ride · Food · Market · Flash — your super app for Sri Lanka.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _confirmLogout(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 36),
        title: const Text('Log out?', textAlign: TextAlign.center),
        content: const Text(
          'You will go offline and stop receiving ride requests until you log back in.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    if (!context.mounted) return;
    final driver = context.read<DriverProvider>();
    if (driver.isOnline) {
      await driver.toggleOnline(false);
    }
    if (!context.mounted) return;
    await context.read<AuthProvider>().logout();
    if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }
}

class _PendingApprovalScreen extends StatelessWidget {
  final Map<String, dynamic> profile;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;

  const _PendingApprovalScreen({
    required this.profile,
    required this.onRefresh,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 30),
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: AppColors.goldGradient,
                    shape: BoxShape.circle,
                    boxShadow: AppStyles.goldGlow,
                  ),
                  child: const Icon(Icons.hourglass_top_rounded,
                      color: Colors.black, size: 60),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Awaiting approval',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your registration was submitted. The admin will review and approve your account shortly.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  children: [
                    _row('Name', profile['full_name']?.toString() ?? '-'),
                    const Divider(height: 14),
                    _row('Phone', profile['phone_number']?.toString() ?? '-'),
                    const Divider(height: 14),
                    _row('Vehicle',
                        '${profile['vehicle_model'] ?? ''} (${profile['vehicle_number'] ?? ''})'),
                    const Divider(height: 14),
                    _row('Type',
                        (profile['vehicle_type'] ?? '').toString().toUpperCase()),
                    const Divider(height: 14),
                    _row('License', profile['license_number']?.toString() ?? '-'),
                  ],
                ),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'REFRESH STATUS',
                icon: Icons.refresh_rounded,
                onPressed: onRefresh,
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: onLogout,
                child: const Text(
                  'LOG OUT',
                  style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            k,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: AppColors.textTertiary,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
        ),
      ],
    );
  }
}


/// BRD: vertical HUD on the driver map — speed read-out, mute toggle, and
/// the SOS/incident quick-report. Floats over the map top-right.
class _DriverHUD extends StatelessWidget {
  final double speedKmh;
  final bool muted;
  final VoidCallback onToggleMute;
  final VoidCallback onReportIncident;
  const _DriverHUD({
    required this.speedKmh,
    required this.muted,
    required this.onToggleMute,
    required this.onReportIncident,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Speed pill
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppStyles.shadowSm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                speedKmh.toStringAsFixed(0),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Text('km/h',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.6,
                  )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Mute toggle
        GestureDetector(
          onTap: onToggleMute,
          child: Container(
            width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: muted ? AppColors.textTertiary : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppStyles.shadowSm,
            ),
            child: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: muted ? Colors.white : AppColors.textPrimary,
              size: 20,
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Incident report
        GestureDetector(
          onTap: onReportIncident,
          child: Container(
            width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.warning,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppStyles.shadowSm,
            ),
            child: const Icon(Icons.report_rounded, color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }
}
