import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/map/maps_service.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';

class ConfirmPickupScreen extends StatefulWidget {
  final Place initialLocation;

  const ConfirmPickupScreen({
    super.key,
    required this.initialLocation,
  });

  @override
  State<ConfirmPickupScreen> createState() => _ConfirmPickupScreenState();
}

class _ConfirmPickupScreenState extends State<ConfirmPickupScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();
  late Place _currentPlace;
  bool _isResolving = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _currentPlace = widget.initialLocation;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onMapPositionChanged(LatLng center) {
    // Only update position coordinates immediately to keep marker centered
    setState(() {
      _currentPlace = Place(
        _currentPlace.name,
        _currentPlace.fullAddress,
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
      setState(() {
        _currentPlace = here;
      });
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
              markers: [
                ZiggoMarker(
                  point: _currentPlace.location,
                  icon: Icons.location_on,
                  color: const Color(0xFF0099FF),
                  label: 'Meet your driver here',
                ),
              ],
              circles: [
                ZiggoCircle(
                  center: _currentPlace.location,
                  radius: 80,
                  fillColor: const Color(0xFF0099FF).withOpacity(0.12),
                  strokeColor: const Color(0xFF0099FF).withOpacity(0.3),
                  strokeWidth: 2,
                ),
              ],
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

                // White Info Card
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
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Handle bar
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Confirm your pickup',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE6F0FA),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFF0099FF),
                              size: 24,
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
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currentPlace.fullAddress,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.black54,
                                    fontWeight: FontWeight.w500,
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
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isResolving ? null : _onConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0099FF), // Pickme blue
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          child: const Text(
                            'CONFIRM PICKUP',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 0.5,
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
