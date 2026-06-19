import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';
import '../../../core/network/api_client.dart';
import 'add_stops_screen.dart';
import 'customer_shell.dart';
import 'location_search_screen.dart';
import 'vehicle_selection_screen.dart';

class FareEstimateScreen extends StatefulWidget {
  final bool isTruckMode;
  const FareEstimateScreen({super.key, this.isTruckMode = false});

  @override
  State<FareEstimateScreen> createState() => _FareEstimateScreenState();
}

class _FareEstimateScreenState extends State<FareEstimateScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();
  Place? _currentLocation;
  List<Map<String, dynamic>> _nearbyDrivers = const [];
  Timer? _nearbyTimer;
  DateTime? _scheduledTime;
  String _tripType = 'one_way';
  List<Place> _stops = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
    });
  }

  @override
  void dispose() {
    _nearbyTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted || here == null) return;
    setState(() => _currentLocation = here);
    _mapController.moveTo(here.location, zoom: 16);
    _startNearbyDriverPolling();
  }

  Future<void> _moveToCurrentLocation() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted || here == null) return;
    setState(() => _currentLocation = here);
    _mapController.moveTo(here.location, zoom: 16);
  }

  String _formatDateTime(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return "$month ${dt.day}, $hour:$minute $period";
  }

  Future<void> _handleLaterTap() async {
    if (_scheduledTime != null) {
      final action = await showModalBottomSheet<String>(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                'Scheduled Ride: ${_formatDateTime(_scheduledTime!)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit_calendar_rounded, color: AppColors.primary),
                title: const Text('Change Date & Time'),
                onTap: () => Navigator.pop(ctx, 'change'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.cancel_outlined, color: AppColors.error),
                title: const Text('Cancel Schedule'),
                onTap: () => Navigator.pop(ctx, 'cancel'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );

      if (action == 'cancel') {
        setState(() => _scheduledTime = null);
        return;
      } else if (action != 'change') {
        return;
      }
    }

    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (t == null || !mounted) return;

    final selected = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (selected.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot schedule in the past')),
      );
      return;
    }

    setState(() => _scheduledTime = selected);
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
    final loc = _currentLocation?.location;
    if (loc == null) return;
    try {
      final resp = await ApiClient.instance.dio.get(
        '/driver/nearby',
        queryParameters: {
          'lat': loc.latitude,
          'lng': loc.longitude,
          'radius_km': 5,
        },
      );
      if (!mounted) return;
      setState(() {
        _nearbyDrivers = List<Map<String, dynamic>>.from(resp.data as List);
      });
    } catch (_) {}
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
      return;
    }
    final shell = context.findAncestorStateOfType<CustomerShellState>();
    shell?.goToTab(2);
  }

  void _openSearch({bool focusDrop = true, String tripType = 'one_way'}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationSearchScreen(
          initialPickup: _currentLocation,
          initialTripType: tripType,
          isTruckMode: widget.isTruckMode,
          initialStops: _stops,
        ),
      ),
    );
  }

  Future<void> _openAddStops() async {
    if (_currentLocation == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddStopsScreen(
          pickup: _currentLocation!,
          initialStops: _stops,
        ),
      ),
    );
    
    if (result != null && result is Map) {
      if (!mounted) return;
      setState(() {
        _stops = List<Place>.from(result['stops']);
      });
      final drop = result['drop'] as Place;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VehicleSelectionScreen(
            pickup: _currentLocation!,
            drop: drop,
            tripType: _tripType,
            isTruckMode: widget.isTruckMode,
            stops: _stops,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: ZiggoMap(
              controller: _mapController,
              center: _currentLocation?.location ?? kColomboCenter,
              zoom: 16,
              showMyLocation: false, // We'll show a custom marker instead
              markers: [
                if (_currentLocation != null)
                  pinMarker(
                    point: _currentLocation!.location,
                    icon: Icons.my_location_rounded,
                    color: AppColors.info,
                    label: widget.isTruckMode ? 'Meet your truck here' : 'Meet your driver here',
                  ),
              ],
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
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppStyles.shadowSm),
                      child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: true,
            top: false,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(color: AppColors.cardBorder, width: 1),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top row with "Later" and "GPS" buttons
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: _handleLaterTap,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F3F3),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    widget.isTruckMode
                                        ? Icons.local_shipping_rounded
                                        : Icons.directions_car_filled_rounded,
                                    size: 18,
                                    color: Colors.black87,
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.access_time_filled_rounded,
                                    size: 14,
                                    color: Colors.black87,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _scheduledTime != null
                                        ? _formatDateTime(_scheduledTime!)
                                        : 'Later',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _moveToCurrentLocation,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Color(0xFFF3F3F3),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.my_location_rounded,
                                size: 18,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Trip Type Toggle Row
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openSearch(tripType: 'one_way'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _tripType == 'one_way'
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: _tripType == 'one_way'
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.05),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _tripType == 'one_way'
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      size: 16,
                                      color: _tripType == 'one_way'
                                          ? Colors.black87
                                          : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'One way',
                                      style: TextStyle(
                                        fontWeight: _tripType == 'one_way'
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: _tripType == 'one_way'
                                            ? Colors.black87
                                            : AppColors.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _openSearch(tripType: 'return'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: _tripType == 'return'
                                      ? Colors.white
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: _tripType == 'return'
                                      ? [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.05),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _tripType == 'return'
                                          ? Icons.check_circle_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      size: 16,
                                      color: _tripType == 'return'
                                          ? Colors.black87
                                          : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Return trip*',
                                      style: TextStyle(
                                        fontWeight: _tripType == 'return'
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                        color: _tripType == 'return'
                                            ? Colors.black87
                                            : AppColors.textSecondary,
                                        fontSize: 13,
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
                    const SizedBox(height: 8),

                    // Pickup & Drop locations
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 60,
                                child: Text(
                                  'PICKUP',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _openSearch(focusDrop: false),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _currentLocation?.name ?? 'Your location',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 15,
                                            color: Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Icon(
                                        Icons.favorite_border_rounded,
                                        size: 20,
                                        color: Colors.black87,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Divider(
                              height: 1,
                              color: AppColors.divider.withOpacity(0.8),
                            ),
                          ),
                          if (_stops.isNotEmpty)
                            for (int i = 0; i < _stops.length; i++) ...[
                              Row(
                                children: [
                                  SizedBox(
                                    width: 60,
                                    child: Text(
                                      'STOP ${i + 1}',
                                      style: const TextStyle(
                                        color: AppColors.warning,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      _stops[i].name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Divider(
                                  height: 1,
                                  color: AppColors.divider.withOpacity(0.8),
                                ),
                              ),
                            ],
                          Row(
                            children: [
                              const SizedBox(
                                width: 60,
                                child: Text(
                                  'DROP',
                                  style: TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => _openSearch(focusDrop: true),
                                        child: const Text(
                                          'Where are you going?',
                                          style: TextStyle(
                                            color: AppColors.textTertiary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _openAddStops,
                                      child: const Icon(
                                        Icons.add_rounded,
                                        size: 24,
                                        color: Colors.black87,
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
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
