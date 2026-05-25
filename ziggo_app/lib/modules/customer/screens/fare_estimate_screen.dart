import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';
import '../../../core/network/api_client.dart';
import '../booking_provider.dart';
import 'customer_shell.dart';
import 'ride_tracking_screen.dart';

class FareEstimateScreen extends StatefulWidget {
  const FareEstimateScreen({super.key});

  @override
  State<FareEstimateScreen> createState() => _FareEstimateScreenState();
}

class _FareEstimateScreenState extends State<FareEstimateScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();

  Place? _pickup;
  Place? _drop;
  // BRD: CD-19 — up to 2 intermediate stops between pickup and drop.
  final List<Place> _stops = [];
  static const int _maxStops = 2;
  String? _serviceType;
  String _payment = 'cash';
  String _promo = '';
  String _tripType = 'one_way';
  final _promoController = TextEditingController();

  final Map<String, Map<String, dynamic>> _estimates = {};
  bool _loadingEstimates = false;
  List<LatLng> _routePoints = const [];

  List<Map<String, dynamic>> _nearbyDrivers = const [];
  Timer? _nearbyTimer;

  @override
  void initState() {
    super.initState();
    _pickup = kColomboPlaces[0];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _useCurrentLocationForPickup();
      _startNearbyDriverPolling();
    });
  }

  @override
  void dispose() {
    _nearbyTimer?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  void _startNearbyDriverPolling() {
    _nearbyTimer?.cancel();
    _fetchNearbyDrivers();
    _nearbyTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => _fetchNearbyDrivers(),
    );
  }

  Future<void> _fetchNearbyDrivers() async {
    final pickup = _pickup?.location;
    if (pickup == null) return;
    try {
      final resp = await ApiClient.instance.dio.get(
        '/driver/nearby',
        queryParameters: {
          'lat': pickup.latitude,
          'lng': pickup.longitude,
          'radius_km': 5,
          if (_serviceType != null) 'vehicle_type': _serviceType,
        },
      );
      if (!mounted) return;
      setState(() {
        _nearbyDrivers = List<Map<String, dynamic>>.from(resp.data as List);
      });
    } catch (_) {
      // Silent — drivers won't appear, but the rest of the screen still works.
    }
  }

  IconData _vehicleIcon(String? type) {
    switch (type) {
      case 'bike':
        return Icons.motorcycle_rounded;
      case 'tuk':
        return Icons.electric_rickshaw_rounded;
      case 'car':
        return Icons.directions_car_filled_rounded;
      case 'van':
        return Icons.airport_shuttle_rounded;
      case 'truck':
        return Icons.local_shipping_rounded;
      default:
        return Icons.local_taxi_rounded;
    }
  }

  Color _vehicleColor(String? type) {
    switch (type) {
      case 'bike':
        return AppColors.bike;
      case 'tuk':
        return AppColors.warning;
      case 'car':
        return AppColors.primary;
      case 'van':
        return AppColors.market;
      case 'truck':
        return AppColors.truck;
      default:
        return AppColors.primary;
    }
  }

  String _vehicleAsset(String? type) {
    switch (type) {
      case 'bike':
        return 'assets/icons/bike.png';
      case 'tuk':
        return 'assets/icons/tuk.png';
      case 'truck':
        return 'assets/icons/truck.png';
      case 'van':
      case 'car':
      default:
        return 'assets/icons/car.png';
    }
  }

  Future<void> _useCurrentLocationForPickup() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted || here == null) return;
    setState(() => _pickup = here);
    _mapController.moveTo(here.location, zoom: 15);
    _fetchNearbyDrivers();
    await _recalculate();
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
      return;
    }
    final shell = context.findAncestorStateOfType<CustomerShellState>();
    shell?.goToTab(2);
  }

  Future<void> _recalculate() async {
    if (_pickup == null || _drop == null) return;
    setState(() {
      _loadingEstimates = true;
      _routePoints = const [];
    });
    final booking = context.read<BookingProvider>();
    final stopsPayload = _stops.map((s) => {
          'lat': s.location.latitude,
          'lng': s.location.longitude,
          'address': s.fullAddress,
        }).toList();
    for (final st in const ['bike', 'tuk', 'car', 'van', 'truck']) {
      final res = await booking.estimateFare(
        serviceType: st,
        pickup: _pickup!.location,
        drop: _drop!.location,
        promoCode: _promo.isEmpty ? null : _promo,
        tripType: _tripType,
        stops: stopsPayload,
      );
      if (res != null) _estimates[st] = res;
    }
    if (!mounted) return;
    setState(() => _loadingEstimates = false);
    _fitBounds();

    // Fetch the real road route for the map polyline.
    final dir = await MapsService.instance
        .directions(_pickup!.location, _drop!.location);
    if (mounted && dir != null && dir.points.isNotEmpty) {
      setState(() => _routePoints = dir.points);
    }
  }

  void _fitBounds() {
    if (_pickup == null || _drop == null) return;
    _mapController.fitBounds(
      [_pickup!.location, _drop!.location],
      padding: 80,
    );
  }

  Future<void> _selectLocation(bool isPickup) async {
    final result = await showPlaceSearch(
      context,
      title: isPickup ? 'Pickup location' : 'Drop location',
      near: _pickup?.location ?? kColomboCenter,
      allowCurrentLocation: isPickup,
    );
    if (result != null) {
      setState(() {
        if (isPickup) {
          _pickup = result;
        } else {
          _drop = result;
        }
      });
      if (_pickup != null && _drop != null) {
        await _recalculate();
      } else {
        _mapController.moveTo(result.location, zoom: 15);
      }
    }
  }

  Future<void> _confirmBooking() async {
    if (_pickup == null || _drop == null || _serviceType == null) return;
    HapticFeedback.mediumImpact();
    final booking = context.read<BookingProvider>();
    Map<String, dynamic>? created;
    String? caughtError;
    try {
      created = await booking.createBooking(
        serviceType: _serviceType!,
        pickup: _pickup!.location,
        pickupAddress: _pickup!.fullAddress,
        drop: _drop!.location,
        dropAddress: _drop!.fullAddress,
        paymentMethod: _payment,
        promoCode: _promo.isEmpty ? null : _promo,
        tripType: _tripType,
        stops: _stops
            .map((s) => {
                  'lat': s.location.latitude,
                  'lng': s.location.longitude,
                  'address': s.fullAddress,
                })
            .toList(),
      );
    } catch (e) {
      caughtError = e.toString();
    }
    if (!mounted) return;
    if (created == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 36),
          title: const Text('Booking failed', textAlign: TextAlign.center),
          content: Text(
            caughtError ??
                booking.lastError ??
                'Could not create booking. Check your connection and try again.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RideTrackingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final est = _serviceType == null ? null : _estimates[_serviceType!];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Map with floating back + locations card
          SizedBox(
            height: 300,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ZiggoMap(
                    controller: _mapController,
                    center: _pickup?.location ?? kColomboCenter,
                    zoom: 13,
                    showMyLocation: true,
                    markers: [
                      for (final d in _nearbyDrivers)
                        pinMarker(
                          point: LatLng(
                            (d['lat'] as num).toDouble(),
                            (d['lng'] as num).toDouble(),
                          ),
                          icon: _vehicleIcon(d['vehicle_type'] as String?),
                          color: _vehicleColor(d['vehicle_type'] as String?),
                          size: 30,
                          assetPath: _vehicleAsset(d['vehicle_type'] as String?),
                        ),
                      if (_pickup != null)
                        pinMarker(point: _pickup!.location, icon: Icons.my_location_rounded, color: AppColors.flash),
                      if (_drop != null)
                        pinMarker(point: _drop!.location, icon: Icons.location_on_rounded, color: AppColors.error),
                      // BRD: CD-19 — show every intermediate stop on the map
                      for (final s in _stops)
                        pinMarker(point: s.location, icon: Icons.pin_drop_rounded, color: AppColors.warning),
                    ],
                    polylines: (_pickup != null && _drop != null)
                        ? [
                            ZiggoPolyline(
                              points: _routePoints.isNotEmpty
                                  ? _routePoints
                                  : [_pickup!.location, _drop!.location],
                              strokeWidth: 4,
                              color: Colors.black,
                            ),
                          ]
                        : const [],
                  ),
                ),
                // Soft gradient fade so the locations card pops
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.background.withOpacity(0),
                            AppColors.background,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _handleBack,
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: AppStyles.shadowSm,
                            ),
                            child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                          ),
                        ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Locations card (overlapping map slightly)
          Transform.translate(
            offset: const Offset(0, -28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: AppStyles.shadowMd,
                ),
                child: Column(
                  children: [
                    _routeRow(
                      isPickup: true,
                      icon: Icons.my_location_rounded,
                      label: 'PICKUP',
                      value: _pickup?.fullAddress ?? 'Set pickup',
                      color: AppColors.flash,
                    ),
                    // BRD: CD-19 — render any intermediate stops + the +Add button
                    for (int i = 0; i < _stops.length; i++) ...[
                      _stopDots(),
                      _stopRow(index: i),
                    ],
                    _stopDots(),
                    if (_stops.length < _maxStops)
                      _addStopButton(),
                    _routeRow(
                      isPickup: false,
                      icon: Icons.location_on_rounded,
                      label: 'DROP-OFF',
                      value: _drop?.fullAddress ?? 'Set drop',
                      color: AppColors.error,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              children: [
                _sectionHeader('TRIP TYPE'),
                const SizedBox(height: 8),
                _tripTypeToggle(),
                const SizedBox(height: 18),
                _sectionHeader('CHOOSE A RIDE', subtitle: 'Tap to select'),
                const SizedBox(height: 12),
                for (final st in const ['bike', 'tuk', 'car', 'van', 'truck']) _vehicleTile(st),
                const SizedBox(height: 18),
                _sectionHeader('PROMO CODE'),
                const SizedBox(height: 8),
                _promoField(),
                const SizedBox(height: 18),
                _sectionHeader('PAYMENT'),
                const SizedBox(height: 8),
                _paymentRow(),
              ],
            ),
          ),
          // Bottom action bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total fare',
                          style: TextStyle(
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          est == null ? '--' : 'Rs.${(est['final_amount'] as num).toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            letterSpacing: -0.5,
                          ),
                        ),
                        if (est != null && (est['distance_km'] as num) > 0)
                          Row(
                            children: [
                              const Icon(Icons.timer_rounded, size: 12, color: AppColors.textSecondary),
                              const SizedBox(width: 3),
                              Text(
                                '${(est['distance_km'] as num).toStringAsFixed(1)} km • ${est['duration_min']} min',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: PrimaryButton(
                      label: 'BOOK NOW',
                      icon: Icons.bolt_rounded,
                      gold: true,
                      busy: _loadingEstimates,
                      onPressed: est == null ? null : _confirmBooking,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text, {String? subtitle}) {
    return Row(
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 8),
          Text(
            '• $subtitle',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  // BRD: CD-19 — small connector dots between pickup / each stop / drop.
  Widget _stopDots() {
    return Padding(
      padding: const EdgeInsets.only(left: 28),
      child: Row(
        children: [
          for (int i = 0; i < 4; i++) ...[
            Container(
              width: 3, height: 3,
              decoration: const BoxDecoration(
                color: AppColors.divider, shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  // BRD: CD-19 — a row showing one intermediate stop with a remove button.
  Widget _stopRow({required int index}) {
    final s = _stops[index];
    return InkWell(
      onTap: () => _pickStop(replaceIndex: index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 28, height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${index + 1}',
                  style: const TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  )),
            ),
            const SizedBox(width: 12),
            const Text('STOP',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                )),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.fullAddress,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              color: AppColors.textTertiary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                setState(() => _stops.removeAt(index));
                if (_pickup != null && _drop != null) _recalculate();
              },
            ),
          ],
        ),
      ),
    );
  }

  // BRD: CD-19 — "+ Add stop" affordance between pickup and drop.
  Widget _addStopButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: InkWell(
        onTap: () => _pickStop(),
        borderRadius: BorderRadius.circular(10),
        child: Row(
          children: [
            const SizedBox(width: 16),
            const Icon(Icons.add_location_alt_rounded,
                size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              _stops.isEmpty ? 'Add stop' : 'Add another stop',
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStop({int? replaceIndex}) async {
    final picked = await showPlaceSearch(
      context,
      title: replaceIndex != null
          ? 'Edit stop ${replaceIndex + 1}'
          : 'Add stop ${_stops.length + 1}',
      near: _pickup?.location ?? kColomboCenter,
      allowCurrentLocation: false,
    );
    if (picked == null) return;
    setState(() {
      if (replaceIndex != null) {
        _stops[replaceIndex] = picked;
      } else {
        _stops.add(picked);
      }
    });
    if (_pickup != null && _drop != null) await _recalculate();
  }

  Widget _routeRow({
    required bool isPickup,
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return InkWell(
      onTap: () => _selectLocation(isPickup),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textTertiary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_rounded, size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _tripTypeToggle() {
    Widget cell(String value, String label, IconData icon) {
      final selected = _tripType == value;
      return Expanded(
        child: GestureDetector(
          onTap: () {
            if (_tripType == value) return;
            setState(() => _tripType = value);
            _recalculate();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          cell('one_way', 'One way', Icons.arrow_forward_rounded),
          cell('return', 'Return', Icons.compare_arrows_rounded),
        ],
      ),
    );
  }

  Widget _vehicleTile(String st) {
    final selected = _serviceType == st;
    final est = _estimates[st];

    final meta = {
      'bike': ('Bike', 'Fastest, lightest', 'assets/icons/bike.png'),
      'tuk': ('Tuk-tuk', 'Open-air, 3 seats', 'assets/icons/tuk.png'),
      'car': ('Car', 'Comfortable, AC', 'assets/icons/car.png'),
      'van': ('Van', 'Up to 8 seats', 'assets/icons/taxi.png'),
      'truck': ('Truck', 'Heavy goods', 'assets/icons/truck.png'),
    }[st]!;

    return GestureDetector(
      onTap: () {
        setState(() => _serviceType = st);
        _fetchNearbyDrivers();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected ? AppStyles.shadowMd : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Image.asset(meta.$3, fit: BoxFit.contain),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.$1,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: selected ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    est == null
                        ? meta.$2
                        : '${(est['distance_km'] as num).toStringAsFixed(1)} km • ${est['duration_min']} min',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white60 : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  est == null ? '--' : 'Rs.${(est['final_amount'] as num).toStringAsFixed(0)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                // BRD: RS-07 — per-ride loyalty points display.
                if (est != null && (est['points_earnable'] ?? 0) is num && (est['points_earnable'] as num) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white.withOpacity(0.18) : const Color(0x14F59E0B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '+${est['points_earnable']} pts',
                        style: TextStyle(
                          color: selected ? Colors.white : AppColors.warning,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                if (selected)
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle, color: Colors.white, size: 14),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _promoField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_offer_rounded, color: AppColors.success, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _promoController,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1),
              decoration: const InputDecoration(
                hintText: 'Try ZIGGO50',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: (v) {
                _promo = v.trim().toUpperCase();
                _recalculate();
              },
            ),
          ),
          GestureDetector(
            onTap: () {
              _promo = _promoController.text.trim().toUpperCase();
              _recalculate();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'APPLY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentRow() {
    return Row(
      children: [
        _payOption('cash', Icons.payments_rounded, 'Cash'),
        const SizedBox(width: 10),
        _payOption('wallet', Icons.account_balance_wallet_rounded, 'Wallet'),
      ],
    );
  }

  Widget _payOption(String value, IconData icon, String label) {
    final selected = _payment == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _payment = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.black : AppColors.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: selected ? AppColors.primary : AppColors.textPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              if (selected) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, color: AppColors.primary, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
