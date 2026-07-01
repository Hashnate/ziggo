import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../restaurant_provider.dart';

class RestaurantCommissionScreen extends StatefulWidget {
  const RestaurantCommissionScreen({super.key});

  @override
  State<RestaurantCommissionScreen> createState() =>
      _RestaurantCommissionScreenState();
}

class _RestaurantCommissionScreenState
    extends State<RestaurantCommissionScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = context.read<RestaurantProvider>();
    final result = await p.fetchCommission();
    if (!mounted) return;
    setState(() {
      _data = result;
      _loading = false;
    });
  }

  Future<void> _payCommission() async {
    final outstanding =
        (_data?['outstanding_amount'] as num? ?? 0).toDouble();
    if (outstanding <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.account_balance_wallet_rounded,
            color: AppColors.primary, size: 40),
        title: const Text('Pay Commission',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900)),
        content: Text(
          'You are about to pay Rs.${NumberFormat('#,##0').format(outstanding.round())} in commission to Ziggo Admin via PayHere.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: AppColors.textSecondary, fontWeight: FontWeight.w600),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.surfaceMuted,
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100)),
                  ),
                  child: const Text('Cancel',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(100)),
                  ),
                  child: const Text('Pay Now',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _paying = true);
    final p = context.read<RestaurantProvider>();
    final err = await p.payCommission(context, outstanding);
    if (!mounted) return;
    setState(() => _paying = false);

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.white),
            SizedBox(width: 10),
            Text('Commission paid successfully!',
                style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ));
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Commission',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_rounded,
                          size: 48, color: AppColors.textTertiary),
                      const SizedBox(height: 12),
                      const Text("Couldn't load commission data",
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: staggered([
                      _CommissionHeroCard(
                        data: _data!,
                        paying: _paying,
                        onPay: _payCommission,
                      ),
                      const SizedBox(height: 16),
                      _CommissionBreakdown(data: _data!),
                      const SizedBox(height: 18),
                      _PaymentHistory(data: _data!),
                    ]),
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card — outstanding balance + Pay button
// ─────────────────────────────────────────────────────────────────────────────
class _CommissionHeroCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool paying;
  final VoidCallback onPay;

  const _CommissionHeroCard({
    required this.data,
    required this.paying,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final outstanding =
        (data['outstanding_amount'] as num? ?? 0).toDouble();
    final adminOwesVendor =
        (data['admin_owes_vendor'] as num? ?? 0).toDouble();
    final rate = (data['commission_rate'] as num? ?? 0).toDouble();
    final hasDebt = outstanding > 0;
    final adminHasDebt = adminOwesVendor > 0;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: hasDebt
              ? const [Color(0xFF7F1D1D), Color(0xFFB91C1C), Color(0xFFEF4444)]
              : adminHasDebt 
                  ? const [Color(0xFF1E3A8A), Color(0xFF2563EB), Color(0xFF3B82F6)] // Blue for incoming settlement
                  : const [Color(0xFF14532D), Color(0xFF15803D), Color(0xFF22C55E)],
        ),
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        boxShadow: AppStyles.shadowLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  hasDebt ? 'OUTSTANDING COMMISSION' : (adminHasDebt ? 'INCOMING SETTLEMENT' : 'ALL CLEAR'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  'Rate: ${rate.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Rs.${NumberFormat('#,##0').format(adminHasDebt ? adminOwesVendor.round() : outstanding.round())}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            hasDebt
                ? 'Commission payable to Ziggo Admin'
                : adminHasDebt
                    ? 'Settlement incoming from Ziggo Admin'
                    : 'No outstanding commission — you\'re up to date!',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (hasDebt) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: paying ? null : onPay,
                icon: paying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFB91C1C)),
                      )
                    : const Icon(Icons.account_balance_wallet_rounded,
                        size: 18),
                label: Text(
                  paying ? 'Processing...' : 'Pay Commission Now',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB91C1C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Breakdown grid — total sales, total commission owed, total paid
// ─────────────────────────────────────────────────────────────────────────────
class _CommissionBreakdown extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CommissionBreakdown({required this.data});

  @override
  Widget build(BuildContext context) {
    final totalSales = (data['total_sales'] as num? ?? 0).toDouble();
    final totalOwed = (data['total_commission_owed'] as num? ?? 0).toDouble();
    final totalPaid = (data['total_paid'] as num? ?? 0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Summary',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: -0.3),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _InfoTile(
                icon: Icons.point_of_sale_rounded,
                color: AppColors.primary,
                label: 'TOTAL SALES',
                value:
                    'Rs.${NumberFormat('#,##0').format(totalSales.round())}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoTile(
                icon: Icons.receipt_long_rounded,
                color: AppColors.warning,
                label: 'COMMISSION OWED',
                value:
                    'Rs.${NumberFormat('#,##0').format(totalOwed.round())}',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _InfoTile(
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                label: 'TOTAL PAID',
                value:
                    'Rs.${NumberFormat('#,##0').format(totalPaid.round())}',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(
                fontSize: 9,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Payment history list
// ─────────────────────────────────────────────────────────────────────────────
class _PaymentHistory extends StatelessWidget {
  final Map<String, dynamic> data;
  const _PaymentHistory({required this.data});

  @override
  Widget build(BuildContext context) {
    final payments =
        (data['payments'] as List? ?? []).cast<Map<String, dynamic>>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Payment History',
            style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                letterSpacing: -0.3),
          ),
        ),
        if (payments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              boxShadow: AppStyles.shadowSm,
            ),
            child: const Column(
              children: [
                Icon(Icons.history_rounded,
                    size: 40, color: AppColors.textTertiary),
                SizedBox(height: 8),
                Text(
                  'No payments made yet',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              boxShadow: AppStyles.shadowSm,
            ),
            child: Column(
              children: [
                for (var i = 0; i < payments.length; i++) ...[
                  _PaymentRow(payment: payments[i]),
                  if (i != payments.length - 1)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final Map<String, dynamic> payment;
  const _PaymentRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    final iso = payment['paid_at']?.toString() ?? '';
    DateTime? parsed;
    try {
      parsed = DateTime.parse(iso);
    } catch (_) {}
    final dateLabel = parsed == null
        ? iso
        : DateFormat('EEE, MMM d \u2022 h:mm a').format(parsed);
    final amount = (payment['amount'] as num? ?? 0).toDouble();
    final method = payment['method']?.toString() ?? 'Wallet';
    final ref = payment['reference']?.toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: AppColors.success, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 13),
                ),
                Text(
                  ref != null ? '$method \u2022 $ref' : method,
                  style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '- Rs.${NumberFormat('#,##0').format(amount.round())}',
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: AppColors.success),
          ),
        ],
      ),
    );
  }
}
