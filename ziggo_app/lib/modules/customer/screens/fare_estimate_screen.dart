import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
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

  bool _isDragging = false;
  bool _isResolving = false;
  LatLng? _deviceLocation;
  Timer? _debounceTimer;

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
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted || here == null) return;
    setState(() {
      _currentLocation = here;
      _deviceLocation = here.location;
    });
    _mapController.moveTo(here.location, zoom: 16);
    _startNearbyDriverPolling();
  }

  void _onMapPositionChanged(LatLng center) {
    setState(() {
      _isDragging = true;
      _currentLocation = Place(
        'Fetching address...',
        'Fetching address...',
        center,
      );
    });

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _isDragging = false;
        });
      }
      _resolveLocation(center);
    });
  }

  Future<void> _resolveLocation(LatLng center) async {
    if (!mounted) return;
    setState(() => _isResolving = true);

    final address = await MapsService.instance.reverseGeocode(center);

    if (!mounted) return;

    if (address != null) {
      setState(() {
        _currentLocation = Place(
          address.split(',').first, // Main text
          address,                  // Full address
          center,
        );
      });
    }
    setState(() => _isResolving = false);
  }

  Future<void> _moveToCurrentLocation() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted || here == null) return;
    setState(() {
      _currentLocation = here;
      _deviceLocation = here.location;
    });
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
    bool isAtDeviceLocation = false;
    if (_currentLocation != null && _deviceLocation != null) {
      final dist = const Distance().as(LengthUnit.Meter, _currentLocation!.location, _deviceLocation!);
      isAtDeviceLocation = dist < 20;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: ZiggoMap(
              controller: _mapController,
              center: _currentLocation?.location ?? kColomboCenter,
              zoom: 16,
              showMyLocation: true,
              onPositionChanged: _onMapPositionChanged,
            ),
          ),
          
          // Center Pin (Fixed in center of screen)
          Align(
            alignment: Alignment.center,
            child: FractionalTranslation(
              translation: const Offset(0.0, -0.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, _isDragging ? -15.0 : 0.0, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Tooltip
                    if (isAtDeviceLocation) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF009DE0),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                          ],
                        ),
                        child: Text(
                          widget.isTruckMode ? 'Meet your truck here' : 'Meet your driver here',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      // Small triangle/arrow pointing down
                      CustomPaint(
                        size: const Size(12, 8),
                        painter: _TrianglePainter(color: const Color(0xFF009DE0)),
                      ),
                      const SizedBox(height: 4),
                    ],
                    // The human icon with shadow
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isDragging ? 0.3 : 1.0,
                          child: Container(
                            width: 16,
                            height: 6,
                            margin: const EdgeInsets.only(top: 36),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: const [
                                BoxShadow(color: Colors.black26, blurRadius: 4),
                              ],
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.accessibility_new_rounded,
                          size: 48,
                          color: Colors.black87,
                        ),
                      ],
                    ),
                  ],
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

                    // Pickup & Drop locations (Uber style)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left side: Vertical Timeline (Uber style)
                          Column(
                            children: [
                              // Pickup dot
                              SizedBox(
                                height: 44,
                                child: Center(
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.black87,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 2,
                                height: 10,
                                color: Colors.black12,
                              ),
                              // Stops dots
                              if (_stops.isNotEmpty)
                                for (int i = 0; i < _stops.length; i++) ...[
                                  SizedBox(
                                    height: 44,
                                    child: Center(
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.black54, width: 1.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 2,
                                    height: 10,
                                    color: Colors.black12,
                                  ),
                                ],
                              // Dropoff square
                              SizedBox(
                                height: 44,
                                child: Center(
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          // Right side: Stacked address inputs in light grey boxes
                          Expanded(
                            child: Column(
                              children: [
                                // Pickup Container
                                GestureDetector(
                                  onTap: () => _openSearch(focusDrop: false),
                                  child: Container(
                                    height: 44,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F3F3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _currentLocation?.name ?? 'Your location',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const Icon(
                                          Icons.favorite_border_rounded,
                                          size: 18,
                                          color: Colors.black54,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // Stops Containers
                                if (_stops.isNotEmpty)
                                  for (int i = 0; i < _stops.length; i++) ...[
                                    Container(
                                      height: 44,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF3F3F3),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _stops[i].name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.black87,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                  ],
                                // Drop Container
                                GestureDetector(
                                  onTap: () => _openSearch(focusDrop: true),
                                  child: Container(
                                    height: 44,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F3F3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Where are you going?',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: _openAddStops,
                                          child: const Icon(
                                            Icons.add_rounded,
                                            size: 22,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
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

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
