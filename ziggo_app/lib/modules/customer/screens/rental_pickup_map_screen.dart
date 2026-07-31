import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/app_colors.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';

class RentalPickupMapScreen extends StatefulWidget {
  final Place initialLocation;

  const RentalPickupMapScreen({
    super.key,
    required this.initialLocation,
  });

  @override
  State<RentalPickupMapScreen> createState() => _RentalPickupMapScreenState();
}

class _RentalPickupMapScreenState extends State<RentalPickupMapScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();
  late Place _currentPlace;
  bool _isMoving = false;
  bool _isResolving = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _currentPlace = widget.initialLocation;
  }

  void _onMapPositionChanged(LatLng center) {
    final latDiff = (center.latitude - _currentPlace.location.latitude).abs();
    final lngDiff = (center.longitude - _currentPlace.location.longitude).abs();
    if (latDiff < 0.00001 && lngDiff < 0.00001) {
      return;
    }

    if (!_isMoving) {
      setState(() => _isMoving = true);
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _resolveLocation(center);
    });
  }

  Future<void> _resolveLocation(LatLng center) async {
    setState(() {
      _isMoving = false;
      _isResolving = true;
    });

    final address = await MapsService.instance.reverseGeocode(center);
    
    if (!mounted) return;

    if (address != null) {
      setState(() {
        _currentPlace = Place(
          address.split(',').first, // Main text
          address,                  // Full address
          center,
        );
      });
    }

    setState(() => _isResolving = false);
  }

  void _onConfirm() {
    Navigator.pop(context, _currentPlace);
  }

  void _moveToCurrentLocation() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (here != null && mounted) {
      _mapController.moveTo(here.location, zoom: 16);
      setState(() => _currentPlace = here);
    }
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
              center: _currentPlace.location,
              zoom: 16,
              showMyLocation: true,
              onPositionChanged: _onMapPositionChanged,
            ),
          ),

          // Center Pin (Fixed in center of screen)
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40.0), // Adjust for pin tail
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0099FF), // Pickme blue
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Pickup',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 20,
                    color: Colors.black87,
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top Back Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(Icons.arrow_back_rounded, color: Colors.black87),
              ),
            ),
          ),

          // Bottom Info Sheet
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Current Location Button
                Padding(
                  padding: const EdgeInsets.only(right: 20.0, bottom: 20.0),
                  child: GestureDetector(
                    onTap: _moveToCurrentLocation,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.my_location_rounded, color: Colors.black87),
                    ),
                  ),
                ),

                // White Bottom Sheet
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 20,
                        offset: Offset(0, -5),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Confirm pickup',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE6F0FA),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFF3B5998),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isResolving ? 'Locating...' : _currentPlace.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currentPlace.fullAddress,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isResolving ? null : _onConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2C3E50), // Dark blue/grey
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: const Text(
                            'Confirm',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
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
          ),
        ],
      ),
    );
  }
}
