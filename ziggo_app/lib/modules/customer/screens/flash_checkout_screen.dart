import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/places.dart';
import '../../../core/map/ziggo_map.dart';
import '../booking_provider.dart';
import '../payment_methods_provider.dart';
import '../wallet_provider.dart';
import 'flash_tracking_screen.dart';
import 'payment_methods_screen.dart';

class FlashCheckoutScreen extends StatefulWidget {
  final Place pickup;
  final Place drop;
  final String itemType;
  final String whoPays;
  final String receiverName;
  final String receiverPhone;
  final String notes;
  final bool isCourier;

  const FlashCheckoutScreen({
    super.key,
    required this.pickup,
    required this.drop,
    required this.itemType,
    required this.whoPays,
    required this.receiverName,
    required this.receiverPhone,
    required this.notes,
    this.isCourier = false,
  });

  @override
  State<FlashCheckoutScreen> createState() => _FlashCheckoutScreenState();
}

class _FlashCheckoutScreenState extends State<FlashCheckoutScreen> {
  String _payment = 'cash';

  List<Map<String, dynamic>> _tiers = const [];
  int _weightIndex = 0;
  bool _loadingTiers = true;

  final ZiggoMapController _mapController = ZiggoMapController();
  Map<String, dynamic>? _estimate;
  bool _busy = false;
  String? _error;
  List<LatLng> _routePoints = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTiers();
      _fetchRoute();
      context.read<PaymentMethodsProvider>().fetchCards();
      context.read<PaymentMethodsProvider>().fetchCorporateProfile();
      context.read<WalletProvider>().refresh();
    });
  }

  Future<void> _fetchRoute() async {
    final dir = await MapsService.instance.directions(widget.pickup.location, widget.drop.location);
    if (mounted && dir != null && dir.points.isNotEmpty) {
      setState(() {
        _routePoints = dir.points;
      });
      // Adjust map bounds
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _mapController.moveTo(widget.pickup.location, zoom: 12);
      });
    }
  }

  Future<void> _loadTiers() async {
    final tiers = widget.isCourier
        ? await context.read<BookingProvider>().fetchCourierTiers()
        : await context.read<BookingProvider>().fetchFlashTiers();
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

  Future<void> _recalc() async {
    final res = await context.read<BookingProvider>().estimateFare(
          serviceType: 'bike',
          pickup: widget.pickup.location,
          drop: widget.drop.location,
          isFlash: !widget.isCourier,
          isCourier: widget.isCourier,
          parcelWeightKg: _selectedWeightKg,
        );
    if (mounted) {
      setState(() {
        _estimate = res;
      });
    }
  }

  String? _validate() {
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
    
    // Pass whoPays in parcelInstructions or a custom field if API supports it.
    // We will append it to parcelInstructions for now.
    final notes = widget.notes.isNotEmpty ? '${widget.notes} | Pays: ${widget.whoPays}' : 'Pays: ${widget.whoPays}';

    final created = await context.read<BookingProvider>().createBooking(
          serviceType: 'bike',
          pickup: widget.pickup.location,
          pickupAddress: widget.pickup.fullAddress,
          drop: widget.drop.location,
          dropAddress: widget.drop.fullAddress,
          paymentMethod: _payment,
          isFlash: !widget.isCourier,
          isCourier: widget.isCourier,
          parcelType: widget.itemType.toLowerCase(),
          parcelWeightKg: _selectedWeightKg,
          receiverName: widget.receiverName,
          receiverPhone: widget.receiverPhone,
          parcelInstructions: notes,
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
      backgroundColor: AppColors.background,
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
              center: widget.pickup.location,
              zoom: 14,
              showMyLocation: true,
              markers: [
                pinMarker(
                  point: widget.pickup.location,
                  icon: Icons.inventory_2_rounded,
                  color: AppColors.primary,
                  label: 'Sender | ${widget.pickup.name.isNotEmpty ? widget.pickup.name : widget.pickup.fullAddress}',
                ),
                pinMarker(
                  point: widget.drop.location,
                  icon: Icons.location_on_rounded,
                  color: AppColors.warning,
                  label: 'Receiver | ${widget.drop.name.isNotEmpty ? widget.drop.name : widget.drop.fullAddress}',
                ),
              ],
              polylines: [
                ZiggoPolyline(
                  points: _routePoints.isNotEmpty ? _routePoints : [widget.pickup.location, widget.drop.location],
                  strokeWidth: 5,
                  color: AppColors.primary.withOpacity(0.8),
                ),
              ],
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

          // 3. Scrollable Content Sheet
          Positioned.fill(
            child: ListView(
              padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.38),
              children: [
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.background,
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
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Checkout',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (widget.isCourier) ...[
                        const SizedBox(height: 16),
                        _buildCourierBanner(),
                      ],
                      const SizedBox(height: 24),

                      _sectionHeader('PARCEL WEIGHT'),
                      const SizedBox(height: 12),
                      _buildWeightPicker(),

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

          // Back button
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
                          disabledBackgroundColor: AppColors.primarySoft,
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
                                children: [
                                  Icon(
                                    widget.isCourier
                                        ? Icons.local_shipping_rounded
                                        : Icons.flash_on_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.isCourier ? 'BOOK COURIER' : 'SEND NOW',
                                    style: const TextStyle(
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

  Widget _buildCourierBanner() {
    final etaDays = _estimate?['courier_eta_days'];
    final etaLabel = etaDays != null ? '$etaDays–3 day delivery' : '2–3 day delivery';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ziggo Courier • $etaLabel',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Island-wide • weight-based • Powered by CityPak',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
            'No weight tiers configured.',
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
