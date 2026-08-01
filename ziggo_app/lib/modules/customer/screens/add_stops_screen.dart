import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/app_colors.dart';
import '../../../core/map/places.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/ziggo_map.dart';
import '../../../core/map/maps_service.dart';
import 'customer_shell.dart';

class AddStopsScreen extends StatefulWidget {
  final Place pickup;
  final Place? initialDrop;
  final List<Place> initialStops;

  const AddStopsScreen({
    super.key,
    required this.pickup,
    this.initialDrop,
    this.initialStops = const [],
  });

  @override
  State<AddStopsScreen> createState() => _AddStopsScreenState();
}

class _AddStopsScreenState extends State<AddStopsScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();
  
  // Up to 3 user-selected destinations. The last non-null is DROP, the rest are STOPS.
  late List<Place?> _destinations;
  
  List<LatLng> _routePoints = const [];
  bool _calculatingRoute = false;

  @override
  void initState() {
    super.initState();
    _destinations = [];
    for (var s in widget.initialStops) {
      _destinations.add(s);
    }
    if (widget.initialDrop != null) {
      _destinations.add(widget.initialDrop);
    }
    // Pad with nulls to always have at least 1 empty slot (up to 3 total slots)
    while (_destinations.length < 3) {
      _destinations.add(null);
    }
    if (_destinations.length > 3) {
      _destinations = _destinations.sublist(0, 3);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recalculateRoute();
    });
  }

  List<Place> get _validDestinations => _destinations.whereType<Place>().toList();

  Future<void> _recalculateRoute() async {
    final valid = _validDestinations;
    if (valid.isEmpty) {
      setState(() => _routePoints = []);
      _mapController.moveTo(widget.pickup.location, zoom: 15);
      return;
    }

    setState(() => _calculatingRoute = true);

    try {
      final pointsToVisit = [widget.pickup.location, ...valid.map((p) => p.location)];
      
      _mapController.fitBounds(pointsToVisit, padding: 60);

      // We need to fetch route across all points.
      // Since our MapsService.directions currently takes (start, end), we might need to stitch them.
      List<LatLng> fullRoute = [];
      for (int i = 0; i < pointsToVisit.length - 1; i++) {
        final dir = await MapsService.instance.directions(pointsToVisit[i], pointsToVisit[i+1]);
        if (dir != null && dir.points.isNotEmpty) {
          fullRoute.addAll(dir.points);
        } else {
          fullRoute.add(pointsToVisit[i]);
          fullRoute.add(pointsToVisit[i+1]);
        }
      }

      if (mounted) {
        setState(() {
          _routePoints = fullRoute;
        });
      }
    } catch (e) {
      debugPrint("Error calculating route: $e");
    } finally {
      if (mounted) {
        setState(() => _calculatingRoute = false);
      }
    }
  }

  Future<void> _selectPlace(int index) async {
    final p = await showPlaceSearch(context, title: 'Stop ${index + 1}');
    if (p != null && mounted) {
      setState(() {
        _destinations[index] = p;
        // Shift nulls to the end
        final valid = _destinations.where((e) => e != null).toList();
        _destinations = List.generate(3, (i) => i < valid.length ? valid[i] : null);
      });
      _recalculateRoute();
    }
  }

  void _removePlace(int index) {
    setState(() {
      _destinations[index] = null;
      // Shift nulls to the end
      final valid = _destinations.where((e) => e != null).toList();
      _destinations = List.generate(3, (i) => i < valid.length ? valid[i] : null);
    });
    _recalculateRoute();
  }

  void _onDone() {
    final valid = _validDestinations;
    if (valid.isEmpty) {
      Navigator.pop(context, null);
      return;
    }
    
    final drop = valid.last;
    final stops = valid.length > 1 ? valid.sublist(0, valid.length - 1) : <Place>[];
    
    Navigator.pop(context, {
      'stops': stops,
      'drop': drop,
    });
  }

  @override
  Widget build(BuildContext context) {
    final validCount = _validDestinations.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add Stops',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          // Locations List
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connecting line
                Column(
                  children: [
                    const SizedBox(height: 14),
                    const Text('PICKUP', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    for (int i = 0; i < 3; i++) ...[
                      if (i < 3) Container(height: 24, width: 1.5, color: Colors.grey.shade300),
                      const SizedBox(height: 4),
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: _destinations[i] != null ? AppColors.warning : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.warning, width: 2),
                          boxShadow: _destinations[i] != null ? [
                            BoxShadow(color: AppColors.warning.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))
                          ] : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            color: _destinations[i] != null ? Colors.white : AppColors.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ],
                ),
                const SizedBox(width: 16),
                // Text Fields
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      // Pickup
                      Text(
                        widget.pickup.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Colors.black87),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 26),
                      // Destinations
                      for (int i = 0; i < 3; i++) ...[
                        if (_destinations[i] != null) ...[
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _selectPlace(i),
                                  child: Text(
                                    _destinations[i]!.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black87),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _removePlace(i),
                                child: const Icon(Icons.close_rounded, color: Colors.black87, size: 20),
                              ),
                            ],
                          ),
                        ] else if (i == validCount) ...[
                          GestureDetector(
                            onTap: () => _selectPlace(i),
                            child: Text(
                              'Add stop ${i + 1}',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.grey.shade400),
                            ),
                          ),
                        ] else ...[
                          Text(
                            'Add stop ${i + 1}',
                            style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: Colors.grey.shade300),
                          ),
                        ],
                        if (i < 2) ...[
                          const SizedBox(height: 12),
                          Divider(height: 1, color: Colors.grey.shade200),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Map
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: ZiggoMap(
                    controller: _mapController,
                    center: widget.pickup.location,
                    zoom: 15,
                    showMyLocation: false,
                    onMapCreated: () {
                      final valid = _validDestinations;
                      if (valid.isNotEmpty) {
                        final pointsToVisit = [widget.pickup.location, ...valid.map((p) => p.location)];
                        _mapController.fitBounds(pointsToVisit, padding: 60);
                      }
                    },
                    markers: [
                      pinMarker(
                        point: widget.pickup.location,
                        icon: Icons.my_location_rounded,
                        color: AppColors.info,
                        size: 30,
                        label: 'Pickup | ${widget.pickup.name}',
                      ),
                      for (int i = 0; i < _validDestinations.length; i++)
                        pinMarker(
                          point: _validDestinations[i].location,
                          icon: Icons.location_on_rounded,
                          color: AppColors.warning,
                          size: 30,
                          label: '${i + 1}',
                        ),
                    ],
                    polylines: [
                      if (_routePoints.isNotEmpty)
                        ZiggoPolyline(
                          points: _routePoints,
                          strokeWidth: 4,
                          color: Colors.black,
                        ),
                    ],
                  ),
                ),
                if (_calculatingRoute)
                  const Positioned(
                    top: 16,
                    right: 16,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 16,
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Bottom info and button
          Container(
            color: Colors.white,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 18, color: Colors.indigo.shade400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can spend up to 2 min at your stop.* If exceeded, standard waiting charges will be applied',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.indigo.shade400,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: validCount > 0 ? _onDone : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: validCount > 0 ? AppColors.success : Colors.grey.shade300,
                      foregroundColor: validCount > 0 ? Colors.white : Colors.grey.shade500,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
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
