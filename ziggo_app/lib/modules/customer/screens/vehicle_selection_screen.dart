import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';
import '../../../core/network/api_client.dart';
import '../../customer/booking_provider.dart';
import '../../customer/payment_methods_provider.dart';
import '../../customer/promos_provider.dart';
import '../../customer/wallet_provider.dart';
import 'payment_selection_screen.dart';
import 'promotions_selection_screen.dart';
import 'ride_tracking_screen.dart';
import 'customer_shell.dart';
import 'confirm_pickup_screen.dart';

class VehicleSelectionScreen extends StatefulWidget {
  final Place pickup;
  final Place drop;
  final String tripType;
  final ({String name, String phone})? friend;
  final bool isTruckMode;

  const VehicleSelectionScreen({
    super.key,
    required this.pickup,
    required this.drop,
    this.tripType = 'one_way',
    this.friend,
    this.isTruckMode = false,
  });

  @override
  State<VehicleSelectionScreen> createState() => _VehicleSelectionScreenState();
}

class _VehicleSelectionScreenState extends State<VehicleSelectionScreen> {
  final ZiggoMapController _mapController = ZiggoMapController();
  
  String? _serviceType;
  String _payment = 'cash';
  String _promo = '';
  final _promoController = TextEditingController();
  String _driverNote = '';
  String? _secondaryPhone;

  final Map<String, Map<String, dynamic>> _estimates = {};
  bool _loadingEstimates = false;
  bool _usePoints = false;
  bool _truckTermsAccepted = false;
  List<LatLng> _routePoints = const [];

  List<Map<String, dynamic>> _nearbyDrivers = const [];
  Timer? _nearbyTimer;
  List<String> _serviceTypes = [];
  Map<String, Map<String, dynamic>> _categoryData = {};

  Future<void> _fetchActiveServices() async {
    try {
      final resp = await ApiClient.instance.dio.get('/public/categories');
      if (resp.data is List) {
        final list = List<Map<String, dynamic>>.from(resp.data as List);
        setState(() {
          _serviceTypes = list.map((item) => item['service_type'] as String).toList();
          _categoryData = {
            for (var item in list) item['service_type'] as String: item
          };
        });
      }
    } catch (e) {
      debugPrint("Error fetching active services: $e");
      setState(() {
        _serviceTypes = ['tuk', 'bike', 'car', 'mini', 'van', 'truck'];
        _categoryData = {};
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _secondaryPhone = widget.friend?.phone;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PromosProvider>().refresh();
      context.read<PaymentMethodsProvider>().fetchCards();
      context.read<PaymentMethodsProvider>().fetchCorporateProfile();
      _usePoints = false;
      _recalculate();
      _startNearbyDriverPolling();
    });
  }

  @override
  void dispose() {
    _nearbyTimer?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  Future<void> _animateToUserLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await _mapController.moveTo(LatLng(pos.latitude, pos.longitude), zoom: 15);
    } catch (e) {
      debugPrint("Error getting current location: $e");
    }
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
    final pickup = widget.pickup.location;
    try {
      final resp = await ApiClient.instance.dio.get(
        '/driver/nearby',
        queryParameters: {
          'lat': pickup.latitude,
          'lng': pickup.longitude,
          'radius_km': 5,
        },
      );
      if (!mounted) return;
      setState(() {
        _nearbyDrivers = List<Map<String, dynamic>>.from(resp.data as List);
      });
    } catch (_) {
      // Silent error
    }
  }

  IconData _vehicleIcon(String? type) {
    switch (type) {
      case 'bike': return Icons.motorcycle_rounded;
      case 'tuk': return Icons.electric_rickshaw_rounded;
      case 'car': return Icons.directions_car_filled_rounded;
      case 'van': return Icons.airport_shuttle_rounded;
      case 'mini': return Icons.directions_car_filled_rounded;
      case 'truck': return Icons.local_shipping_rounded;
      default: return Icons.local_taxi_rounded;
    }
  }

  Color _vehicleColor(String? type) {
    switch (type) {
      case 'bike': return AppColors.bike;
      case 'tuk': return AppColors.warning;
      case 'car': return AppColors.primary;
      case 'van': return AppColors.market;
      case 'mini': return AppColors.primary;
      case 'truck': return AppColors.truck;
      default: return AppColors.primary;
    }
  }

  String _vehicleAsset(String? type) {
    switch (type) {
      case 'bike': return 'assets/icons/top_bike.png';
      case 'tuk': return 'assets/icons/top_tuk.png';
      case 'truck': return 'assets/icons/top_truck.png';
      case 'mini': return 'assets/icons/top_car.png';
      case 'van':
      case 'car':
      default: return 'assets/icons/top_car.png';
    }
  }

  Future<void> _recalculate() async {
    setState(() {
      _loadingEstimates = true;
      _routePoints = const [];
    });
    
    final booking = context.read<BookingProvider>();
    _estimates.clear();
    
    if (!widget.isTruckMode && _serviceTypes.isEmpty) {
      await _fetchActiveServices();
    }
    
    final servicesToFetch = widget.isTruckMode ? ['truck'] : _serviceTypes;

    for (final st in servicesToFetch) {
      final res = await booking.estimateFare(
        serviceType: st,
        pickup: widget.pickup.location,
        drop: widget.drop.location,
        promoCode: _promo.isEmpty ? null : _promo,
        tripType: widget.tripType,
        stops: [],
      );
      if (res != null) {
        if (widget.isTruckMode && st == 'truck') {
          // Mock truck variations based on the base truck fare
          final baseAmt = res['final_amount'] as num;
          _estimates['light'] = {...res, 'final_amount': baseAmt * 1.0, 'capacity': 1, 'duration_min': res['duration_min']};
          _estimates['light_open'] = {...res, 'final_amount': baseAmt * 1.0, 'capacity': 1, 'duration_min': res['duration_min']};
          _estimates['mover'] = {...res, 'final_amount': baseAmt * 2.5, 'capacity': 1, 'duration_min': res['duration_min']};
          _estimates['mover_open'] = {...res, 'final_amount': baseAmt * 2.5, 'capacity': 1, 'duration_min': res['duration_min']};
          
          if (_serviceType == null) {
            _serviceType = 'light';
          }
        } else {
          _estimates[st] = res;
          if (_serviceType == null) {
            _serviceType = st;
          }
        }
      }
    }
    
    if (!mounted) return;
    setState(() => _loadingEstimates = false);
    
    _mapController.fitBounds(
      [widget.pickup.location, widget.drop.location],
      padding: 80,
    );
 
    final dir = await MapsService.instance.directions(widget.pickup.location, widget.drop.location);
    if (mounted && dir != null && dir.points.isNotEmpty) {
      setState(() => _routePoints = dir.points);
    }
  }

  Future<void> _confirmBooking() async {
    if (_serviceType == null) return;
    
    final confirmedPlace = await Navigator.push<Place>(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmPickupScreen(initialLocation: widget.pickup),
      ),
    );
    if (confirmedPlace == null) return;

    HapticFeedback.mediumImpact();
    
    final booking = context.read<BookingProvider>();
    Map<String, dynamic>? created;
    String? caughtError;
    
    try {
      final actualServiceType = widget.isTruckMode ? 'truck' : _serviceType!;
      created = await booking.createBooking(
        serviceType: actualServiceType,
        pickup: confirmedPlace.location,
        pickupAddress: confirmedPlace.fullAddress,
        drop: widget.drop.location,
        dropAddress: widget.drop.fullAddress,
        paymentMethod: _payment,
        promoCode: _promo.isEmpty ? null : _promo,
        redeemPoints: _usePoints ? context.read<PromosProvider>().points : 0,
        tripType: widget.tripType,
        stops: [],
        friendName: _secondaryPhone != null && _secondaryPhone!.isNotEmpty ? 'Secondary' : widget.friend?.name,
        friendPhone: _secondaryPhone != null && _secondaryPhone!.isNotEmpty ? _secondaryPhone : widget.friend?.phone,
        receiverName: _secondaryPhone != null && _secondaryPhone!.isNotEmpty ? 'Secondary' : null,
        receiverPhone: _secondaryPhone != null && _secondaryPhone!.isNotEmpty ? _secondaryPhone : null,
        parcelInstructions: _driverNote.isNotEmpty ? _driverNote : null,
      );
    } catch (e) {
      caughtError = e.toString();
    }
    
    if (!mounted) return;
    
    if (created == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          icon: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 36),
          title: const Text('Booking failed', textAlign: TextAlign.center),
          content: Text(
            caughtError ?? booking.lastError ?? 'Could not create booking. Check your connection and try again.',
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RideTrackingScreen()),
      (route) => route.isFirst,
    );
  }

  void _showPromoDialog() async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PromotionsSelectionScreen(currentPromo: _promo),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _promo = selected;
      });
      _recalculate();
    }
  }

  void _showPaymentPicker() async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSelectionScreen(currentPayment: _payment),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _payment = selected;
      });
    }
  }

  void _showNoteBottomSheet() {
    final noteController = TextEditingController(text: _driverNote);
    final phoneController = TextEditingController(text: _secondaryPhone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Add note for driver',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, color: Colors.black),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Send a special note to your driver',
                    style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: noteController,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "E.g., I'm standing next to the Kohuwala Sampath ATM. Wearing a red t-shirt",
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.normal),
                      filled: true,
                      fillColor: Colors.grey.withOpacity(0.04),
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.grey.shade200),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.phone_outlined, color: Colors.black, size: 24),
                    title: const Text(
                      'Secondary mobile number',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
                    ),
                    subtitle: Text(
                      _secondaryPhone != null && _secondaryPhone!.isNotEmpty
                          ? _secondaryPhone!
                          : 'If you are unavailable, the driver partner will call this number',
                      style: TextStyle(
                        fontSize: 12,
                        color: _secondaryPhone != null && _secondaryPhone!.isNotEmpty
                            ? AppColors.primary
                            : Colors.grey.shade500,
                        fontWeight: _secondaryPhone != null && _secondaryPhone!.isNotEmpty
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward, size: 20, color: Colors.black),
                    onTap: () {
                      // Show phone input dialog
                      showDialog(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text('Secondary Mobile Number', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          content: TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: 'e.g. +94771234567',
                              labelText: 'Mobile Number',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                setModalState(() {
                                  _secondaryPhone = phoneController.text.trim();
                                });
                                Navigator.pop(dCtx);
                              },
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_rounded, color: Colors.blueAccent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This is an optional message, your driver partner may or may not read your note. We suggest calling your driver partner to relay any important information',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.4, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _driverNote = noteController.text.trim();
                        });
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade200,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _hidePromoBanner = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: ZiggoMap(
              controller: _mapController,
              center: widget.pickup.location,
              zoom: 13,
              showMyLocation: true,
              markers: [
                if (!_loadingEstimates && _serviceType != null)
                  for (final d in _nearbyDrivers)
                    if ((widget.isTruckMode && d['vehicle_type'] == 'truck') ||
                        (!widget.isTruckMode && d['vehicle_type'] == _serviceType))
                      pinMarker(
                        point: LatLng((d['lat'] as num).toDouble(), (d['lng'] as num).toDouble()),
                        icon: _vehicleIcon(d['vehicle_type'] as String?),
                        color: _vehicleColor(d['vehicle_type'] as String?),
                        size: 30,
                        assetPath: _vehicleAsset(d['vehicle_type'] as String?),
                        rotation: (d['heading'] as num?)?.toDouble() ?? 0.0,
                      ),
                pinMarker(
                  point: widget.pickup.location,
                  icon: Icons.my_location_rounded,
                  color: AppColors.info,
                  label: 'Pickup | ${widget.pickup.name}',
                ),
                pinMarker(
                  point: widget.drop.location,
                  icon: Icons.location_on_rounded,
                  color: AppColors.primaryDark,
                  label: 'Drop | ${widget.drop.name}',
                ),
              ],
              polylines: [
                ZiggoPolyline(
                  points: _routePoints.isNotEmpty ? _routePoints : [widget.pickup.location, widget.drop.location],
                  strokeWidth: 4,
                  color: Colors.black,
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppStyles.shadowSm),
                      child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                    ),
                  ),
                  GestureDetector(
                    onTap: _animateToUserLocation,
                    child: Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: AppStyles.shadowSm),
                      child: const Icon(Icons.gps_fixed_rounded, color: AppColors.textPrimary, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, -6))],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // Promotional banner - only show when bike is selected and not dismissed
                  if (_serviceType == 'bike' && !_hidePromoBanner)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.local_offer_rounded, color: AppColors.success, size: 16),
                          const SizedBox(width: 8),
                          const Text('You are saving 10% more on Bike.', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 13)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => setState(() => _hidePromoBanner = true),
                            child: Icon(Icons.close_rounded, color: AppColors.success.withOpacity(0.6), size: 18),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  
                  // Vehicles horizontal list
                  if (_loadingEstimates)
                    const SizedBox(height: 140, child: Center(child: CircularProgressIndicator()))
                  else
                    SizedBox(
                      height: 140,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: (widget.isTruckMode 
                            ? ['light', 'light_open', 'mover', 'mover_open'] 
                            : _serviceTypes
                          ).map((st) => _vehicleCard(st)).toList(),
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  
                  // Bottom actions (Cash, Note, Promo)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _showPaymentPicker,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.cardBorder),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _payment == 'cash'
                                        ? Icons.payments_rounded
                                        : _payment == 'wallet'
                                            ? Icons.account_balance_wallet_rounded
                                            : _payment == 'corporate'
                                                ? Icons.business_rounded
                                                : Icons.credit_card_rounded,
                                    color: AppColors.success,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _payment == 'cash'
                                        ? 'Cash'
                                        : _payment == 'wallet'
                                            ? 'Wallet'
                                            : _payment == 'corporate'
                                                ? 'Corporate'
                                                : _getSelectedCardLabel(),
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: _showNoteBottomSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.cardBorder),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.edit_note_rounded, color: _driverNote.isNotEmpty ? AppColors.primary : AppColors.textSecondary, size: 18),
                                  const SizedBox(width: 8),
                                  Text(_driverNote.isNotEmpty ? 'Note Added' : 'Add note', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: _showPromoDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.cardBorder),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.local_offer_rounded, color: _promo.isNotEmpty ? AppColors.success : AppColors.primary, size: 18),
                                  const SizedBox(width: 8),
                                  Text(_promo.isNotEmpty ? 'Applied' : 'Add Promo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _promo.isNotEmpty ? AppColors.success : AppColors.primary)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  if (widget.isTruckMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.cardBorder),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: CheckboxListTile(
                          value: _truckTermsAccepted,
                          onChanged: (v) => setState(() => _truckTermsAccepted = v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: RichText(
                            text: const TextSpan(
                              text: 'I confirm that I have read, consent and agree to the ',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                              children: [
                                TextSpan(text: 'Terms and Conditions', style: TextStyle(color: Colors.blue)),
                              ],
                            ),
                          ),
                          activeColor: AppColors.primary,
                        ),
                      ),
                    ),
                  
                  // Book Now Button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _loadingEstimates || _serviceType == null || (widget.isTruckMode && !_truckTermsAccepted) ? null : _confirmBooking,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black, // Ziggo dark theme
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                              ),
                              child: const Text('BOOK NOW', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                            ),
                          ),
                        ),
                        if (widget.isTruckMode) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: SizedBox(
                              height: 54,
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  // TODO: Schedule later
                                },
                                icon: const Icon(Icons.schedule_rounded, color: AppColors.textPrimary, size: 20),
                                label: const Text('Later', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.textPrimary)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.cardBorder),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(27)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ],
      ),
    );
  }

  Widget _vehicleCard(String st) {
    final selected = _serviceType == st;
    final est = _estimates[st];
    if (est == null) return const SizedBox.shrink();

    final meta = {
      'bike': ('Bike', 'assets/icons/bike.png', 1),
      'tuk': ('Tuk', 'assets/icons/tuk.png', 3),
      'car': ('Flex', 'assets/icons/car.png', 4),
      'mini': ('Mini', 'assets/icons/car.png', 4),
      'van': ('Mini van', 'assets/icons/taxi.png', 8),
      'truck': ('Truck', 'assets/icons/truck.png', 2),
      'light': ('Light', 'assets/icons/truck.png', 1),
      'light_open': ('Light Open', 'assets/icons/truck.png', 1),
      'mover': ('Mover', 'assets/icons/truck.png', 1),
      'mover_open': ('Mover Open', 'assets/icons/truck.png', 1),
    }[st];

    final category = _categoryData[st];
    final customName = category?['name'] as String?;
    final customImage = category?['image_url'] as String?;

    final displayName = customName ?? meta?.$1 ?? (st.isNotEmpty ? '${st[0].toUpperCase()}${st.substring(1)}' : st);
    final assetIcon = meta?.$2 ?? 'assets/icons/taxi.png';
    final capacity = meta?.$3 ?? 4;

    final customImageUrl = (customImage != null && customImage.isNotEmpty)
        ? (customImage.startsWith('http') 
            ? customImage 
            : (customImage.startsWith('/') 
                ? '${ApiConfig.baseHost}$customImage' 
                : '${ApiConfig.baseHost}/$customImage'))
        : null;

    // Find nearby drivers of this type to calculate pickup ETA
    int etaMin;
    final typeDrivers = _nearbyDrivers.where((d) => d['vehicle_type'] == st).toList();
    if (typeDrivers.isNotEmpty) {
      final minDist = typeDrivers.map((d) => d['distance_km'] as num).reduce((a, b) => a < b ? a : b).toDouble();
      etaMin = (minDist / 25.0 * 60).round();
      if (etaMin < 2) etaMin = 2;
    } else {
      etaMin = {
        'bike': 3,
        'tuk': 4,
        'car': 6,
        'mini': 7,
        'van': 8,
        'truck': 10,
        'light': 8,
        'light_open': 8,
        'mover': 12,
        'mover_open': 12,
      }[st] ?? 5;
    }

    return GestureDetector(
      onTap: () {
        setState(() => _serviceType = st);
        _fetchNearbyDrivers();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: widget.isTruckMode ? 115 : 100,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? AppColors.surfaceMuted : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Colors.black : AppColors.cardBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('In $etaMin min', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            customImageUrl != null
                ? Image.network(
                    customImageUrl,
                    height: 32,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Image.asset(assetIcon, height: 32, fit: BoxFit.contain),
                  )
                : Image.asset(assetIcon, height: 32, fit: BoxFit.contain),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    displayName, 
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.person_rounded, size: 10, color: AppColors.textSecondary),
                Text(' ${est['capacity'] ?? capacity}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: 4),
            Text('LKR ${(est['final_amount'] as num).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  String _getSelectedCardLabel() {
    final cards = context.read<PaymentMethodsProvider>().cards;
    try {
      final id = int.parse(_payment.split('_')[1]);
      final card = cards.firstWhere((c) => c['id'] == id);
      final no = card['card_no'].toString();
      return "${card['card_type']} •••• ${no.substring(no.length - 4)}";
    } catch (_) {
      return "Card";
    }
  }
}
