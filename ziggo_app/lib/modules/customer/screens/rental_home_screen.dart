import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';
import '../booking_provider.dart';
import 'ride_tracking_screen.dart';

/// Rental booking — customer hires a vehicle for an hourly block. No fixed
/// drop-off; the customer roams. Mirrors the FlashHomeScreen layout.
class RentalHomeScreen extends StatefulWidget {
  const RentalHomeScreen({super.key});

  @override
  State<RentalHomeScreen> createState() => _RentalHomeScreenState();
}

class _RentalHomeScreenState extends State<RentalHomeScreen> {
  Place? _pickup;
  String _vehicleType = 'car';
  int _hours = 4;
  String _payment = 'cash';

  final ZiggoMapController _mapController = ZiggoMapController();
  Map<String, dynamic>? _estimate;
  bool _busy = false;
  String? _error;

  static const _vehicles = [
    ('bike', 'Bike', Icons.electric_bike_rounded, 400),
    ('tuk', 'Tuk', Icons.electric_rickshaw_rounded, 600),
    ('car', 'Car', Icons.directions_car_filled_rounded, 1200),
    ('van', 'Van', Icons.airport_shuttle_rounded, 1800),
    ('truck', 'Truck', Icons.local_shipping_rounded, 2500),
  ];

  static const _hourPresets = [2, 4, 6, 8, 12];

  @override
  void initState() {
    super.initState();
    _pickup = kColomboPlaces[0];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _useCurrentLocationForPickup();
    });
  }

  Future<void> _useCurrentLocationForPickup() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted || here == null) return;
    setState(() => _pickup = here);
    await _recalc();
  }

  Future<void> _recalc() async {
    if (_pickup == null) return;
    final res = await context.read<BookingProvider>().estimateFare(
          serviceType: _vehicleType,
          pickup: _pickup!.location,
          drop: _pickup!.location,
          isRental: true,
          rentalHours: _hours,
        );
    if (mounted) setState(() => _estimate = res);
  }

  Future<void> _selectPickup() async {
    final p = await showPlaceSearch(
      context,
      title: 'Pickup location',
      near: _pickup?.location ?? kColomboCenter,
      allowCurrentLocation: true,
    );
    if (p != null) {
      setState(() {
        _pickup = p;
        _error = null;
      });
      _mapController.moveTo(p.location, zoom: 15);
      await _recalc();
    }
  }

  String? _validate() {
    if (_pickup == null) return 'Set a pickup location';
    if (_hours < 1) return 'Pick at least 1 hour';
    if (_estimate == null) return 'Waiting for fare estimate…';
    return null;
  }

  bool get _formReady => _validate() == null && !_busy;

  Future<void> _book() async {
    final err = _validate();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final created = await context.read<BookingProvider>().createBooking(
          serviceType: _vehicleType,
          pickup: _pickup!.location,
          pickupAddress: _pickup!.fullAddress,
          drop: _pickup!.location,
          dropAddress: _pickup!.fullAddress,
          paymentMethod: _payment,
          isRental: true,
          rentalHours: _hours,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (created == null) {
      setState(() => _error =
          context.read<BookingProvider>().lastError ?? 'Could not book');
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
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Map background
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.40,
            child: ZiggoMap(
              controller: _mapController,
              center: _pickup?.location ?? kColomboCenter,
              zoom: 14,
              showMyLocation: true,
              markers: [
                if (_pickup != null)
                  pinMarker(
                    point: _pickup!.location,
                    icon: Icons.directions_car_filled_rounded,
                    color: AppColors.primary,
                  ),
              ],
            ),
          ),

          // Gradient overlay for status bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.4), Colors.transparent],
                ),
              ),
            ),
          ),

          // Scrollable content
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.only(
                  top: MediaQuery.of(context).size.height * 0.33),
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(32)),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 30,
                        offset: Offset(0, -10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.divider.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'ZIGGO RENTALS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Hire a vehicle',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Driver waits with you. Pay by the hour.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      _buildPickupCard(),

                      const SizedBox(height: 24),
                      _sectionHeader('VEHICLE TYPE'),
                      const SizedBox(height: 12),
                      _buildVehiclePicker(),

                      const SizedBox(height: 24),
                      _sectionHeader('HOW LONG?'),
                      const SizedBox(height: 12),
                      _buildHoursPicker(),

                      const SizedBox(height: 24),
                      _sectionHeader('PAYMENT'),
                      const SizedBox(height: 12),
                      _buildPaymentPicker(),

                      if (_error != null) ...[
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.error.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: AppColors.error, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Back button — placed AFTER the ListView so it renders on top of
          // the Positioned.fill scroll area and actually receives taps.
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppStyles.shadowMd,
                ),
                child: const Icon(Icons.arrow_back_rounded,
                    color: AppColors.textPrimary),
              ),
            ),
          ),

          // Bottom action bar
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 30,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'TOTAL FARE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textTertiary,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          _estimate == null
                              ? '--'
                              : 'Rs.${(_estimate!['final_amount'] as num).toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: AppColors.textPrimary,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          '${_hours}h · Rs.${_hourlyRate()}/hr',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _formReady ? _book : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFCBD5E1),
                          disabledForegroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          elevation: 0,
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.key_rounded,
                                      color: AppColors.primary, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'BOOK NOW',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      letterSpacing: 0.5,
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
          ),
        ],
      ),
    );
  }

  int _hourlyRate() {
    final found = _vehicles.firstWhere(
      (v) => v.$1 == _vehicleType,
      orElse: () => _vehicles[2],
    );
    return found.$4;
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }

  Widget _buildPickupCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: AppStyles.shadowSm,
      ),
      child: InkWell(
        onTap: _selectPickup,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.my_location_rounded,
                size: 16,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PICKUP',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  Text(
                    _pickup?.fullAddress ?? 'Set pickup point',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_rounded,
                size: 16, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildVehiclePicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: _vehicles.map((v) {
          final sel = _vehicleType == v.$1;
          return GestureDetector(
            onTap: () {
              setState(() => _vehicleType = v.$1);
              _recalc();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: sel ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color:
                        sel ? Colors.black : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Icon(v.$3,
                      size: 22,
                      color: sel ? AppColors.primary : AppColors.textPrimary),
                  const SizedBox(height: 6),
                  Text(
                    v.$2,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: sel ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rs.${v.$4}/hr',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: sel ? Colors.white70 : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHoursPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            children: _hourPresets.map((h) {
              final sel = _hours == h;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() => _hours = h);
                    _recalc();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.only(
                      right: h == _hourPresets.last ? 0 : 8,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: sel
                            ? AppColors.primary
                            : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${h}h',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: sel ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Fine-grained slider for non-preset hour counts
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 18, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Slider(
                  value: _hours.toDouble(),
                  min: 1,
                  max: 24,
                  divisions: 23,
                  label: '${_hours}h',
                  onChanged: (v) {
                    setState(() => _hours = v.round());
                  },
                  onChangeEnd: (_) => _recalc(),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_hours}h',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _payTile('cash', 'Cash', Icons.payments_rounded),
          const SizedBox(width: 12),
          _payTile('wallet', 'Wallet', Icons.account_balance_wallet_rounded),
        ],
      ),
    );
  }

  Widget _payTile(String val, String label, IconData icon) {
    final sel = _payment == val;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _payment = val),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: sel ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: sel ? Colors.black : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 20,
                  color: sel ? AppColors.primary : AppColors.textPrimary),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: sel ? Colors.white : AppColors.textPrimary,
                ),
              ),
              if (sel) ...[
                const Spacer(),
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.primary, size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
