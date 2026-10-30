import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/widgets/guest_login_prompt.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/auth_provider.dart';
import '../addresses_provider.dart';
import '../market_provider.dart';
import '../promos_provider.dart';
import '../wallet_provider.dart';
import '../payment_methods_provider.dart';
import '../widgets/promo_code_tile.dart';
import 'market_tracking_screen.dart';
import 'payment_methods_screen.dart';
import 'promotions_selection_screen.dart';
import 'set_location_map_screen.dart';
import '../../../core/utils/amount_format.dart';

class MarketCheckoutScreen extends StatefulWidget {
  const MarketCheckoutScreen({super.key});

  @override
  State<MarketCheckoutScreen> createState() => _MarketCheckoutScreenState();
}

class _MarketCheckoutScreenState extends State<MarketCheckoutScreen> {
  String _payment = 'cash';
  Place? _picked;
  Map<String, dynamic>? _saved;
  bool _busy = false;
  bool _usePoints = false;
  bool _isSelfPickup = false;
  bool _isQuoting = false;
  final _promoCheck = PromoCheck();
  final _instructionsCtrl = TextEditingController();

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final addr = context.read<AddressesProvider>();
      await addr.refresh();
      if (mounted && _saved == null && _picked == null && addr.items.isNotEmpty) {
        final def = addr.items.firstWhere(
            (a) => a['is_default'] == true,
            orElse: () => addr.items.first);
        setState(() => _saved = def);
        _refreshQuote();
      }
      if (mounted) {
        context.read<PromosProvider>().refresh();
        context.read<PaymentMethodsProvider>().fetchCards();
        context.read<PaymentMethodsProvider>().fetchCorporateProfile();
      }
    });
  }

  Future<void> _refreshQuote() async {
    final market = context.read<MarketProvider>();
    if (market.cart.isEmpty) return;
    double? lat;
    double? lng;
    if (_saved != null) {
      lat = (_saved!['lat'] as num).toDouble();
      lng = (_saved!['lng'] as num).toDouble();
    } else if (_picked != null) {
      lat = _picked!.location.latitude;
      lng = _picked!.location.longitude;
    }
    if (lat != null && lng != null) {
      if (mounted) setState(() => _isQuoting = true);
      try {
        await market.quoteDelivery(lat: lat, lng: lng);
      } finally {
        if (mounted) setState(() => _isQuoting = false);
      }
    }
  }

  Future<void> _pickPlace() async {
    final p = await showPlaceSearch(
      context,
      title: 'Delivery address',
      allowCurrentLocation: true,
      allowSetOnMap: true,
    );
    if (p == null || !mounted) return;
    if (p.name == '__SET_ON_MAP__') {
      final pickedOnMap = await Navigator.push<Place>(
        context,
        MaterialPageRoute(
          builder: (_) => SetLocationMapScreen(
            initialLocation: _picked,
            title: 'Set delivery address',
            confirmButtonText: 'CONFIRM ADDRESS',
            badgeText: 'Delivery',
          ),
        ),
      );
      if (pickedOnMap != null && mounted) {
        setState(() {
          _picked = pickedOnMap;
          _saved = null;
        });
        _refreshQuote();
      }
      return;
    }
    setState(() {
      _picked = p;
      _saved = null;
    });
    _refreshQuote();
  }

  Future<void> _placeOrder() async {
    double? lat;
    double? lng;
    String? addr;

    if (!_isSelfPickup) {
      if (_saved != null) {
        lat = (_saved!['lat'] as num).toDouble();
        lng = (_saved!['lng'] as num).toDouble();
        addr = _saved!['address'].toString();
      } else if (_picked != null) {
        lat = _picked!.location.latitude;
        lng = _picked!.location.longitude;
        addr = _picked!.fullAddress;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Choose a delivery address'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    final auth = context.read<AuthProvider>();
    if (auth.isGuest) {
      final ok = await GuestLoginPrompt.ensureAuthenticated(
        context,
        message: 'Please sign in or create an account to place your market order.',
      );
      if (!ok) return;
    }

    setState(() => _busy = true);
    final promos = context.read<PromosProvider>();
    final appUsagePct = _isSelfPickup ? ((promos.loyalty['self_pickup_app_usage_charge'] as num?)?.toDouble() ?? 5.0) : 0.0;
    final market = context.read<MarketProvider>();
    final appUsageCharge = _isSelfPickup ? (market.cartTotal * (appUsagePct / 100.0)) : 0.0;

    int pointsToRedeem = 0;
    if (_usePoints && promos.isLoyaltyActive) {
      final double valPerPoint = (promos.loyalty['value_per_point'] as num?)?.toDouble() ?? 0.50;
      final double maxPct = (promos.loyalty['max_redeem_order_pct'] as num?)?.toDouble() ?? 20.0;
      final int minPoints = (promos.loyalty['min_redeem_points'] as num?)?.toInt() ?? 100;
      final int balance = promos.points;

      if (valPerPoint > 0) {
        double subtotal = market.cartTotal + (_isSelfPickup ? 0.0 : ((market.quote?['delivery_fee'] as num?)?.toDouble() ?? 0.0)) + appUsageCharge - _promoCheck.discount(market.pendingPromoCode ?? '');
        double maxDiscount = subtotal * (maxPct / 100.0);
        int allowed = balance;
        double allowedVal = allowed * valPerPoint;
        if (allowedVal > maxDiscount) {
          allowed = (maxDiscount / valPerPoint).floor();
        }
        if (allowed >= minPoints) {
          pointsToRedeem = allowed;
        }
      }
    }

    final order = await market.placeOrder(
      deliveryAddress: addr,
      lat: lat,
      lng: lng,
      paymentMethod: _payment,
      instructions: _instructionsCtrl.text.trim(),
      redeemPoints: pointsToRedeem,
      promoCode: market.pendingPromoCode,
      isSelfPickup: _isSelfPickup,
      appUsageCharge: appUsageCharge,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<MarketProvider>().error ?? 'Order failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MarketTrackingScreen(orderRef: order['order_ref'] as String),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MarketProvider>();
    final addr = context.watch<AddressesProvider>();
    final promos = context.watch<PromosProvider>();
    final vendor = p.activeVendor;
    final quote = p.quote;
    final hasAddress = _saved != null || _picked != null;
    final isCalculatingQuote = !_isSelfPickup && hasAddress && (_isQuoting || p.isQuoting);
    final outOfRange = !_isSelfPickup && !isCalculatingQuote && quote != null && quote['in_range'] == false;
    // Show the live quoted fee once an address is chosen; before then the
    // delivery line is a placeholder and isn't added to the total.
    final deliveryFee = _isSelfPickup ? 0.0 : ((quote?['delivery_fee'] as num?)?.toDouble() ?? 0.0);
    final appUsagePct = _isSelfPickup ? ((promos.loyalty['self_pickup_app_usage_charge'] as num?)?.toDouble() ?? 5.0) : 0.0;
    final appUsageCharge = _isSelfPickup ? (p.cartTotal * (appUsagePct / 100.0)) : 0.0;
    final promoCode = p.pendingPromoCode ?? '';
    _promoCheck.keepFresh(context, promoCode, 'market', p.cartTotal, () {
      if (mounted) setState(() {});
    });
    final promoDiscount = _promoCheck.discount(promoCode);

    double total = p.cartTotal + ((hasAddress && !_isSelfPickup) ? deliveryFee : 0.0) + appUsageCharge - promoDiscount;
    if (total < 0) total = 0;
    int maxRedeemablePoints = 0;
    double potentialDiscount = 0.0;
    double discount = 0.0;

    if (promos.isLoyaltyActive) {
      final double valPerPoint = (promos.loyalty['value_per_point'] as num?)?.toDouble() ?? 0.50;
      final double maxPct = (promos.loyalty['max_redeem_order_pct'] as num?)?.toDouble() ?? 20.0;
      final int minPoints = (promos.loyalty['min_redeem_points'] as num?)?.toInt() ?? 100;
      final int balance = promos.points;

      if (valPerPoint > 0) {
        double maxDiscount = total * (maxPct / 100.0);
        int allowed = balance;
        double allowedVal = allowed * valPerPoint;
        if (allowedVal > maxDiscount) {
          allowed = (maxDiscount / valPerPoint).floor();
          allowedVal = allowed * valPerPoint;
        }
        if (allowed >= minPoints) {
          maxRedeemablePoints = allowed;
          potentialDiscount = allowedVal;
          if (_usePoints) {
            discount = allowedVal;
            if (discount > total) discount = total;
            total -= discount;
          }
        }
      }
    }

    if (p.cart.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'Checkout',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.market.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.shopping_basket_outlined,
                    size: 46,
                    color: AppColors.market,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Your cart is empty',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Explore products in Ziggo Marketplace to add items to your cart.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 28),
                PrimaryButton(
                  label: 'GO TO MARKETPLACE',
                  icon: Icons.storefront_rounded,
                  gold: true,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Checkout'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: staggered([
          // Segmented pickup vs delivery toggle
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppStyles.shadowSm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isSelfPickup = false;
                      _refreshQuote();
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_isSelfPickup ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delivery_dining_rounded,
                              color: !_isSelfPickup ? Colors.white : AppColors.textSecondary,
                              size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Delivery',
                            style: TextStyle(
                              color: !_isSelfPickup ? Colors.white : AppColors.textSecondary,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _isSelfPickup = true;
                    }),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _isSelfPickup ? AppColors.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_bag_rounded,
                              color: _isSelfPickup ? Colors.white : AppColors.textSecondary,
                              size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Self Pickup',
                            style: TextStyle(
                              color: _isSelfPickup ? Colors.white : AppColors.textSecondary,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
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
          _section(
            'YOUR CART',
            trailing: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Clear cart?', style: TextStyle(fontWeight: FontWeight.w900)),
                    content: const Text('Are you sure you want to remove all items from your cart?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('CANCEL', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(ctx);
                          p.clearCart();
                        },
                        child: const Text('CLEAR', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.error)),
                      ),
                    ],
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 14, color: AppColors.error),
                    SizedBox(width: 4),
                    Text(
                      'Clear all',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Column(
              children: p.cart.values.map((e) {
                final pr = e['product'] as Map<String, dynamic>;
                final qty = e['quantity'] as int;
                final pid = (pr['id'] as num).toInt();
                final unitPrice = (pr['price'] as num).toDouble();
                final unit = pr['unit']?.toString() ?? '';
                final itemTotal = unitPrice * qty;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pr['name']?.toString() ?? '',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Rs.${formatAmount(unitPrice)}${unit.isNotEmpty ? ' / $unit' : ''}',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                p.changeQty(pid, -1);
                                _refreshQuote();
                              },
                              child: Container(
                                width: 30,
                                height: 32,
                                alignment: Alignment.center,
                                child: Icon(
                                  qty == 1
                                      ? Icons.delete_outline_rounded
                                      : Icons.remove_rounded,
                                  size: 16,
                                  color: qty == 1
                                      ? AppColors.error
                                      : AppColors.primary,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '$qty',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                p.changeQty(pid, 1);
                                _refreshQuote();
                              },
                              child: Container(
                                width: 30,
                                height: 32,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.add_rounded,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 70,
                        child: Text(
                          'Rs.${formatAmount(itemTotal)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: AppColors.error,
                        ),
                        tooltip: 'Remove item',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () {
                          p.removeFromCart(pid);
                          _refreshQuote();
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          _section(
            _isSelfPickup ? 'PICKUP LOCATION' : 'DELIVERY ADDRESS',
            _isSelfPickup
                ? Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.market.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.storefront_rounded,
                            color: AppColors.market, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vendor?['name']?.toString() ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              vendor?['address']?.toString() ?? 'At Vendor Stalls',
                              style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      ...addr.items.map((a) {
                        final selected = _saved?['id'] == a['id'];
                        return GestureDetector(
                          onTap: () {
                            setState(() { _saved = a; _picked = null; });
                            _refreshQuote();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.market.withOpacity(0.08)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected ? AppColors.market : AppColors.cardBorder,
                                width: selected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    color: selected ? AppColors.market : AppColors.textSecondary,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a['label']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        a['address']?.toString() ?? '',
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(Icons.check_circle_rounded,
                                      color: AppColors.market),
                              ],
                            ),
                          ),
                        );
                      }),
                      Builder(
                        builder: (context) {
                          final pickedSelected = _picked != null && _saved == null;
                          return GestureDetector(
                            onTap: _pickPlace,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: pickedSelected
                                    ? AppColors.market.withOpacity(0.08)
                                    : AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: pickedSelected ? AppColors.market : AppColors.cardBorder,
                                  width: pickedSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.market.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                    child: Icon(
                                      pickedSelected ? Icons.location_on_rounded : Icons.add_location_alt_rounded,
                                      color: AppColors.market,
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _picked?.fullAddress ?? 'Pick another location',
                                      style: TextStyle(
                                        fontWeight: pickedSelected ? FontWeight.w900 : FontWeight.w700,
                                        fontSize: 14,
                                        color: pickedSelected ? AppColors.textPrimary : AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  if (pickedSelected)
                                    const Icon(Icons.check_circle_rounded, color: AppColors.market)
                                  else
                                    const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ),
          _section(
            'INSTRUCTIONS',
            TextField(
              controller: _instructionsCtrl,
              maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'e.g. leave at the gate, call on arrival...',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          _section(
            'PAYMENT',
            InkWell(
              onTap: () => _showPaymentPicker(context),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
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
                                ? 'Ziggo Wallet (Rs.${formatAmount(context.read<WalletProvider>().balance)})'
                                : _payment == 'corporate'
                                    ? 'Corporate (${context.read<PaymentMethodsProvider>().corporateProfile?['company_name'] ?? 'Business'})'
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
          ),
          _section(
            'PROMO CODE',
            PromoCodeTile(
              code: promoCode,
              check: _promoCheck,
              onTap: () async {
                final code = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (_) => PromotionsSelectionScreen(currentPromo: promoCode, category: 'market')),
                );
                if (code != null && mounted) p.setPromoCode(code.toUpperCase());
              },
              onClear: () => p.setPromoCode(null),
            ),
          ),
          if (promos.isLoyaltyActive && maxRedeemablePoints > 0)
            _section(
              'LOYALTY POINTS',
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(Icons.stars_rounded, color: AppColors.primary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Use ${formatAmount(maxRedeemablePoints)} Points',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        Text(
                          '-Rs.${formatAmount(potentialDiscount, 2)} discount',
                          style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _usePoints,
                    onChanged: (v) => setState(() => _usePoints = v),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
          if (outOfRange)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.error.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_off_rounded, color: AppColors.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This address is outside the store\'s ${(quote['radius_km'] as num?)?.toStringAsFixed(0) ?? ''}km delivery range. Pick a closer address.',
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _section(
            'BILL SUMMARY',
            Column(
              children: [
                _row('Items', 'Rs.${formatAmount(p.cartTotal)}'),
                if (!_isSelfPickup) ...[
                  _row(
                    'Delivery',
                    !hasAddress
                        ? 'Pick address'
                        : (isCalculatingQuote || quote == null)
                            ? 'Calculating…'
                            : 'Rs.${formatAmount(deliveryFee)}',
                  ),
                  if (hasAddress && isCalculatingQuote)
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.market,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Measuring distance & fee…',
                            style: TextStyle(
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (quote != null && hasAddress)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 2),
                      child: Row(
                        children: [
                          Text(
                            '${(quote['distance_km'] as num?)?.toStringAsFixed(1) ?? '—'} km'
                            ' • ${(quote['weight_kg'] as num?)?.toStringAsFixed(1) ?? '—'} kg',
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (_isSelfPickup && appUsageCharge > 0)
                  _row('App usage charge', 'Rs.${formatAmount(appUsageCharge)}'),
                if (promoDiscount > 0)
                  _row('Promo ($promoCode)', '-Rs.${formatAmount(promoDiscount)}', color: AppColors.success),
                if (_usePoints && discount > 0)
                  _row('Points Discount', '-Rs.${formatAmount(discount)}', color: AppColors.success),
                const Divider(height: 16),
                _row('Total', 'Rs.${formatAmount(total)}', bold: true),
              ],
            ),
          ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(
            label: isCalculatingQuote
                ? 'CALCULATING DELIVERY FEE…'
                : (outOfRange
                    ? 'OUT OF DELIVERY RANGE'
                    : 'PLACE ORDER • Rs.${formatAmount(total)}'),
            icon: isCalculatingQuote
                ? Icons.sync_rounded
                : (outOfRange ? Icons.location_off_rounded : Icons.check_rounded),
            busy: _busy,
            onPressed: (isCalculatingQuote || outOfRange) ? null : _placeOrder,
          ),
        ),
      ),
    );
  }

  Widget _section(String title, Widget child, {Widget? trailing}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
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
                  subtitle: Text('Balance: Rs.${formatAmount(walletProvider.balance, 2)}'),
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

  Widget _row(String k, String v, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            k,
            style: TextStyle(
              color: color ?? (bold ? AppColors.textPrimary : AppColors.textSecondary),
              fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            v,
            style: TextStyle(
              fontSize: bold ? 20 : 14,
              fontWeight: FontWeight.w900,
              color: color ?? (bold ? AppColors.market : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
