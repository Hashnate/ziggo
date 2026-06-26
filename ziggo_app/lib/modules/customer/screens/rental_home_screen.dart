import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/places.dart';
import '../../../core/map/place_search_sheet.dart';
import '../booking_provider.dart';
import 'ride_tracking_screen.dart';
import 'rental_pickup_map_screen.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'rental_confirm_booking_screen.dart';

class RentalHomeScreen extends StatefulWidget {
  const RentalHomeScreen({super.key});

  @override
  State<RentalHomeScreen> createState() => _RentalHomeScreenState();
}

class _RentalHomeScreenState extends State<RentalHomeScreen> {
  Place? _pickup;
  Place? _drop;
  bool _isNow = true;
  String _vehicleType = 'car';
  int _hours = 1;
  double _distance = 5;
  DateTime? _scheduledDate;
  TimeOfDay? _scheduledTime;
  ({String name, String phone})? _friend;
  
  bool _isCalculated = false;
  int? _calculatedMinutes;
  double? _calculatedDistanceKm;

  bool _busy = false;

  static const _vehicles = [
    ('mini', 'Mini', Icons.directions_car_rounded, 3, 1100),
    ('car', 'Car', Icons.directions_car_filled_rounded, 4, 1300),
    ('minivan', 'Minivan', Icons.airport_shuttle_rounded, 5, 1200),
    ('van', 'Van', Icons.airport_shuttle_outlined, 10, 2500),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _useCurrentLocationForPickup();
    });
  }

  Future<void> _useCurrentLocationForPickup() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted || here == null) return;
    setState(() => _pickup = here);
  }

  Future<void> _selectPickup() async {
    final startLoc = _pickup ?? await MapsService.instance.currentLocationAsPlace() ?? kColomboPlaces[0];
    
    final p = await showPlaceSearch(
      context,
      title: 'Choose Pickup Location',
      near: startLoc.location,
      allowCurrentLocation: true,
      allowSetOnMap: true,
    );

    if (p == null || !mounted) return;

    if (p.name == '__SET_ON_MAP__') {
      final confirmedPlace = await Navigator.push<Place>(
        context,
        MaterialPageRoute(
          builder: (_) => RentalPickupMapScreen(initialLocation: startLoc),
        ),
      );
      if (confirmedPlace != null && mounted) {
        setState(() => _pickup = confirmedPlace);
      }
    } else {
      setState(() => _pickup = p);
    }
  }

  void _onNext() async {
    if (_pickup == null) {
      await _selectPickup();
      if (_pickup == null) return;
    }
    
    final confirmedPlace = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => RentalPickupMapScreen(initialLocation: _pickup!),
      ),
    );

    if (confirmedPlace != null) {
      if (!mounted) return;
      setState(() => _pickup = confirmedPlace);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RentalConfirmBookingScreen(
            pickup: _pickup!,
            drop: _drop,
            vehicleType: _vehicleType,
            hours: _hours,
            distance: _distance,
            isNow: _isNow,
            scheduledDate: _scheduledDate,
            scheduledTime: _scheduledTime,
          ),
        ),
      );
    }
  }

  Future<void> _calculatePackage() async {
    if (_pickup == null) {
      await _selectPickup();
      if (_pickup == null) return;
    }

    final startLoc = _pickup!;
    final p = await showPlaceSearch(
      context,
      title: 'Choose Drop Location',
      near: startLoc.location,
      allowCurrentLocation: false,
      allowSetOnMap: true,
    );

    if (p == null || !mounted) return;

    Place dropPlace = p;
    if (p.name == '__SET_ON_MAP__') {
      final confirmedPlace = await Navigator.push<Place>(
        context,
        MaterialPageRoute(
          builder: (_) => RentalPickupMapScreen(initialLocation: startLoc),
        ),
      );
      if (confirmedPlace != null) {
        dropPlace = confirmedPlace;
      } else {
        return;
      }
    }

    setState(() => _busy = true);
    final result = await MapsService.instance.directions(startLoc.location, dropPlace.location);
    if (!mounted) return;
    setState(() => _busy = false);

    if (result != null) {
      setState(() {
        _drop = dropPlace;
        _calculatedDistanceKm = result.distanceKm;
        _calculatedMinutes = result.durationMin;
        
        int suggestedHrs = (result.durationMin / 60).ceil();
        if (suggestedHrs < 1) suggestedHrs = 1;
        if (suggestedHrs > 14) suggestedHrs = 14;
        
        double suggestedDist = (result.distanceKm / 5).ceil() * 5.0;
        if (suggestedDist < 5) suggestedDist = 5;
        if (suggestedDist > 70) suggestedDist = 70;

        _hours = suggestedHrs;
        _distance = suggestedDist;
        _isCalculated = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not calculate route. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Hourly Packages',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
            child: GestureDetector(
              onTap: () => _showBookForFriendSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 18),
                    const SizedBox(width: 6),
                    Text(_friend?.name ?? 'For Me', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _buildTimeToggle(),
                const SizedBox(height: 20),
                _buildPickupField(),
                const SizedBox(height: 24),
                const Text('Choose Vehicle', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _buildVehiclePicker(),
                const SizedBox(height: 24),
                const Text('Duration & Distance', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                _buildDurationDistanceBox(),
              ],
            ),
          ),
          
          // Fixed Bottom Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ElevatedButton(
                  onPressed: _busy ? null : _onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _busy 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Next', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _isNow = true;
                _scheduledDate = null;
                _scheduledTime = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isNow ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: _isNow ? [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                  ] : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: _isNow ? AppColors.primary : AppColors.textTertiary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text('Book Now', style: TextStyle(fontWeight: FontWeight.w700, color: _isNow ? AppColors.primary : AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () async {
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
                if (t != null && mounted) {
                  setState(() {
                    _isNow = false;
                    _scheduledDate = d;
                    _scheduledTime = t;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_isNow ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: !_isNow ? [
                    BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
                  ] : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.edit_calendar_rounded,
                      color: !_isNow ? AppColors.primary : AppColors.textTertiary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text('Schedule Later', style: TextStyle(fontWeight: FontWeight.w700, color: !_isNow ? AppColors.primary : AppColors.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupField() {
    return GestureDetector(
      onTap: _selectPickup,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.cardBorder),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
          ]
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.my_location_rounded, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pickup Location', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    _pickup?.name ?? 'Set your location',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textTertiary, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildVehiclePicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: _vehicles.map((v) {
          final sel = _vehicleType == v.$1;
          return GestureDetector(
            onTap: () => setState(() => _vehicleType = v.$1),
            child: Container(
              width: 100,
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: sel ? AppColors.primarySoft : AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? AppColors.primary : AppColors.cardBorder,
                  width: sel ? 2 : 1,
                ),
                boxShadow: sel ? [] : [
                  BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))
                ],
              ),
              child: Column(
                children: [
                  Icon(v.$3, size: 36, color: sel ? AppColors.primary : AppColors.textSecondary),
                  const SizedBox(height: 12),
                  Text(v.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: sel ? AppColors.primary : AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(
                    'Rs.${v.$5.toInt() * _hours}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? AppColors.primary.withOpacity(0.8) : AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDurationDistanceBox() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ]
      ),
      child: Column(
        children: [
          // Hours Selector
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Duration', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('${_hours} Hours', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                  ],
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (_hours > 1) {
                          setState(() {
                            _hours--;
                            if (_distance > 5) _distance -= 5;
                          });
                        }
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted, 
                          borderRadius: BorderRadius.circular(12)
                        ),
                        child: const Icon(Icons.remove_rounded, color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        if (_hours < 14) {
                          setState(() {
                            _hours++;
                            if (_distance < 70) _distance += 5;
                          });
                        }
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft, 
                          borderRadius: BorderRadius.circular(12)
                        ),
                        child: const Icon(Icons.add_rounded, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const Divider(height: 1, color: AppColors.divider),
          
          // Slider 
          Padding(
            padding: const EdgeInsets.only(top: 20, left: 16, right: 16, bottom: 8),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: AppColors.surfaceMuted,
                    thumbColor: AppColors.primary,
                    trackHeight: 6,
                    overlayColor: AppColors.primary.withOpacity(0.1),
                    valueIndicatorColor: AppColors.primary,
                  ),
                  child: Slider(
                    value: _distance,
                    min: 5,
                    max: 70,
                    divisions: 13,
                    onChanged: (v) => setState(() => _distance = v),
                  ),
                ),
                Positioned(
                  top: -12,
                  left: 20 + ((_distance - 5) / 65) * (MediaQuery.of(context).size.width - 100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${_distance.toInt()} km', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 20.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('5 km', style: TextStyle(color: AppColors.textTertiary, fontSize: 12, fontWeight: FontWeight.w600)),
                Text('70 km', style: TextStyle(color: AppColors.textTertiary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),

          // Bottom Banner
          if (_isCalculated)
            _buildCalculatedSummary()
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Not sure about hours?", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
                  GestureDetector(
                    onTap: _calculatePackage,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text("Help me calculate", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCalculatedSummary() {
    return Column(
      children: [
        const Divider(height: 1, color: AppColors.divider),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: const BoxDecoration(
            color: AppColors.primarySoft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Suggested package based on calculated time and distance", style: TextStyle(fontSize: 12, color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text('${_calculatedMinutes} mins', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: [
                        const Icon(Icons.route_outlined, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text('${_calculatedDistanceKm?.toStringAsFixed(1)} km', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            color: Colors.transparent,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLocationRow(Icons.my_location_rounded, AppColors.primary, 'Pickup', _pickup?.fullAddress ?? _pickup?.name ?? ''),
              const SizedBox(height: 16),
              _buildLocationRow(Icons.location_on_rounded, AppColors.error, 'Drop', _drop?.fullAddress ?? _drop?.name ?? ''),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _calculatePackage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const Text('Edit Drop', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _isCalculated = false;
                          _drop = null;
                          _calculatedMinutes = null;
                          _calculatedDistanceKm = null;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: const Text('Clear', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String title, String address) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(address, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  void _showBookForFriendSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Who are you booking for?',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    ListTile(
                      onTap: () async {
                        if (await FlutterContacts.permissions.request(PermissionType.read) == PermissionStatus.granted) {
                          final contact = await FlutterContacts.native.showPicker(properties: {ContactProperty.phone});
                          if (contact != null && contact.phones.isNotEmpty) {
                            setState(() => _friend = (name: contact.displayName ?? 'Unknown', phone: contact.phones.first.number));
                          }
                        }
                        if (context.mounted) Navigator.pop(ctx);
                      },
                      leading: const Icon(Icons.contact_phone_outlined, color: AppColors.textPrimary),
                      title: const Text('Phone book', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      onTap: () {
                        setState(() => _friend = null);
                        Navigator.pop(ctx);
                      },
                      leading: const Icon(Icons.person_outline_rounded, color: AppColors.textPrimary),
                      title: const Text('Set as you', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      trailing: _friend == null ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      onTap: () {
                        setState(() => _friend = (name: 'John Doe', phone: '+94771234567'));
                        Navigator.pop(ctx);
                      },
                      leading: const Icon(Icons.history_rounded, color: AppColors.textPrimary),
                      title: const Text('Recent contacts (1)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
