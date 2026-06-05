import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/widgets/motion.dart';
import '../addresses_provider.dart';
import '../food_provider.dart';
import '../promos_provider.dart';
import 'food_tracking_screen.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AddressesProvider>().refresh();
      context.read<PromosProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _instructionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPlace() async {
    final p = await showPlaceSearch(context, title: 'Delivery address');
    if (p != null) {
      setState(() {
        _deliveryPlace = p;
        _deliveryAddress = null;
      });
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
    final deliveryFee = (restaurant?['delivery_fee'] as num?)?.toDouble() ?? 0;
    
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
                          'Rs.${((it['price'] as num) * qty).toStringAsFixed(0)}',
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
                    onTap: () => setState(() {
                      _deliveryAddress = a;
                      _deliveryPlace = null;
                    }),
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
            child: Row(
              children: [
                _payOption('cash', Icons.payments_rounded, 'Cash'),
                const SizedBox(width: 10),
                _payOption('wallet', Icons.account_balance_wallet_rounded, 'Wallet'),
              ],
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
                _row('Items total', 'Rs.${food.cartTotal.toStringAsFixed(0)}'),
                _row('Delivery fee', 'Rs.${deliveryFee.toStringAsFixed(0)}'),
                if (_usePoints && discount > 0)
                  _row('Points Discount', '-Rs.${discount.toStringAsFixed(0)}', color: AppColors.success),
                const Divider(height: 16),
                _row('Total', 'Rs.${total.toStringAsFixed(0)}', bold: true),
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
            label: 'PLACE ORDER • Rs.${total.toStringAsFixed(0)}',
            icon: Icons.check_rounded,
            busy: _busy,
            onPressed: _placeOrder,
          ),
        ),
      ),
    );
  }

  Widget _payOption(String value, IconData icon, String label) {
    final selected = _payment == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _payment = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? Colors.black : AppColors.cardBorder,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: selected ? AppColors.primary : AppColors.textPrimary, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: selected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              if (selected) ...[
                const Spacer(),
                const Icon(Icons.check_rounded, color: AppColors.primary, size: 16),
              ],
            ],
          ),
        ),
      ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
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
