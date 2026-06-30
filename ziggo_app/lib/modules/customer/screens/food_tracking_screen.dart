import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../food_provider.dart';
import '../food_ui.dart';
import 'food_home_screen.dart';

class FoodTrackingScreen extends StatefulWidget {
  final String orderRef;
  const FoodTrackingScreen({super.key, required this.orderRef});

  @override
  State<FoodTrackingScreen> createState() => _FoodTrackingScreenState();
}

class _FoodTrackingScreenState extends State<FoodTrackingScreen> {
  Map<String, dynamic>? _order;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final orders = await context.read<FoodProvider>().fetchMyOrders();
    final match = orders.firstWhere(
      (o) => o['order_ref'] == widget.orderRef,
      orElse: () => <String, dynamic>{},
    );
    if (mounted) setState(() => _order = match.isEmpty ? null : match);
  }

  Future<void> _showCancelConfirmation(BuildContext context) async {
    final TextEditingController reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppStyles.radiusMd)),
        title: const Text('Cancel Order', style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to cancel this order? This action cannot be undone.'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for cancellation',
                hintText: 'e.g., changed my mind, wrong items',
                border: OutlineInputBorder(),
              ),
              maxLength: 200,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NO', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('YES, CANCEL', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final orderId = _order?['id'] as int?;
      if (orderId == null) return;
      final reason = reasonController.text.trim();
      final ok = await context.read<FoodProvider>().cancelOrder(
            orderId,
            reason: reason.isNotEmpty ? reason : 'Customer cancelled the order',
          );
      if (mounted) {
        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order cancelled successfully.')),
          );
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const FoodHomeScreen()),
            (route) => route.isFirst,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.read<FoodProvider>().error ?? 'Failed to cancel order.')),
          );
        }
      }
    }
  }

  static const List<_Step> _steps = [
    _Step('pending', 'Order placed', Icons.receipt_long_rounded),
    _Step('confirmed', 'Confirmed', Icons.check_circle_rounded),
    _Step('preparing', 'Preparing your food', Icons.restaurant_menu_rounded),
    _Step('ready_for_pickup', 'Ready for pickup', Icons.shopping_bag_rounded),
    _Step('out_for_delivery', 'Out for delivery', Icons.delivery_dining_rounded),
    _Step('delivered', 'Delivered', Icons.done_all_rounded),
  ];

  int _currentIndex(String status) {
    final i = _steps.indexWhere((s) => s.status == status);
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    final status = _order?['status']?.toString() ?? 'pending';
    final current = _currentIndex(status);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(widget.orderRef,
            style: const TextStyle(letterSpacing: 0.4, fontWeight: FontWeight.w900)),
      ),
      body: _order == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              children: staggered([
                // Hero status card
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF172554), Color(0xFF1E40AF), Color(0xFF3B82F6)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: AppStyles.shadowLg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(_steps[current].icon, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.22),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: const Text(
                                    'CURRENT STATUS',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _steps[current].label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 18,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              formatRs(_order!['final_amount'] as num?),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              (_order!['payment_method'] ?? '').toString().toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Step list with connecting line
                _StepList(current: current),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                    boxShadow: AppStyles.shadowSm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DELIVERY ADDRESS',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.location_on_rounded,
                                color: AppColors.primary, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _order!['delivery_address']?.toString() ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (status == 'pending') ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _showCancelConfirmation(context),
                    icon: const Icon(Icons.cancel_rounded, color: Colors.white),
                    label: const Text(
                      'CANCEL ORDER',
                      style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                      ),
                    ),
                  ),
                ],
                if (status == 'delivered') ...[
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: 'DONE',
                    icon: Icons.check_circle_rounded,
                    gold: true,
                    onPressed: () {
                      Navigator.popUntil(context, (r) => r.isFirst);
                    },
                  ),
                ],
              ]),
            ),
    );
  }
}

class _StepList extends StatelessWidget {
  final int current;
  const _StepList({required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        children: List.generate(_FoodTrackingScreenState._steps.length, (i) {
          final s = _FoodTrackingScreenState._steps[i];
          final done = i <= current;
          final isLast = i == _FoodTrackingScreenState._steps.length - 1;
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: done ? AppColors.primary : AppColors.surfaceMuted,
                        shape: BoxShape.circle,
                        boxShadow: done
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withOpacity(0.35),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        s.icon,
                        color: done ? Colors.white : AppColors.textTertiary,
                        size: 18,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 3,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: i < current ? AppColors.primary : AppColors.divider,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: done ? AppColors.textPrimary : AppColors.textTertiary,
                          ),
                        ),
                        if (i == current)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              s.status == 'delivered' ? 'Completed' : 'In progress...',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.3,
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
        }),
      ),
    );
  }
}

class _Step {
  final String status;
  final String label;
  final IconData icon;
  const _Step(this.status, this.label, this.icon);
}
