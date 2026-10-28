import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/app_colors.dart';
import '../../../core/map/location_permission_helper.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';

/// Full-screen interactive map location picker.
/// Allows the user to pan/zoom the map with a center pin, reverse-geocodes the
/// location, and pops the chosen [Place] upon confirmation.
class SetLocationMapScreen extends StatefulWidget {
  final Place? initialLocation;
  final String title;
  final String confirmButtonText;
  final String badgeText;

  const SetLocationMapScreen({
    super.key,
    this.initialLocation,
    this.title = 'Set delivery location',
    this.confirmButtonText = 'CONFIRM LOCATION',
    this.badgeText = 'Delivery',
  });

  @override
  State<SetLocationMapScreen> createState() => _SetLocationMapScreenState();
}

class _SetLocationMapScreenState extends State<SetLocationMapScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();
  late Place _currentPlace;
  bool _isResolving = false;
  bool _isDragging = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _currentPlace = widget.initialLocation ?? kColomboPlaces[0];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    if (widget.initialLocation != null) {
      _mapController.moveTo(widget.initialLocation!.location, zoom: 16);
      return;
    }

    final here = await MapsService.instance.currentLocationAsPlace();
    if (here != null && mounted) {
      setState(() => _currentPlace = here);
      _mapController.moveTo(here.location, zoom: 16);
    } else if (mounted) {
      _mapController.moveTo(_currentPlace.location, zoom: 16);
    }
  }

  void _onMapPositionChanged(LatLng center) {
    final latDiff = (center.latitude - _currentPlace.location.latitude).abs();
    final lngDiff = (center.longitude - _currentPlace.location.longitude).abs();
    if (latDiff < 0.00001 && lngDiff < 0.00001) {
      return;
    }

    setState(() {
      _isDragging = true;
      _currentPlace = Place(
        _currentPlace.name,
        _currentPlace.fullAddress,
        center,
      );
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _resolveLocation(center);
    });
  }

  Future<void> _resolveLocation(LatLng center) async {
    if (!mounted) return;
    setState(() {
      _isDragging = false;
      _isResolving = true;
    });

    final address = await MapsService.instance.reverseGeocode(center);
    if (!mounted) return;

    if (address != null && address.trim().isNotEmpty) {
      final name = address.split(',').first.trim();
      setState(() {
        _currentPlace = Place(
          name.isNotEmpty ? name : 'Selected Location',
          address,
          center,
        );
      });
    } else {
      setState(() {
        _currentPlace = Place(
          'Selected Location',
          '${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}',
          center,
        );
      });
    }

    setState(() => _isResolving = false);
  }

  Future<void> _moveToCurrentLocation() async {
    final granted = await LocationPermissionHelper.ensureLocationAccess(
      context: context,
      customMessage:
          'Location access is disabled. Open app settings to center on your current position.',
    );
    if (!granted) return;

    final here = await MapsService.instance.currentLocationAsPlace();
    if (here != null && mounted) {
      _mapController.moveTo(here.location, zoom: 16);
      setState(() {
        _currentPlace = here;
      });
    }
  }

  Future<void> _searchAndMove() async {
    final p = await showPlaceSearch(context, title: 'Search location');
    if (p != null && mounted) {
      setState(() => _currentPlace = p);
      _mapController.moveTo(p.location, zoom: 16);
    }
  }

  void _onConfirm() {
    Navigator.pop(context, _currentPlace);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Interactive Map
          Positioned.fill(
            child: ZiggoMap(
              controller: _mapController,
              center: _currentPlace.location,
              zoom: 16,
              showMyLocation: true,
              onPositionChanged: _onMapPositionChanged,
            ),
          ),

          // Center Pin with drag-lift animation
          Center(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: _isDragging ? 52.0 : 40.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 6,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.badgeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Container(
                    width: 2.5,
                    height: 20,
                    color: AppColors.textPrimary,
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Top Header (Back button + Search bar)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 16,
            right: 16,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _searchAndMove,
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.12),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search_rounded,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _currentPlace.name.isNotEmpty
                                  ? _currentPlace.name
                                  : 'Search area...',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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

          // Bottom Controls (Locate-me button + confirmation sheet)
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Floating Locate-Me Button
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, bottom: 16.0),
                  child: GestureDetector(
                    onTap: _moveToCurrentLocation,
                    child: Container(
                      width: 48,
                      height: 48,
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
                      child: const Icon(
                        Icons.my_location_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),

                // Bottom Details Sheet
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(24)),
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
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  color: AppColors.primary,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isResolving
                                          ? 'Locating...'
                                          : _currentPlace.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _isResolving
                                          ? 'Fetching address details...'
                                          : _currentPlace.fullAddress,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.textSecondary,
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
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isResolving ? null : _onConfirm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(26),
                                ),
                              ),
                              child: _isResolving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Text(
                                      widget.confirmButtonText,
                                      style: const TextStyle(
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

