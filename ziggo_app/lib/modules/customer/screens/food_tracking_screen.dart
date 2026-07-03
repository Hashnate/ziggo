import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../food_provider.dart';
import '../food_ui.dart';
import 'food_home_screen.dart';
import 'food_rating_screen.dart';
import '../../../core/network/ws_client.dart';

// ─────────────────────────────────────────────
//  Food-order colour tokens
// ─────────────────────────────────────────────
const _kOrange = Color(0xFFFF7849);
const _kOrangeDark = Color(0xFFE8622E);
const _kOrangeLight = Color(0xFFFFEDE6);
const _kOrangeGlow = Color(0x44FF7849);

class FoodTrackingScreen extends StatefulWidget {
  final String orderRef;
  const FoodTrackingScreen({super.key, required this.orderRef});

  @override
  State<FoodTrackingScreen> createState() => _FoodTrackingScreenState();
}

class _FoodTrackingScreenState extends State<FoodTrackingScreen> {
  Map<String, dynamic>? _order;
  Timer? _poll;

  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _wsSub = WsClient.instance.events.listen((msg) {
      if (msg['event'] == 'order_update') {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final orders = await context.read<FoodProvider>().fetchMyOrders();
    final match = orders.firstWhere(
      (o) => o['order_ref'] == widget.orderRef,
      orElse: () => <String, dynamic>{},
    );
    if (mounted) {
      setState(() => _order = match.isEmpty ? null : match);
      if (_order != null && _order!['status'] == 'rejected') {
        _showRejectedDialog();
      }
    }
  }

  bool _isShowingRejectedDialog = false;

  void _showRejectedDialog() {
    if (_isShowingRejectedDialog) return;
    _isShowingRejectedDialog = true;
    _poll?.cancel();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusMd)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded,
                    color: AppColors.error, size: 40),
              ),
              const SizedBox(height: 20),
              const Text(
                'Order Rejected',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your order was rejected by the restaurant. If you paid via wallet, your amount has been refunded.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const FoodHomeScreen()),
                      (route) => route.isFirst,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppStyles.radiusSm)),
                    elevation: 0,
                  ),
                  child: const Text('BACK TO HOME',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCancelConfirmation(BuildContext context) async {
    final TextEditingController reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusMd)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.cancel_rounded,
                        color: AppColors.error, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text('Cancel Order',
                      style: TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 18)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Are you sure you want to cancel this order?\nThis action cannot be undone.',
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason (optional)',
                  hintText: 'e.g., changed my mind',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                    borderSide: const BorderSide(color: AppColors.cardBorder),
                  ),
                ),
                maxLength: 200,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppStyles.radiusSm)),
                      ),
                      child: const Text('KEEP ORDER',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: AppColors.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.error,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppStyles.radiusSm)),
                        elevation: 0,
                      ),
                      child: const Text('CANCEL',
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
            SnackBar(
                content: Text(
                    context.read<FoodProvider>().error ??
                        'Failed to cancel order.')),
          );
        }
      }
    }
  }

  static const List<_Step> _steps = [
    _Step('pending', 'Order Placed', Icons.receipt_long_rounded),
    _Step('confirmed', 'Confirmed', Icons.check_circle_rounded),
    _Step('preparing', 'Preparing Food', Icons.restaurant_menu_rounded),
    _Step('ready_for_pickup', 'Ready for Pickup', Icons.shopping_bag_rounded),
    _Step('out_for_delivery', 'Out for Delivery', Icons.delivery_dining_rounded),
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
    final isDelivered = status == 'delivered';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4F2),
      body: _order == null
          ? const Center(child: CircularProgressIndicator(color: _kOrange))
          : CustomScrollView(
              slivers: [
                _HeroHeader(
                  orderRef: widget.orderRef,
                  current: current,
                  steps: _steps,
                  order: _order!,
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // ── Progress steps card ──
                      _StepCard(current: current),
                      const SizedBox(height: 16),

                      // ── Delivery address card ──
                      _InfoCard(
                        icon: Icons.location_on_rounded,
                        label: 'DELIVERY ADDRESS',
                        value: _order!['delivery_address']?.toString() ?? '—',
                      ),
                      const SizedBox(height: 16),

                      // ── Restaurant name if present ──
                      if (_order!['restaurant_name'] != null) ...[
                        _InfoCard(
                          icon: Icons.storefront_rounded,
                          label: 'RESTAURANT',
                          value: _order!['restaurant_name'].toString(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Cancel button (only when pending) ──
                      if (status == 'pending') ...[
                        _CancelButton(
                          onPressed: () => _showCancelConfirmation(context),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // ── Done button (delivered) — goes to rating screen ──
                      if (isDelivered) ...[
                        _DoneButton(
                          onPressed: () {
                            final orderId = _order?['id'] as int?;
                            final orderRef = _order?['order_ref']?.toString() ?? widget.orderRef;
                            if (orderId != null) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FoodRatingScreen(
                                    orderId: orderId,
                                    orderRef: orderRef,
                                  ),
                                ),
                              );
                            } else {
                              Navigator.popUntil(context, (r) => r.isFirst);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
//  Sliver hero header
// ─────────────────────────────────────────────
class _HeroHeader extends StatelessWidget {
  final String orderRef;
  final int current;
  final List<_Step> steps;
  final Map<String, dynamic> order;

  const _HeroHeader({
    required this.orderRef,
    required this.current,
    required this.steps,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (current + 1) / steps.length;

    return SliverToBoxAdapter(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A0A05), Color(0xFF3D1A0A), _kOrangeDark],
          ),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(36),
            bottomRight: Radius.circular(36),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white, size: 20),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ORDER TRACKING',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.6,
                            ),
                          ),
                          Text(
                            orderRef,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Amount + payment chip
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatRs(order['final_amount'] as num?),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            (order['payment_method'] ?? '').toString().toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Status icon + label
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Status icon
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3), width: 1.5),
                      ),
                      child: Icon(steps[current].icon,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _kOrange.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text(
                              'CURRENT STATUS',
                              style: TextStyle(
                                color: _kOrange,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            steps[current].label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            steps[current].status == 'delivered'
                                ? '✓ Your order has been delivered!'
                                : 'In progress · Step ${current + 1} of ${steps.length}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(progress * 100).round()}% complete',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${current + 1}/${steps.length} steps',
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(100),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: Colors.white.withOpacity(0.15),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(_kOrange),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Step timeline card
// ─────────────────────────────────────────────
class _StepCard extends StatelessWidget {
  final int current;

  const _StepCard({required this.current});

  @override
  Widget build(BuildContext context) {
    final steps = _FoodTrackingScreenState._steps;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ORDER PROGRESS',
            style: TextStyle(
              fontSize: 10,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(steps.length, (i) {
            final s = steps[i];
            final isDone = i < current;
            final isActive = i == current;
            final isUpcoming = i > current;
            final isLast = i == steps.length - 1;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon + connector
                SizedBox(
                  width: 44,
                  child: Column(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? _kOrange
                              : isActive
                                  ? _kOrange
                                  : AppColors.surfaceMuted,
                          boxShadow: isActive || isDone
                              ? [
                                  BoxShadow(
                                    color: _kOrangeGlow,
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : null,
                        ),
                        child: Icon(
                          isDone ? Icons.check_rounded : s.icon,
                          color: isUpcoming
                              ? AppColors.textTertiary
                              : Colors.white,
                          size: isDone ? 18 : 17,
                        ),
                      ),
                      if (!isLast)
                        Container(
                          width: 2.5,
                          height: 36,
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: isDone
                                  ? [_kOrange, _kOrange.withOpacity(0.4)]
                                  : [
                                      AppColors.divider,
                                      AppColors.divider,
                                    ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Label + subtitle
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        top: 8, bottom: isLast ? 8 : 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.label,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: isUpcoming
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(height: 3),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _kOrangeLight,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text(
                              '● In progress',
                              style: TextStyle(
                                fontSize: 10,
                                color: _kOrangeDark,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ] else if (isDone) ...[
                          const SizedBox(height: 3),
                          const Text(
                            'Completed',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Info card (address / restaurant)
// ─────────────────────────────────────────────
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _kOrangeLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _kOrange, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Cancel button
// ─────────────────────────────────────────────
class _CancelButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _CancelButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          border: Border.all(color: AppColors.error.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.cancel_rounded, color: AppColors.error, size: 20),
            SizedBox(width: 8),
            Text(
              'CANCEL ORDER',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Done button
// ─────────────────────────────────────────────
class _DoneButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _DoneButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kOrangeDark, _kOrange],
          ),
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          boxShadow: [
            BoxShadow(
              color: _kOrangeGlow,
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text(
              'DONE — GO HOME',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Data class
// ─────────────────────────────────────────────
class _Step {
  final String status;
  final String label;
  final IconData icon;
  const _Step(this.status, this.label, this.icon);
}
