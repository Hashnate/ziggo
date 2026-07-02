import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/widgets/motion.dart';
import '../addresses_provider.dart';
import '../food_provider.dart';
import '../food_ui.dart';
import '../promos_provider.dart';
import '../wallet_provider.dart';
import '../payment_methods_provider.dart';
import 'food_tracking_screen.dart';
import 'payment_methods_screen.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _payment = 'cash';
  Place? _deliveryPlace;
  Map<String, dynamic>? _deliveryAddress;
  final _instructionsCtrl = TextEditingController();
  bool _busy = false;
  bool _usePoints = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final addr = context.read<AddressesProvider>();
      await addr.refresh();
      if (mounted && _deliveryAddress == null && _deliveryPlace == null && addr.items.isNotEmpty) {
        final def = addr.items.firstWhere(
            (a) => a['is_default'] == true,
            orElse: () => addr.items.first);
        setState(() => _deliveryAddress = def);
        _refreshQuote();
      }
      if (mounted) {
        context.read<PromosProvider>().refresh();
        context.read<PaymentMethodsProvider>().fetchCards();
        context.read<PaymentMethodsProvider>().fetchCorporateProfile();
      }
    });
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshQuote() async {
    double? lat;
    double? lng;
    if (_deliveryAddress != null) {
      lat = (_deliveryAddress!['lat'] as num).toDouble();
      lng = (_deliveryAddress!['lng'] as num).toDouble();
    } else if (_deliveryPlace != null) {
      lat = _deliveryPlace!.location.latitude;
      lng = _deliveryPlace!.location.longitude;
    }
    if (lat != null && lng != null) {
      await context.read<FoodProvider>().quoteDelivery(lat: lat, lng: lng);
    }
  }

  Future<void> _pickPlace() async {
    final p = await showPlaceSearch(context, title: 'Delivery address', allowCurrentLocation: true);
    if (p != null) {
      setState(() {
        _deliveryPlace = p;
        _deliveryAddress = null;
      });
      _refreshQuote();
    }
  }

  Future<void> _placeOrder() async {
    final food = context.read<FoodProvider>();
    double lat, lng;
    String addr;

    if (_deliveryAddress != null) {
      lat = (_deliveryAddress!['lat'] as num).toDouble();
      lng = (_deliveryAddress!['lng'] as num).toDouble();
      addr = _deliveryAddress!['address'].toString();
    } else if (_deliveryPlace != null) {
      lat = _deliveryPlace!.location.latitude;
      lng = _deliveryPlace!.location.longitude;
      addr = _deliveryPlace!.fullAddress;
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

    setState(() => _busy = true);
    final order = await food.placeOrder(
      deliveryAddress: addr,
      lat: lat,
      lng: lng,
      paymentMethod: _payment,
      instructions: _instructionsCtrl.text.trim(),
      redeemPoints: _usePoints ? context.read<PromosProvider>().points : 0,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (order == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(food.error ?? 'Could not place order'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => FoodTrackingScreen(orderRef: order['order_ref'] as String)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final food = context.watch<FoodProvider>();
    final addr = context.watch<AddressesProvider>();
    final promos = context.watch<PromosProvider>();
    final restaurant = food.activeRestaurant;
    final quote = food.quote;
    final deliveryFee = (quote?['delivery_fee'] as num?)?.toDouble() ??
        (restaurant?['delivery_fee'] as num?)?.toDouble() ?? 0.0;
    
    double total = food.cartTotal + deliveryFee;
    double discount = 0.0;
    if (_usePoints) {
      discount = promos.pointsValue;
      if (discount > total) discount = total;
      total -= discount;
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
          _Section(
            title: 'YOUR ORDER',
            child: Column(
              children: [
                if (restaurant != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            gradient: AppColors.serviceGradient(AppColors.primary),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(Icons.restaurant_rounded,
                              color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            restaurant['name']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ...food.cart.values.map((e) {
                  final it = e['item'] as Map<String, dynamic>;
                  final qty = e['quantity'] as int;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${qty}x',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(it['name'].toString())),
                        Text(
                          formatRs((it['price'] as num) * qty),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          _Section(
            title: 'DELIVERY ADDRESS',
            child: Column(
              children: [
                ...addr.items.map((a) {
                  final selected = _deliveryAddress?['id'] == a['id'];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _deliveryAddress = a;
                        _deliveryPlace = null;
                      });
                      _refreshQuote();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary.withOpacity(0.08) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? AppColors.primary : AppColors.cardBorder,
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
                              color: selected ? AppColors.primary : AppColors.textSecondary,
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
                            const Icon(Icons.check_circle_rounded, color: AppColors.primary),
                        ],
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: _pickPlace,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(Icons.add_location_alt_rounded,
                              color: AppColors.primary, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _deliveryPlace?.fullAddress ?? 'Pick another location',
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          _Section(
            title: 'INSTRUCTIONS',
            child: TextField(
              controller: _instructionsCtrl,
              maxLines: 2,
              style: const TextStyle(fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'e.g. less spicy, leave at the gate...',
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          _Section(
            title: 'PAYMENT METHOD',
            child: InkWell(
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
                                ? 'Ziggo Wallet (Rs.${context.read<WalletProvider>().balance.toStringAsFixed(0)})'
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
          if (promos.points > 0 && promos.points >= ((promos.loyalty['min_redeem_points'] as num?)?.toInt() ?? 100))
            _Section(
              title: 'LOYALTY POINTS',
              child: Row(
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
                          'Use ${promos.points} Points',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                        Text(
                          '-Rs.${promos.pointsValue.toStringAsFixed(0)} discount',
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
          _Section(
            title: 'BILL SUMMARY',
            child: Column(
              children: [
                _row('Items total', formatRs(food.cartTotal)),
                _row('Delivery fee', formatRs(deliveryFee)),
                if (_usePoints && discount > 0)
                  _row('Points Discount', '-${formatRs(discount)}', color: AppColors.success),
                const Divider(height: 16),
                _row('Total', formatRs(total), bold: true),
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
            label: 'PLACE ORDER • ${formatRs(total)}',
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: _placeOrder,
          ),
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
              color: color ?? (bold ? AppColors.primary : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
