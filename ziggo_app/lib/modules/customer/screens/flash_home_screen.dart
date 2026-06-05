import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';
import '../booking_provider.dart';
import '../payment_methods_provider.dart';
import '../wallet_provider.dart';
import 'flash_tracking_screen.dart';
import 'payment_methods_screen.dart';

class FlashHomeScreen extends StatefulWidget {
  const FlashHomeScreen({super.key});

  @override
  State<FlashHomeScreen> createState() => _FlashHomeScreenState();
}

class _FlashHomeScreenState extends State<FlashHomeScreen> {
  Place? _pickup;
  Place? _drop;
  String _serviceType = 'bike';
  String _payment = 'cash';
  String _parcelType = 'document';

  List<Map<String, dynamic>> _tiers = const [];
  int _weightIndex = 0;
  bool _loadingTiers = true;

  final _receiverNameCtrl = TextEditingController();
  final _receiverPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final ZiggoMapController _mapController = ZiggoMapController();
  Map<String, dynamic>? _estimate;
  bool _busy = false;
  String? _error;
  List<LatLng> _routePoints = const [];

  @override
  void initState() {
    super.initState();
    _pickup = kColomboPlaces[0];
    _receiverNameCtrl.addListener(_onReceiverEdit);
    _receiverPhoneCtrl.addListener(_onReceiverEdit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTiers();
      _useCurrentLocationForPickup();
      context.read<PaymentMethodsProvider>().fetchCards();
      context.read<PaymentMethodsProvider>().fetchCorporateProfile();
      context.read<WalletProvider>().refresh();
    });
  }

  Future<void> _loadTiers() async {
    final tiers = await context.read<BookingProvider>().fetchFlashTiers();
    if (!mounted) return;
    setState(() {
      _tiers = tiers;
      _loadingTiers = false;
      if (_weightIndex >= _tiers.length) _weightIndex = 0;
    });
    await _recalc();
  }

  double? get _selectedWeightKg {
    if (_tiers.isEmpty || _weightIndex >= _tiers.length) return null;
    final v = _tiers[_weightIndex]['representative_weight_kg'];
    if (v is num) return v.toDouble();
    return null;
  }

  String _weightRangeLabel(Map<String, dynamic> t) {
    final min = (t['min_weight_kg'] as num?)?.toDouble() ?? 0;
    final max = t['max_weight_kg'];
    if (max == null) return '> ${min.toStringAsFixed(min == min.roundToDouble() ? 0 : 1)} kg';
    final maxD = (max as num).toDouble();
    if (min == 0) return '< ${maxD.toStringAsFixed(maxD == maxD.roundToDouble() ? 0 : 1)} kg';
    return '${min.toStringAsFixed(min == min.roundToDouble() ? 0 : 1)} – ${maxD.toStringAsFixed(maxD == maxD.roundToDouble() ? 0 : 1)} kg';
  }

  IconData _iconFromName(String name) {
    switch (name) {
      case 'feed':
        return Icons.feed_rounded;
      case 'shopping_bag':
        return Icons.shopping_bag_rounded;
      case 'inventory_2':
        return Icons.inventory_2_rounded;
      case 'local_shipping':
        return Icons.local_shipping_rounded;
      case 'backpack':
        return Icons.backpack_rounded;
      case 'luggage':
        return Icons.luggage_rounded;
      default:
        return Icons.inventory_2_rounded;
    }
  }

  Future<void> _useCurrentLocationForPickup() async {
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted || here == null) return;
    setState(() => _pickup = here);
    await _recalc();
  }

  @override
  void dispose() {
    _receiverNameCtrl.dispose();
    _receiverPhoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _recalc() async {
    if (_pickup == null || _drop == null) return;
    setState(() {
      _routePoints = const [];
    });
    final res = await context.read<BookingProvider>().estimateFare(
          serviceType: _serviceType,
          pickup: _pickup!.location,
          drop: _drop!.location,
          isFlash: true,
          parcelWeightKg: _selectedWeightKg,
        );
    final dir = await MapsService.instance.directions(_pickup!.location, _drop!.location);
    if (mounted) {
      setState(() {
        _estimate = res;
        if (dir != null && dir.points.isNotEmpty) {
          _routePoints = dir.points;
        }
      });
    }
  }

  Future<void> _selectPlace(bool isPickup) async {
    final p = await showPlaceSearch(
      context,
      title: isPickup ? 'Pickup location' : 'Drop-off location',
      near: _pickup?.location ?? kColomboCenter,
      allowCurrentLocation: isPickup,
    );
    if (p != null) {
      setState(() {
        if (isPickup) {
          _pickup = p;
        } else {
          _drop = p;
        }
        _error = null;
      });
      _mapController.moveTo(p.location, zoom: 15);
      await _recalc();
    }
  }

  void _onReceiverEdit() {
    setState(() {
      if (_error != null) _error = null;
    });
  }

  String get _normalizedReceiverPhone {
    final raw = _receiverPhoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    return raw.length > 10 ? raw.substring(0, 10) : raw;
  }

  String? _validate() {
    if (_pickup == null) return 'Set a pickup location';
    if (_drop == null) return 'Set a delivery location';
    if (_pickup!.location == _drop!.location ||
        (_pickup!.fullAddress == _drop!.fullAddress &&
            _pickup!.fullAddress.isNotEmpty)) {
      return 'Pickup and delivery cannot be the same place';
    }
    if (_receiverNameCtrl.text.trim().length < 2) {
      return 'Enter the receiver’s name';
    }
    final phone = _normalizedReceiverPhone;
    if (phone.length != 10) {
      return 'Enter a valid 10-digit receiver phone';
    }
    if (_estimate == null) return 'Waiting for fare estimate…';
    return null;
  }

  bool get _formReady => _validate() == null && !_busy;

  String _fareSubline() {
    final est = _estimate;
    if (est == null) return '';
    final distance = (est['distance_km'] as num?)?.toDouble();
    final duration = (est['duration_min'] as num?)?.toInt();
    final parts = <String>[];
    if (distance != null) parts.add('${distance.toStringAsFixed(1)} km');
    if (duration != null) parts.add('~$duration min');
    return parts.join(' • ');
  }

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
          serviceType: _serviceType,
          pickup: _pickup!.location,
          pickupAddress: _pickup!.fullAddress,
          drop: _drop!.location,
          dropAddress: _drop!.fullAddress,
          paymentMethod: _payment,
          isFlash: true,
          parcelType: _parcelType,
          parcelWeightKg: _selectedWeightKg,
          receiverName: _receiverNameCtrl.text.trim(),
          receiverPhone: _normalizedReceiverPhone,
          parcelInstructions:
              _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (created == null) {
      setState(() =>
          _error = context.read<BookingProvider>().lastError ?? 'Could not book');
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const FlashTrackingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // 1. Map Background (top half)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.45,
            child: ZiggoMap(
              controller: _mapController,
              center: _pickup?.location ?? kColomboCenter,
              zoom: 14,
              showMyLocation: true,
              markers: [
                if (_pickup != null)
                  pinMarker(
                    point: _pickup!.location,
                    icon: Icons.inventory_2_rounded,
                    color: AppColors.success,
                    label: 'Sender | ${_pickup!.name.isNotEmpty ? _pickup!.name : _pickup!.fullAddress}',
                  ),
                if (_drop != null)
                  pinMarker(
                    point: _drop!.location,
                    icon: Icons.location_on_rounded,
                    color: AppColors.error,
                    label: 'Receiver | ${_drop!.name.isNotEmpty ? _drop!.name : _drop!.fullAddress}',
                  ),
              ],
              polylines: (_pickup != null && _drop != null)
                  ? [
                      ZiggoPolyline(
                        points: _routePoints.isNotEmpty ? _routePoints : [_pickup!.location, _drop!.location],
                        strokeWidth: 5,
                        color: AppColors.primary.withOpacity(0.8),
                      ),
                    ]
                  : const [],
            ),
          ),

          // 2. Gradient Overlay for status bar area
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
                  colors: [
                    Colors.black.withOpacity(0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // 4. Scrollable Content Sheet
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.38),
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                      
                      // Service Title
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'ZIGGO FLASH',
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
                          'Send a Parcel',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Location Card
                      _buildLocationCard(),

                      const SizedBox(height: 24),
                      _sectionHeader('WHAT ARE YOU SENDING?'),
                      const SizedBox(height: 12),
                      _buildTypePicker(),

                      const SizedBox(height: 24),
                      _sectionHeader('PARCEL WEIGHT'),
                      const SizedBox(height: 12),
                      _buildWeightPicker(),

                      const SizedBox(height: 24),
                      _sectionHeader('RECEIVER DETAILS'),
                      const SizedBox(height: 12),
                      _buildReceiverForm(),

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

                      const SizedBox(height: 140), // Space for bottom bar
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
                child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
              ),
            ),
          ),

          // 5. Fixed Bottom Action Bar
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
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
                          'ESTIMATED FARE',
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
                        if (_estimate != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _fareSubline(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                                  Icon(Icons.flash_on_rounded,
                                      color: AppColors.primary, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'SEND NOW',
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

  Widget _buildLocationCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        children: [
          _locationRow(true, _pickup?.fullAddress ?? 'Set pickup point'),
          Padding(
            padding: const EdgeInsets.only(left: 15, top: 4, bottom: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 2,
                height: 20,
                color: AppColors.divider.withOpacity(0.4),
              ),
            ),
          ),
          _locationRow(false, _drop?.fullAddress ?? 'Set delivery point'),
        ],
      ),
    );
  }

  Widget _locationRow(bool isPickup, String address) {
    return InkWell(
      onTap: () => _selectPlace(isPickup),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (isPickup ? AppColors.primary : AppColors.error).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isPickup ? Icons.inventory_2_rounded : Icons.location_on_rounded,
              size: 16,
              color: isPickup ? AppColors.primary : AppColors.error,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPickup ? 'PICKUP' : 'DELIVERY',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.textTertiary),
                ),
                Text(
                  address,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.edit_rounded, size: 16, color: AppColors.textTertiary),
        ],
      ),
    );
  }

  Widget _buildTypePicker() {
    final types = [
      ('document', 'Docs', Icons.description_rounded),
      ('food', 'Food', Icons.restaurant_rounded),
      ('clothes', 'Clothes', Icons.checkroom_rounded),
      ('other', 'Other', Icons.inventory_2_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: types.map((t) {
          final sel = _parcelType == t.$1;
          return GestureDetector(
            onTap: () => setState(() => _parcelType = t.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: sel ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: sel ? Colors.black : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Icon(t.$3, size: 18, color: sel ? AppColors.primary : AppColors.textPrimary),
                  const SizedBox(width: 10),
                  Text(
                    t.$2,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: sel ? Colors.white : AppColors.textPrimary,
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

  Widget _buildWeightPicker() {
    if (_loadingTiers) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_tiers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text(
            'No weight tiers configured yet. Ask admin to add tiers in /admin/flash-pricing.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(_tiers.length, (i) {
          final t = _tiers[i];
          final sel = _weightIndex == i;
          final surcharge = (t['surcharge'] as num?)?.toDouble() ?? 0;
          final label = t['label']?.toString() ?? '';
          final icon = _iconFromName(t['icon']?.toString() ?? 'inventory_2');
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _weightIndex = i);
                _recalc();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.only(right: i == _tiers.length - 1 ? 0 : 8),
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? AppColors.primary : const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    Icon(icon, size: 22, color: sel ? Colors.white : AppColors.primary),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: sel ? Colors.white : AppColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _weightRangeLabel(t),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: sel ? Colors.white70 : AppColors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      surcharge == 0 ? 'Free' : '+Rs.${surcharge.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: sel
                            ? Colors.white
                            : (surcharge == 0 ? AppColors.success : AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildReceiverForm() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          _textField(_receiverNameCtrl, 'Receiver Name', Icons.person_rounded,
              hint: 'e.g. Faris Ahmed'),
          const SizedBox(height: 16),
          _textField(
            _receiverPhoneCtrl,
            'Receiver Phone',
            Icons.phone_rounded,
            keyboard: TextInputType.number,
            hint: '0712345678',
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
          ),
          const SizedBox(height: 16),
          _textField(_notesCtrl, 'Delivery Instructions', Icons.notes_rounded,
              maxLines: 2, hint: 'Apt no., landmark, etc. (optional)'),
        ],
      ),
    );
  }

  Widget _textField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType? keyboard,
    int maxLines = 1,
    List<TextInputFormatter>? inputFormatters,
    String? hint,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      maxLines: maxLines,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
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

  void _showPaymentPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final cardsProvider = ctx.watch<PaymentMethodsProvider>();
        final walletProvider = ctx.watch<WalletProvider>();
        
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Choose Payment Method',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 16),
                
                // Cash Option
                ListTile(
                  leading: const Icon(Icons.payments_rounded, color: AppColors.primary),
                  title: const Text('Cash', style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: _payment == 'cash' ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                  onTap: () {
                    setState(() => _payment = 'cash');
                    Navigator.pop(ctx);
                  },
                ),
                const Divider(height: 1),
                
                // Wallet Option
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary),
                  title: const Text('Ziggo Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Balance: Rs.${walletProvider.balance.toStringAsFixed(2)}'),
                  trailing: _payment == 'wallet' ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                  onTap: () {
                    setState(() => _payment = 'wallet');
                    Navigator.pop(ctx);
                  },
                ),
                const Divider(height: 1),

                // Corporate Option
                if (cardsProvider.corporateProfile != null) ...[
                  ListTile(
                    leading: const Icon(Icons.business_rounded, color: AppColors.primary),
                    title: Text('Corporate: ${cardsProvider.corporateProfile!['company_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Status: ${(cardsProvider.corporateProfile!['status'] ?? 'active').toUpperCase()}'),
                    trailing: _payment == 'corporate' ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                    onTap: () {
                      setState(() => _payment = 'corporate');
                      Navigator.pop(ctx);
                    },
                  ),
                  const Divider(height: 1),
                ],

                // Saved Cards
                if (cardsProvider.cards.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
                    child: Text(
                      'SAVED CARDS',
                      style: TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.bold, letterSpacing: 1.1),
                    ),
                  ),
                  ...cardsProvider.cards.map((c) {
                    final String cardNo = c['card_no'] ?? '';
                    final String value = 'card_${c['id']}';
                    return ListTile(
                      leading: const Icon(Icons.credit_card_rounded, color: AppColors.primary),
                      title: Text('${c['card_type']} ending in ${cardNo.substring(cardNo.length - 4)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      trailing: _payment == value ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                      onTap: () {
                        setState(() => _payment = value);
                        Navigator.pop(ctx);
                      },
                    );
                  }),
                  const Divider(height: 1),
                ],

                // Add card shortcut
                ListTile(
                  leading: const Icon(Icons.add_rounded, color: AppColors.accent),
                  title: const Text('Add new card', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PaymentMethodsScreen()),
                    );
                    if (context.mounted) {
                      context.read<PaymentMethodsProvider>().fetchCards();
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentPicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: InkWell(
        onTap: () => _showPaymentPicker(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(
                _payment == 'cash'
                    ? Icons.payments_rounded
                    : _payment == 'wallet'
                        ? Icons.account_balance_wallet_rounded
                        : _payment == 'corporate'
                            ? Icons.business_rounded
                            : Icons.credit_card_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _payment == 'cash'
                      ? 'Cash'
                      : _payment == 'wallet'
                          ? 'Ziggo Wallet (Rs.${context.read<WalletProvider>().balance.toStringAsFixed(0)})'
                          : _payment == 'corporate'
                              ? 'Corporate Profile (${context.read<PaymentMethodsProvider>().corporateProfile?['company_name'] ?? 'Business'})'
                              : _getSelectedCardLabel(),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const Text(
                'CHANGE',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
