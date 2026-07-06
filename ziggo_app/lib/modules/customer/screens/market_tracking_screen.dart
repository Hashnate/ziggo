import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../market_provider.dart';
import 'market_home_screen.dart';
import 'market_rating_screen.dart';
import '../../../core/network/ws_client.dart';
import '../../../core/network/api_client.dart';

// ─────────────────────────────────────────────
//  Market-order green color tokens
// ─────────────────────────────────────────────
const _kGreen = Color(0xFF22C55E);
const _kGreenDark = Color(0xFF16A34A);
const _kGreenLight = Color(0xFFDCFCE7);
const _kGreenGlow = Color(0x4422C55E);

class MarketTrackingScreen extends StatefulWidget {
  final String orderRef;
  const MarketTrackingScreen({super.key, required this.orderRef});

  @override
  State<MarketTrackingScreen> createState() => _MarketTrackingScreenState();
}

class _MarketTrackingScreenState extends State<MarketTrackingScreen> {
  Map<String, dynamic>? _order;
  Timer? _poll;
  String? _lastSeenStatus;
  StreamSubscription? _wsSub;
  bool _busy = false;

  String? _storeName;
  String? _storeAddress;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    _wsSub = WsClient.instance.events.listen((msg) {
      if (msg['event'] == 'market_order_update') {
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
    final orders = await context.read<MarketProvider>().fetchMyOrders();
    final match = orders.firstWhere(
      (o) => o['order_ref'] == widget.orderRef,
      orElse: () => <String, dynamic>{},
    );
    if (!mounted) return;
    final newStatus = match.isEmpty ? null : match['status']?.toString();
    if (_lastSeenStatus != null && newStatus != null && newStatus != _lastSeenStatus) {
      _showStatusToast(newStatus, match['cancellation_reason']?.toString());
    }
    _lastSeenStatus = newStatus;
    setState(() => _order = match.isEmpty ? null : match);
    
    if (_order != null) {
      if (_order!['status'] == 'rejected') {
        _showRejectedDialog();
      }
      if (_storeName == null) {
        _fetchStoreDetails(_order!['id'] as int);
      }
    }
  }

  Future<void> _fetchStoreDetails(int orderId) async {
    try {
      final res = await ApiClient.instance.dio.get('/market/orders/$orderId/details');
      final data = Map<String, dynamic>.from(res.data);
      if (mounted) {
        setState(() {
          _storeName = data['store_name']?.toString();
          _storeAddress = data['store_address']?.toString();
        });
      }
    } catch (_) {}
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
                'Your order was rejected by the store. If you paid via wallet, your amount has been refunded.',
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
                      MaterialPageRoute(builder: (_) => const MarketHomeScreen()),
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
      final ok = await context.read<MarketProvider>().cancelOrder(
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
            MaterialPageRoute(builder: (_) => const MarketHomeScreen()),
            (route) => route.isFirst,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    context.read<MarketProvider>().error ??
                        'Failed to cancel order.')),
          );
        }
      }
    }
  }

  void _showStatusToast(String status, String? reason) {
    String msg;
    Color color = AppColors.primary;
    IconData icon = Icons.info_rounded;
    switch (status) {
      case 'cancelled':
        msg = reason == null || reason.isEmpty
            ? 'Your order was cancelled by the store.'
            : 'Order cancelled: $reason';
        color = AppColors.error;
        icon = Icons.cancel_rounded;
        break;
      case 'confirmed':
        msg = 'The store accepted your order.';
        color = AppColors.success;
        icon = Icons.check_circle_rounded;
        break;
      case 'processing':
        msg = 'The store is packing your order.';
        color = _kGreen;
        icon = Icons.inventory_2_rounded;
        break;
      case 'ready_for_pickup':
        msg = 'Your order is ready — finding a rider.';
        color = _kGreenDark;
        icon = Icons.shopping_bag_rounded;
        break;
      case 'out_for_delivery':
        msg = 'A rider has picked up your order.';
        color = AppColors.warning;
        icon = Icons.delivery_dining_rounded;
        break;
      case 'delivered':
        msg = 'Order delivered. Enjoy!';
        color = AppColors.success;
        icon = Icons.done_all_rounded;
        break;
      default:
        return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(msg,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  static const List<_Step> _steps = [
    _Step('pending', 'Order placed', Icons.receipt_long_rounded),
    _Step('confirmed', 'Confirmed', Icons.check_circle_rounded),
    _Step('processing', 'Packing your order', Icons.inventory_2_rounded),
    _Step('ready_for_pickup', 'Ready for pickup', Icons.shopping_bag_rounded),
    _Step('out_for_delivery', 'Out for delivery', Icons.delivery_dining_rounded),
    _Step('delivered', 'Delivered', Icons.done_all_rounded),
  ];

  int _currentIndex(String status) {
    if (status == 'shipped') status = 'out_for_delivery';
    final i = _steps.indexWhere((s) => s.status == status);
    return i < 0 ? 0 : i;
  }

  Widget _cancelledView() {
    final reason = _order?['cancellation_reason']?.toString() ?? '';
    final amount = (_order!['final_amount'] as num? ?? 0).toDouble();
    final paymentMethod =
        (_order!['payment_method'] ?? '').toString().toUpperCase();
    final paymentStatus =
        (_order!['payment_status'] ?? '').toString().toLowerCase();
    final refunded = paymentStatus == 'refunded';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      children: staggered([
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFDC2626), Color(0xFFB91C1C)],
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
                    child: const Icon(Icons.cancel_rounded,
                        color: Colors.white, size: 24),
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
                            'ORDER CANCELLED',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'The store could not\nfulfil your order',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            letterSpacing: -0.3,
                            height: 1.15,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      'Rs.${amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      paymentMethod,
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
        const SizedBox(height: 18),
        if (reason.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REASON FROM THE STORE',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  reason,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: refunded
                ? AppColors.success.withOpacity(0.08)
                : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: refunded
                  ? AppColors.success.withOpacity(0.4)
                  : AppColors.cardBorder,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (refunded ? AppColors.success : AppColors.textTertiary)
                      .withOpacity(0.16),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  refunded
                      ? Icons.account_balance_wallet_rounded
                      : Icons.info_outline_rounded,
                  color: refunded ? AppColors.success : AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  refunded
                      ? 'Rs.${amount.toStringAsFixed(0)} has been refunded to your wallet.'
                      : paymentMethod == 'CASH'
                          ? 'No payment was taken — nothing to refund.'
                          : 'If you were charged, the refund will appear in your wallet shortly.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _order?['status']?.toString() ?? 'pending';
    final current = _currentIndex(status);
    final isCancelled = status == 'cancelled';
    final isDelivered = status == 'delivered';

    return Scaffold(
      backgroundColor: const Color(0xFFF2F6F3), // Light green-tinted background
      body: _order == null
          ? const Center(child: CircularProgressIndicator(color: _kGreen))
          : isCancelled
              ? Scaffold(
                  backgroundColor: AppColors.background,
                  appBar: AppBar(
                    backgroundColor: AppColors.background,
                    elevation: 0,
                    title: Text(widget.orderRef,
                        style: const TextStyle(letterSpacing: 0.4, fontWeight: FontWeight.w900)),
                  ),
                  body: _cancelledView(),
                )
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

                          // ── Delivery address / Pickup location card ──
                          _InfoCard(
                            icon: (_order!['is_self_pickup'] == true)
                                ? Icons.storefront_rounded
                                : Icons.location_on_rounded,
                            label: (_order!['is_self_pickup'] == true)
                                ? 'PICKUP LOCATION'
                                : 'DELIVERY ADDRESS',
                            value: (_order!['is_self_pickup'] == true)
                                ? (_storeAddress ?? 'At Store')
                                : (_order!['delivery_address']?.toString() ?? '—'),
                          ),
                          const SizedBox(height: 16),

                          // ── Market vendor name if present ──
                          if (_storeName != null && _order!['is_self_pickup'] != true) ...[
                            _InfoCard(
                              icon: Icons.storefront_rounded,
                              label: 'STORE',
                              value: _storeName!,
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

                          // ── Complete Self Pickup Order button ──
                          if (status == 'ready_for_pickup' && _order!['is_self_pickup'] == true) ...[
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: PrimaryButton(
                                label: 'I have picked up my order',
                                onPressed: _busy ? null : () async {
                                  final market = context.read<MarketProvider>();
                                  final orderId = _order?['id'] as int?;
                                  if (orderId != null) {
                                    setState(() => _busy = true);
                                    final ok = await market.completeOrder(orderId);
                                    if (mounted) {
                                      setState(() => _busy = false);
                                      if (ok) {
                                        _refresh();
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(market.error ?? 'Failed to complete order'),
                                            backgroundColor: AppColors.error,
                                          ),
                                        );
                                      }
                                    }
                                  }
                                },
                              ),
                            ),
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
                                      builder: (_) => MarketRatingScreen(
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

// Helper formatting function
String _formatRs(num? value) {
  return 'Rs.${(value ?? 0).toStringAsFixed(0)}';
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
            colors: [Color(0xFF062B14), Color(0xFF0F5A2B), _kGreenDark],
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
                          _formatRs(order['final_amount'] as num?),
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
                              color: _kGreen.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text(
                              'CURRENT STATUS',
                              style: TextStyle(
                                color: _kGreen,
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
                            const AlwaysStoppedAnimation<Color>(_kGreen),
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
    final steps = _MarketTrackingScreenState._steps;
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
                              ? _kGreen
                              : isActive
                                  ? _kGreen
                                  : AppColors.surfaceMuted,
                          boxShadow: isActive || isDone
                              ? [
                                  BoxShadow(
                                    color: _kGreenGlow,
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
                                  ? [_kGreen, _kGreen.withOpacity(0.4)]
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
                          if (s.status == 'delivered')
                            const Text(
                              'Completed',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _kGreenLight,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                '● In progress',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: _kGreenDark,
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
//  Info card (address / store)
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
              color: _kGreenLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: _kGreen, size: 20),
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
            colors: [_kGreenDark, _kGreen],
          ),
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          boxShadow: [
            BoxShadow(
              color: _kGreenGlow,
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

class _Step {
  final String status;
  final String label;
  final IconData icon;
  const _Step(this.status, this.label, this.icon);
}
