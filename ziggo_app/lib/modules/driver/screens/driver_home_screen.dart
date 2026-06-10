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
import '../../auth/auth_provider.dart';
import '../../customer/screens/support_screen.dart';
import '../driver_provider.dart';
import '../driver_theme.dart';
import 'driver_history_screen.dart';
import 'driver_documents_screen.dart';
import 'driver_earnings_screen.dart';
import 'driver_profile_screen.dart';
import 'driver_registration_screen.dart';

// Ziggo dark driver UI tokens — deep navy brand surfaces + gold accent.
const Color _kPanel = Color(0xFF111A33);       // deep navy (brand primaryDark tone)
const Color _kPanelLight = Color(0xFF1B2A52);  // lighter navy for inset cards
const Color _kGold = AppColors.accent;         // Ziggo gold accent (#FBBF24)

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
  bool _incentivesExpanded = true;   // PickMe bottom panel collapse/expand

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
              opacity: 1.0,
              child: ZiggoMap(
                controller: _mapController,
                center: loc,
                zoom: 15,
                showMyLocation: true,
                darkMode: true,
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
          SafeArea(child: _buildTopBar(driver)),
          if (ride != null || food != null || market != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildBottomCard(driver, ride, food, market),
            )
          else
            Align(
              alignment: Alignment.bottomCenter,
              child: _buildPickMeIdle(driver),
            ),
          // BRD: speed display + mute toggle + incident-report quick action.
          // Only shown while on an active trip (mirrors the PickMe driving HUD).
          if (driver.isOnline && (ride != null || food != null || market != null))
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

  // ── PickMe-style driver home ─────────────────────────────────────────────

  Widget _buildTopBar(DriverProvider driver) {
    final auth = context.read<AuthProvider>();
    final profile = driver.profile ?? const <String, dynamic>{};
    final name = auth.fullName ?? 'Driver';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'D';
    final photoPath = profile['profile_photo']?.toString();
    final photoUrl = (photoPath != null && photoPath.isNotEmpty)
        ? (photoPath.startsWith('http')
            ? photoPath
            : '${ApiConfig.baseHost}$photoPath')
        : null;
    final earnings = (profile['today_earnings'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kPanel,
                border: Border.all(color: Colors.white24, width: 2),
                boxShadow: AppStyles.shadowSm,
              ),
              clipBehavior: Clip.antiAlias,
              child: photoUrl != null
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarFallback(initial),
                    )
                  : _avatarFallback(initial),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 7),
              decoration: BoxDecoration(
                color: _kPanel,
                borderRadius: BorderRadius.circular(100),
                boxShadow: AppStyles.shadowSm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      const Text(
                        'LKR ',
                        style: TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        earnings.toStringAsFixed(2),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.savings_rounded, color: _kGold, size: 12),
                      SizedBox(width: 4),
                      Text(
                        'Earnings',
                        style: TextStyle(
                          color: Colors.white60,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => _handleToggleOnline(!driver.isOnline),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kPanel,
                boxShadow: AppStyles.shadowSm,
              ),
              child: Icon(
                Icons.swap_horiz_rounded,
                color: driver.isOnline ? _kGold : Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String initial) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
      ),
    );
  }

  Widget _buildPickMeIdle(DriverProvider driver) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _statusPill(driver),
        const SizedBox(height: 16),
        _incentivesPanel(driver),
      ],
    );
  }

  /// Floating availability toggle — a sliding switch. The power knob sits on
  /// the left (dark) when offline and slides right (green) when online. Tapping
  /// anywhere on the pill flips the state.
  Widget _statusPill(DriverProvider driver) {
    final online = driver.isOnline;
    const dur = Duration(milliseconds: 260);
    const curve = Curves.easeOut;

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        _handleToggleOnline(!online);
      },
      child: AnimatedContainer(
        duration: dur,
        curve: curve,
        width: 208,
        height: 60,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: online ? AppColors.success : _kPanel,
          borderRadius: BorderRadius.circular(100),
          boxShadow: online
              ? [
                  BoxShadow(
                    color: AppColors.success.withOpacity(0.45),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ]
              : AppStyles.shadowLg,
        ),
        child: Stack(
          children: [
            // Label — sits opposite the knob.
            AnimatedAlign(
              duration: dur,
              curve: curve,
              alignment:
                  online ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  online ? 'Online' : 'Go online',
                  style: TextStyle(
                    color: online ? Colors.white : _kGold,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
              ),
            ),
            // Sliding knob.
            AnimatedAlign(
              duration: dur,
              curve: curve,
              alignment:
                  online ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.power_settings_new_rounded,
                  color: online ? AppColors.success : const Color(0xFF24345E),
                  size: 24,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _incentivesPanel(DriverProvider driver) {
    final todayRides = (driver.profile?['today_rides'] as num?)?.toInt() ?? 0;
    const goal = 3;
    final progress = (todayRides / goal).clamp(0.0, 1.0);

    final expanded = _incentivesExpanded;

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _kPanel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle — tap or swipe to collapse/expand the panel.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    setState(() => _incentivesExpanded = !_incentivesExpanded),
                onVerticalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (v > 80 && _incentivesExpanded) {
                    setState(() => _incentivesExpanded = false);
                  } else if (v < -80 && !_incentivesExpanded) {
                    setState(() => _incentivesExpanded = true);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'One Day Incentives',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.access_time_rounded, color: _kGold, size: 15),
                  const SizedBox(width: 5),
                  const Text(
                    '14 hours',
                    style: TextStyle(
                      color: Colors.white60,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: Colors.white38,
                    size: 20,
                  ),
                ],
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                            decoration: BoxDecoration(
                              color: _kPanelLight,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '1. Complete 3 trips to earn an additional LKR 350.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _incentiveProgress(todayRides, goal, progress),
                              ],
                            ),
                          ),
                          if (driver.isOnline) ...[
                            const SizedBox(height: 18),
                            const Text(
                              'Shortcuts',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _shortcutButton(
                              icon: Icons.insights_rounded,
                              label: 'My performance',
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const DriverHistoryScreen()),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _shortcutButton(
                              icon: Icons.directions_walk_rounded,
                              label: 'Road pickup trip',
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Road pickup trips are coming soon.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _incentiveProgress(int rides, int goal, double progress) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final knobX = ((w - 22) * progress).clamp(0.0, w - 22);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 22,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  Container(
                    height: 8,
                    width: (w * progress).clamp(0.0, w),
                    decoration: BoxDecoration(
                      color: _kGold,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  Positioned.fill(
                    child: Center(
                      child: Text(
                        '$rides/$goal',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: knobX,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: _kGold, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                'Goal: 3 trips',
                style: TextStyle(
                  color: Colors.white38,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _shortcutButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38, size: 22),
          ],
        ),
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

    final grossTotal = (ride['final_amount'] as num?)?.toDouble() ?? 0.0;
    final appUsage = (ride['app_usage_charges'] as num?)?.toDouble() ?? (ride['platform_fee'] as num?)?.toDouble() ?? 0.0;
    final passDeductible = (ride['passenger_deductible'] as num?)?.toDouble() ?? 0.0;
    final totalDeductions = (ride['deductions'] as num?)?.toDouble() ?? (appUsage + passDeductible);
    final driverEarnings = (ride['driver_earnings'] as num?)?.toDouble() ?? (grossTotal - totalDeductions);

    Widget buildItemizedRow(String label, String val, {bool isNegative = false, bool isBold = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: isBold ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
            Text(isNegative ? '-Rs.$val' : 'Rs.$val', style: TextStyle(fontSize: 12, color: isNegative ? AppColors.error : (isBold ? AppColors.primary : AppColors.textPrimary), fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      );
    }

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
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 8),
              buildItemizedRow('Gross Total', grossTotal.toStringAsFixed(2), isBold: true),
              buildItemizedRow('App Usage Charges', appUsage.toStringAsFixed(2), isNegative: true),
              if (passDeductible > 0)
                buildItemizedRow('Passenger Deductible', passDeductible.toStringAsFixed(2), isNegative: true),
              buildItemizedRow('Total Deductions', totalDeductions.toStringAsFixed(2), isNegative: true, isBold: true),
              const Divider(height: 1),
              const SizedBox(height: 8),
              buildItemizedRow('Your Net Earnings', driverEarnings.toStringAsFixed(2), isBold: true),
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
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 8),
              buildItemizedRow('Gross Total', grossTotal.toStringAsFixed(2), isBold: true),
              buildItemizedRow('App Usage Charges', appUsage.toStringAsFixed(2), isNegative: true),
              if (passDeductible > 0)
                buildItemizedRow('Passenger Deductible', passDeductible.toStringAsFixed(2), isNegative: true),
              buildItemizedRow('Total Deductions', totalDeductions.toStringAsFixed(2), isNegative: true, isBold: true),
              const Divider(height: 1),
              const SizedBox(height: 8),
              buildItemizedRow('Your Net Earnings', driverEarnings.toStringAsFixed(2), isBold: true),
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
    final driverId = (profile['id'] ?? '—').toString();

    return Drawer(
      backgroundColor: _kPanel,
      child: Column(
        children: [
          // Blue gradient header
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                18, MediaQuery.of(context).padding.top + 16, 16, 22),
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photoUrl != null
                      ? Image.network(
                          photoUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _drawerInitial(initial),
                        )
                      : _drawerInitial(initial),
                ),
                const SizedBox(width: 14),
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
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        driverId,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _confirmLogout(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.logout_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
          // Menu list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _drawerTile(
                  icon: Icons.person_outline_rounded,
                  label: 'Profile',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DriverProfileScreen()),
                    );
                  },
                ),
                _drawerTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Earnings',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const DriverEarningsScreen()),
                    );
                  },
                ),
                _drawerTile(
                  icon: Icons.insights_rounded,
                  label: 'My performance',
                  chevronDown: true,
                  onTap: onHistory,
                ),
                _drawerTile(
                  icon: Icons.badge_outlined,
                  label: 'KYC documents',
                  onTap: onDocuments,
                ),
              ],
            ),
          ),
          // Settings + version footer
          _drawerTile(
            icon: Icons.settings_outlined,
            label: 'Settings and support',
            accent: true,
            chevronDown: true,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const SupportScreen(isDriver: true)),
              );
            },
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: Text(
              'Version 1.0.0',
              style: TextStyle(
                color: Colors.white38,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _drawerInitial(String initial) => Text(
        initial,
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w900,
          fontSize: 24,
        ),
      );

  static Widget _drawerTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool accent = false,
    bool chevronDown = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(width: 18),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              if (accent) ...[
                const SizedBox(width: 8),
                const Icon(Icons.auto_awesome, color: AppColors.primaryLight, size: 14),
              ],
              const Spacer(),
              if (chevronDown)
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white38, size: 22),
            ],
          ),
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
    return Theme(
      data: driverDarkTheme(context),
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: kDriverBg,
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
                  color: kDriverCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white10),
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
