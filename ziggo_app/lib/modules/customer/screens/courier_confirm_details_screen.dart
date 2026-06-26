import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/map/places.dart';
import '../booking_provider.dart';
import '../payment_methods_provider.dart';
import '../wallet_provider.dart';
import 'flash_tracking_screen.dart';
import 'payment_methods_screen.dart';
import 'promotions_selection_screen.dart';

class CourierConfirmDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> pickupDetails;
  final Map<String, dynamic> dropDetails;
  final List<Map<String, dynamic>> packages;

  const CourierConfirmDetailsScreen({
    super.key,
    required this.pickupDetails,
    required this.dropDetails,
    required this.packages,
  });

  @override
  State<CourierConfirmDetailsScreen> createState() => _CourierConfirmDetailsScreenState();
}

class _CourierConfirmDetailsScreenState extends State<CourierConfirmDetailsScreen> {
  String _payment = 'cash';
  Map<String, dynamic>? _estimate;
  bool _agreedToTerms = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recalc();
      context.read<PaymentMethodsProvider>().fetchCards();
      context.read<PaymentMethodsProvider>().fetchCorporateProfile();
      context.read<WalletProvider>().refresh();
    });
  }

  Future<void> _recalc() async {
    final pickupPlace = widget.pickupDetails['place'] as Place;
    final dropPlace = widget.dropDetails['place'] as Place;
    
    final res = await context.read<BookingProvider>().estimateFare(
      serviceType: 'bike',
      pickup: pickupPlace.location,
      drop: dropPlace.location,
      isFlash: false,
      isCourier: true,
      packages: widget.packages,
    );
    if (mounted) {
      setState(() {
        _estimate = res;
      });
    }
  }

  void _showPaymentPicker() {
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

  String _getPaymentLabel() {
    if (_payment == 'cash') return 'Cash';
    if (_payment == 'wallet') return 'Ziggo Wallet';
    return 'Card';
  }

  Future<void> _proceed() async {
    if (_estimate == null) return;
    
    setState(() {
      _busy = true;
      _error = null;
    });

    final pickupPlace = widget.pickupDetails['place'] as Place;
    final dropPlace = widget.dropDetails['place'] as Place;

    final created = await context.read<BookingProvider>().createBooking(
      serviceType: 'bike',
      pickup: pickupPlace.location,
      pickupAddress: pickupPlace.fullAddress,
      drop: dropPlace.location,
      dropAddress: dropPlace.fullAddress,
      paymentMethod: _payment,
      isFlash: false,
      isCourier: true,
      receiverName: widget.dropDetails['name'],
      receiverPhone: widget.dropDetails['phone'],
      parcelInstructions: 'Sender: ${widget.pickupDetails['name']} (${widget.pickupDetails['phone']})',
      packages: widget.packages,
    );

    if (!mounted) return;
    setState(() => _busy = false);

    if (created == null) {
      setState(() {
        _error = context.read<BookingProvider>().lastError ?? 'Could not book courier.';
      });
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const FlashTrackingScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickupPlace = widget.pickupDetails['place'] as Place;
    final dropPlace = widget.dropDetails['place'] as Place;

    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Courier',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: Column(
        children: [
          // 3-step progress bar (step 3 active)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: List.generate(3, (i) {
                return Expanded(
                  child: Container(
                    height: 5,
                    margin: EdgeInsets.only(right: i == 2 ? 0 : 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                );
              }),
            ),
          ),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                const Text(
                  'Confirm details',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.calendar_month_rounded, color: AppColors.textPrimary, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pickup Time',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Pickup times are not guaranteed. Depending on the city, requested time for pickup may be delayed.',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Location Summary Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 16),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Pick up:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.edit, size: 14, color: AppColors.textSecondary),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  pickupPlace.area.isNotEmpty ? pickupPlace.area : pickupPlace.name,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                                Text(
                                  pickupPlace.area,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                                Text(
                                  widget.pickupDetails['name'],
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                                Text(
                                  widget.pickupDetails['phone'],
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 15, top: 4, bottom: 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('⋮', style: TextStyle(color: AppColors.textTertiary, fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_downward_rounded, color: Colors.white, size: 16),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Text('Drop:', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.edit, size: 14, color: AppColors.textSecondary),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dropPlace.area.isNotEmpty ? dropPlace.area : dropPlace.name,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                                Text(
                                  dropPlace.area,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                                Text(
                                  widget.dropDetails['name'],
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                                Text(
                                  widget.dropDetails['phone'],
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Packages Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_rounded, color: Color(0xFFC48658)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Packages',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                      ),
                      Text(
                        '${widget.packages.length}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Payments & Promo
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.textPrimary),
                        title: const Text('Payments', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                        subtitle: Text(
                          _getPaymentLabel(),
                          style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        trailing: GestureDetector(
                          onTap: _showPaymentPicker,
                          child: const Text('Change or add', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.local_offer_rounded, color: AppColors.textPrimary),
                        title: const Text('Promo', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                        trailing: GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const PromotionsSelectionScreen(currentPromo: '')));
                          },
                          child: const Text('Add', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Fare details
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _estimate == null
                      ? const Center(child: CircularProgressIndicator())
                      : Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Total base fare', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                                Text('LKR ${(_estimate!['original_amount'] ?? _estimate!['final_amount'] ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Discount', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                                Text('LKR ${(_estimate!['discount'] ?? 0).toStringAsFixed(2)}', style: const TextStyle(fontSize: 14)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Text('Estimated fare', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                                    const SizedBox(width: 6),
                                    Icon(Icons.info_rounded, size: 16, color: AppColors.textPrimary.withOpacity(0.8)),
                                  ],
                                ),
                                Text(
                                  'LKR ${(_estimate!['final_amount'] ?? 0).toStringAsFixed(2)}',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'The final price may change after reweighing and size check',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                
                // T&C Checkbox
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED), // light orange bg
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _agreedToTerms,
                        onChanged: (val) {
                          setState(() {
                            _agreedToTerms = val ?? false;
                          });
                        },
                        activeColor: const Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: 'I confirm that I have read, consent and agree to the ',
                            style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                            children: [
                              TextSpan(
                                text: 'Terms and Conditions',
                                style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
          
          // Proceed button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: (_agreedToTerms && _estimate != null) ? _proceed : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCFD5DF),
                    disabledBackgroundColor: const Color(0xFFCFD5DF),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return const Color(0xFFCFD5DF);
                      }
                      return AppColors.primary;
                    }),
                  ),
                  child: _busy
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          'Proceed',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: (_agreedToTerms && _estimate != null) ? Colors.white : AppColors.textSecondary,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
