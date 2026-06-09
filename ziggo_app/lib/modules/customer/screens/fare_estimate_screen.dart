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
import 'customer_shell.dart';
import 'location_search_screen.dart';

class FareEstimateScreen extends StatefulWidget {
  const FareEstimateScreen({super.key});

  @override
  State<FareEstimateScreen> createState() => _FareEstimateScreenState();
}

class _FareEstimateScreenState extends State<FareEstimateScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();
  Place? _currentLocation;
  List<Map<String, dynamic>> _nearbyDrivers = const [];
  Timer? _nearbyTimer;

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
        ),
      ),
    );
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
                for (final d in _nearbyDrivers)
                  pinMarker(
                    point: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
                    icon: Icons.local_taxi_rounded,
                    color: AppColors.primary,
                    size: 30,
                    assetPath: 'assets/icons/top_car.png',
                  ),
                if (_currentLocation != null)
                  pinMarker(
                    point: _currentLocation!.location,
                    icon: Icons.my_location_rounded,
                    color: AppColors.info,
                    label: 'Meet your driver here',
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
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 4)),
                ],
                border: Border.all(color: Colors.blueAccent, width: 3), // Emphasizing the bottom sheet similar to the UI markup
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: AppStyles.shadowSm,
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.directions_car_rounded, size: 18),
                              SizedBox(width: 6),
                              Icon(Icons.access_time_rounded, size: 14),
                              SizedBox(width: 8),
                              Text('Later', style: TextStyle(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: AppStyles.shadowSm),
                          child: const Icon(Icons.my_location_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Central Card inside the bottom sheet
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: AppStyles.shadowSm,
                    ),
                    child: Column(
                      children: [
                        // Trip Type Toggle Fake UI
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _openSearch(tripType: 'one_way'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceMuted,
                                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16)),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_rounded, size: 16),
                                      SizedBox(width: 6),
                                      Text('One way', style: TextStyle(fontWeight: FontWeight.w800)),
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
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.only(topRight: Radius.circular(16)),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.radio_button_unchecked_rounded, size: 16, color: AppColors.textSecondary),
                                      SizedBox(width: 6),
                                      Text('Return trip*', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        // Locations
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Column(
                                children: [
                                  const Text('PICKUP', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900)),
                                  Container(height: 20, width: 2, color: AppColors.divider),
                                  const Text('DROP', style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w900)),
                                ],
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _openSearch(focusDrop: false),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Your location', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                          Icon(Icons.favorite_border_rounded, size: 20),
                                        ],
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 8),
                                      child: Divider(height: 1),
                                    ),
                                    GestureDetector(
                                      onTap: () => _openSearch(focusDrop: true),
                                      child: const Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('Where are you going?', style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w600, fontSize: 16)),
                                          Icon(Icons.add_rounded, size: 24),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
