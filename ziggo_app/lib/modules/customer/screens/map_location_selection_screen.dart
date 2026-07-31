import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';
import 'vehicle_selection_screen.dart';

class MapLocationSelectionScreen extends StatefulWidget {
  final Place? initialPickup;
  final Place? initialDrop;
  final String initialTripType;
  final bool isTruckMode;
  final bool startWithPickup;

  const MapLocationSelectionScreen({
    super.key,
    this.initialPickup,
    this.initialDrop,
    this.initialTripType = 'one_way',
    this.isTruckMode = false,
    this.startWithPickup = false,
  });

  @override
  State<MapLocationSelectionScreen> createState() => _MapLocationSelectionScreenState();
}

class _MapLocationSelectionScreenState extends State<MapLocationSelectionScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();
  Place? _pickup;
  Place? _drop;
  String _tripType = 'one_way';
  bool _isSelectingPickup = false;

  Place? _currentPlace;
  bool _isResolving = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _pickup = widget.initialPickup;
    _drop = widget.initialDrop;
    _tripType = widget.initialTripType;
    _isSelectingPickup = widget.startWithPickup || _pickup == null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initMapLocation();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initMapLocation() async {
    final startPlace = _isSelectingPickup 
        ? (_pickup ?? await MapsService.instance.currentLocationAsPlace() ?? kColomboPlaces[0])
        : (_drop ?? _pickup ?? await MapsService.instance.currentLocationAsPlace() ?? kColomboPlaces[0]);
    
    setState(() {
      _currentPlace = startPlace;
    });

    _mapController.moveTo(startPlace.location, zoom: 16);
  }

  void _onMapPositionChanged(LatLng center) {
    if (_currentPlace == null) return;
    
    final latDiff = (center.latitude - _currentPlace!.location.latitude).abs();
    final lngDiff = (center.longitude - _currentPlace!.location.longitude).abs();
    if (latDiff < 0.00001 && lngDiff < 0.00001) {
      return;
    }
    
    setState(() {
      _currentPlace = Place(
        _isSelectingPickup ? 'Pickup Location' : 'Dropoff Location',
        'Fetching address...',
        center,
      );
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      _resolveLocation(center);
    });
  }

  Future<void> _resolveLocation(LatLng center) async {
    if (!mounted) return;
    setState(() {
      _isResolving = true;
    });

    final address = await MapsService.instance.reverseGeocode(center);

    if (!mounted) return;

    if (address != null) {
      final resolvedPlace = Place(
        address.split(',').first, // Main text
        address,                  // Full address
        center,
      );

      setState(() {
        _currentPlace = resolvedPlace;
        if (_isSelectingPickup) {
          _pickup = resolvedPlace;
        } else {
          _drop = resolvedPlace;
        }
      });
    }

    setState(() => _isResolving = false);
  }

  void _moveToCurrentLocation() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (here != null && mounted) {
      _mapController.moveTo(here.location, zoom: 16);
      setState(() {
        _currentPlace = here;
        if (_isSelectingPickup) {
          _pickup = here;
        } else {
          _drop = here;
        }
      });
    }
  }

  void _onConfirm() {
    if (_currentPlace == null) return;

    if (_isSelectingPickup) {
      _pickup = _currentPlace;
      if (_drop == null) {
        setState(() {
          _isSelectingPickup = false;
        });
        // Keep map center, but start geocoding for dropoff
        _onMapPositionChanged(_currentPlace!.location);
      } else {
        _proceedToBooking();
      }
    } else {
      _drop = _currentPlace;
      if (_pickup == null) {
        setState(() {
          _isSelectingPickup = true;
        });
        _onMapPositionChanged(_currentPlace!.location);
      } else {
        _proceedToBooking();
      }
    }
  }

  void _proceedToBooking() {
    if (_pickup == null || _drop == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleSelectionScreen(
          pickup: _pickup!,
          drop: _drop!,
          tripType: _tripType,
          isTruckMode: widget.isTruckMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map Background
          Positioned.fill(
            child: ZiggoMap(
              controller: _mapController,
              center: _currentPlace?.location ?? kColomboCenter,
              zoom: 16,
              showMyLocation: true,
              onPositionChanged: _onMapPositionChanged,
            ),
          ),

          // Center Pin (Fixed in center of screen)
          Center(
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.orange, width: 6),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 6, spreadRadius: 1),
                ],
              ),
            ),
          ),

          // Top panel matching the user request
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Trip Type Toggle Fake UI matching design
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _tripType = 'one_way'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _tripType == 'one_way' ? AppColors.surfaceMuted : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _tripType == 'one_way' ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                  size: 16,
                                  color: _tripType == 'one_way' ? AppColors.textPrimary : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'One way',
                                  style: TextStyle(
                                    fontWeight: _tripType == 'one_way' ? FontWeight.w800 : FontWeight.w600,
                                    color: _tripType == 'one_way' ? AppColors.textPrimary : AppColors.textSecondary,
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
                          onTap: () => setState(() => _tripType = 'return'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: _tripType == 'return' ? AppColors.surfaceMuted : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _tripType == 'return' ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                  size: 16,
                                  color: _tripType == 'return' ? AppColors.textPrimary : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Return trip*',
                                  style: TextStyle(
                                    fontWeight: _tripType == 'return' ? FontWeight.w800 : FontWeight.w600,
                                    color: _tripType == 'return' ? AppColors.textPrimary : AppColors.textSecondary,
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
                  const SizedBox(height: 12),
                  // Pickup & Drop panel
                  Row(
                    children: [
                      Column(
                        children: [
                          const Text('PICKUP', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900)),
                          if (_tripType == 'return') ...[
                            Container(height: 12, width: 2, color: AppColors.divider),
                            const Text('STOP', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w900)),
                            Container(height: 12, width: 2, color: AppColors.divider),
                            const Text('DROP', style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w900)),
                          ] else ...[
                            Container(height: 20, width: 2, color: AppColors.divider),
                            const Text('DROP', style: TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.w900)),
                          ],
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isSelectingPickup = true;
                                });
                                if (_pickup != null) {
                                  _mapController.moveTo(_pickup!.location, zoom: 16);
                                  _onMapPositionChanged(_pickup!.location);
                                }
                              },
                              child: Text(
                                _pickup?.name ?? 'Your Location',
                                style: TextStyle(
                                  fontWeight: _isSelectingPickup ? FontWeight.w900 : FontWeight.w600,
                                  color: _isSelectingPickup ? AppColors.textPrimary : AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Divider(height: 1),
                            ),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isSelectingPickup = false;
                                });
                                if (_drop != null) {
                                  _mapController.moveTo(_drop!.location, zoom: 16);
                                  _onMapPositionChanged(_drop!.location);
                                }
                              },
                              child: Text(
                                _drop?.name ?? 'Where are you going?',
                                style: TextStyle(
                                  fontWeight: !_isSelectingPickup ? FontWeight.w900 : FontWeight.w600,
                                  color: !_isSelectingPickup ? AppColors.textPrimary : AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (_tripType == 'return') ...[
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 6),
                                child: Divider(height: 1),
                              ),
                              const Text(
                                'Same as pickup',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Floating Controls and Bottom Card
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Floating back and locate-me buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Floating Back Button
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
                        ),
                      ),

                      // Floating Locate-Me Button
                      GestureDetector(
                        onTap: _moveToCurrentLocation,
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.my_location_rounded, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),

                // Large Black Button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isResolving ? null : _onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(26),
                        ),
                      ),
                      child: Text(
                        _isSelectingPickup ? 'SET PICKUP LOCATION' : 'SET DROP LOCATION',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
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
