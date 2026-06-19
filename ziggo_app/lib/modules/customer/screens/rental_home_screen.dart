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

class RentalHomeScreen extends StatefulWidget {
  const RentalHomeScreen({super.key});

  @override
  State<RentalHomeScreen> createState() => _RentalHomeScreenState();
}

class _RentalHomeScreenState extends State<RentalHomeScreen> {
  Place? _pickup;
  bool _isNow = true;
  String _vehicleType = 'car';
  int _hours = 1;
  double _distance = 5;
  ({String name, String phone})? _friend;

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
    _book();
  }

  Future<void> _book() async {
    setState(() => _busy = true);
    final created = await context.read<BookingProvider>().createBooking(
          serviceType: _vehicleType,
          pickup: _pickup!.location,
          pickupAddress: _pickup!.fullAddress,
          drop: _pickup!.location,
          dropAddress: _pickup!.fullAddress,
          paymentMethod: 'cash',
          isRental: true,
          rentalHours: _hours,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    
    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<BookingProvider>().lastError ?? 'Could not book'),
          backgroundColor: AppColors.error,
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Hourly Packages',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 10, bottom: 10),
            child: GestureDetector(
              onTap: () => _showBookForFriendSheet(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, color: Colors.black87, size: 18),
                    const SizedBox(width: 6),
                    Text(_friend?.name ?? 'For Me', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600)),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                const Text('Pickup date & time', style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                _buildTimeToggle(),
                const SizedBox(height: 16),
                _buildPickupField(),
                const SizedBox(height: 24),
                _buildVehiclePicker(),
                const SizedBox(height: 24),
                _buildDurationDistanceBox(),
              ],
            ),
          ),
          
          // Fixed Bottom Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _busy ? null : _onNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  ),
                  child: _busy 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('BOOK NOW', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
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
        color: const Color(0xFFE6F0FA), // light blue
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2943A3).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isNow = true),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isNow ? const Color(0xFFE6F0FA) : Colors.white,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _isNow ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: _isNow ? const Color(0xFF2943A3) : Colors.black38,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text('Now', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
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
                  setState(() => _isNow = false);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_isNow ? const Color(0xFFE6F0FA) : Colors.white,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                  border: const Border(left: BorderSide(color: Colors.black12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      !_isNow ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: !_isNow ? const Color(0xFF2943A3) : Colors.black38,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text('Schedule', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(24), // Pill shape
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Color(0xFFE6F0FA),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.my_location_rounded, color: Color(0xFF2943A3), size: 16),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PICKUP', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w700, fontSize: 10)),
                Text(
                  _pickup?.name ?? 'Your Location',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.edit_rounded, color: Colors.black38, size: 18),
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
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: sel ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sel ? Colors.black : Colors.black12,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Icon(v.$3, size: 36, color: sel ? Colors.white : const Color(0xFF334A52)),
                  const SizedBox(height: 8),
                  Text(v.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: sel ? Colors.white : Colors.black)),
                  const SizedBox(height: 4),
                  Text(
                    'Rs.${v.$5.toInt() * _hours}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: sel ? Colors.white70 : Colors.black45),
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
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // Hours Selector
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.remove, color: Colors.black26),
                  ),
                ),
                Text(
                  '${_hours} hr',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
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
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: const Color(0xFF2943A3), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          
          // Slider 
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: const Color(0xFF2943A3),
                    inactiveTrackColor: Colors.black12,
                    thumbColor: const Color(0xFF2943A3),
                    trackHeight: 4,
                    overlayColor: const Color(0xFF2943A3).withOpacity(0.1),
                    valueIndicatorColor: const Color(0xFF2943A3),
                  ),
                  child: Slider(
                    value: _distance,
                    min: 5,
                    max: 70,
                    divisions: 13,
                    onChanged: (v) => setState(() => _distance = v),
                  ),
                ),
                // Custom 5Km Badge positioned manually for visual approximation
                Positioned(
                  top: -15,
                  left: 20 + ((_distance - 5) / 65) * (MediaQuery.of(context).size.width - 100),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2943A3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${_distance.toInt()} km', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('5', style: TextStyle(color: Colors.black54, fontSize: 10)),
                Text('70', style: TextStyle(color: Colors.black54, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFE6F0FA), // Light blue banner
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Don't know hours/distance?", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
                GestureDetector(
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Calculate feature coming soon')),
                    );
                  },
                  child: const Text("Calculate", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black87, decoration: TextDecoration.underline)),
                ),
              ],
            ),
          ),
        ],
      ),
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
