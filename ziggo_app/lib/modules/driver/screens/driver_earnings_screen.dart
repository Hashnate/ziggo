import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../customer/payment_methods_provider.dart';
import '../../customer/screens/payment_methods_screen.dart';
import '../driver_provider.dart';
import '../driver_theme.dart';
import 'driver_history_screen.dart';

/// Driver earnings page — payout summary plus a transparent "how your fare is
/// calculated" rate card (live from the admin fare settings) with a worked
/// example so the driver sees exactly how their share is computed.
class DriverEarningsScreen extends StatefulWidget {
  const DriverEarningsScreen({super.key});

  @override
  State<DriverEarningsScreen> createState() => _DriverEarningsScreenState();
}

class _DriverEarningsScreenState extends State<DriverEarningsScreen> {
  Map<String, dynamic>? _fareCard;
  Map<String, dynamic>? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        ApiClient.instance.dio.get('/driver/earnings-summary'),
        ApiClient.instance.dio.get('/driver/fare-card'),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(results[0].data);
        _fareCard = Map<String, dynamic>.from(results[1].data);
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _handleSettleCommission(double commissionAmount) async {
    final provider = context.read<PaymentMethodsProvider>();
    setState(() => _loading = true);
    await provider.fetchCards();
    setState(() => _loading = false);

    if (!mounted) return;

    final selectedCard = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final p = context.watch<PaymentMethodsProvider>();
          return Container(
            decoration: const BoxDecoration(
              color: kDriverBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: EdgeInsets.fromLTRB(16, 20, 16, 24 + MediaQuery.of(context).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Settle Commission Payment',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Amount due: Rs.${commissionAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (p.cards.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: kDriverCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.credit_card_rounded, color: AppColors.textTertiary, size: 40),
                        SizedBox(height: 8),
                        Text(
                          'No cards added yet',
                          style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  )
                else ...[
                  const Text(
                    'SELECT A SAVED CARD',
                    style: TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 10),
                  ...p.cards.map((c) {
                    final String cardNo = c['card_no'] ?? '';
                    final String last4 = cardNo.length > 4 ? cardNo.substring(cardNo.length - 4) : cardNo;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: kDriverCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.credit_card_rounded, color: AppColors.primary),
                        title: Text('${c['card_type'] ?? 'Card'} ending in $last4'),
                        subtitle: Text('Expires: ${c['card_expiry']}'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.pop(ctx, c),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PaymentMethodsScreen()),
                    );
                    await provider.fetchCards();
                    setSheetState(() {});
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add new card'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (selectedCard == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Payment', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 48),
            const SizedBox(height: 16),
            Text(
              'Confirm payment of Rs.${commissionAmount.toStringAsFixed(2)} from your card ending in ${selectedCard['card_no'].toString().substring(selectedCard['card_no'].toString().length - 4)}?',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Confirm Pay'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      await ApiClient.instance.dio.post(
        '/driver/settle-commission',
        data: {'card_id': selectedCard['id']},
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Commission of Rs.${commissionAmount.toStringAsFixed(2)} settled successfully.'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to settle commission. Please try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<bool?> _showConnectBankDialog() async {
    final formKey = GlobalKey<FormState>();
    final bankName = TextEditingController();
    final accountHolder = TextEditingController();
    final accountNumber = TextEditingController();
    final branchName = TextEditingController();
    bool busy = false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: kDriverCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: const [
              Icon(Icons.account_balance_rounded, color: AppColors.primary, size: 24),
              SizedBox(width: 10),
              Text('Connect Bank Account', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ],
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'To settle commission payouts, please connect your bank account details below.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: bankName,
                    decoration: const InputDecoration(
                      labelText: 'Bank Name',
                      hintText: 'e.g. Commercial Bank',
                      prefixIcon: Icon(Icons.business_rounded, size: 18),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: accountHolder,
                    decoration: const InputDecoration(
                      labelText: 'Account Holder Name',
                      hintText: 'e.g. A.B.C. Perera',
                      prefixIcon: Icon(Icons.person_rounded, size: 18),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: accountNumber,
                    decoration: const InputDecoration(
                      labelText: 'Account Number',
                      hintText: 'e.g. 1020304050',
                      prefixIcon: Icon(Icons.tag_rounded, size: 18),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: branchName,
                    decoration: const InputDecoration(
                      labelText: 'Branch Name',
                      hintText: 'e.g. Colombo Fort',
                      prefixIcon: Icon(Icons.location_on_rounded, size: 18),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => busy = true);
                      final ok = await context.read<DriverProvider>().updateBankDetails(
                            bankName: bankName.text.trim(),
                            accountHolderName: accountHolder.text.trim(),
                            accountNumber: accountNumber.text.trim(),
                            branchName: branchName.text.trim(),
                          );
                      setState(() => busy = false);
                      if (ok) {
                        Navigator.pop(ctx, true);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to save bank details. Please try again.'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save & Connect'),
            ),
          ],
        ),
      ),
    );
  }

  double _d(Map<String, dynamic> m, String k) =>
      (m[k] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: driverTheme(context),
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final profile =
        context.watch<DriverProvider>().profile ?? const <String, dynamic>{};
    final total = _summary != null ? _d(_summary!, 'earnings') : ((profile['total_earnings'] as num?)?.toDouble() ?? 0);
    final today = (profile['today_earnings'] as num?)?.toDouble() ?? 0;
    final trips = (profile['today_rides'] as num?)?.toInt() ?? 0;
    final paid = (profile['paid_payouts'] as num?)?.toDouble() ?? 0;
    final pending = (profile['pending_payout'] as num?)?.toDouble() ?? 0;
    final outstanding = _summary != null ? _d(_summary!, 'outstanding_commission') : 0.0;

    return Scaffold(
      backgroundColor: kDriverBg,
      appBar: AppBar(
        backgroundColor: kDriverBg,
        elevation: 0,
        title: const Text('Earnings'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 30 + MediaQuery.of(context).padding.bottom),
          children: [
            // Lifetime hero
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIFETIME EARNINGS',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Rs.${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (outstanding > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'COMMISSION DUE',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Rs.${outstanding.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _tile('Today', 'Rs.${today.toStringAsFixed(0)}',
                      Icons.today_rounded, AppColors.success),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _tile('Trips today', trips.toString(),
                      Icons.directions_car_rounded, AppColors.info),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _tile('Paid out', 'Rs.${paid.toStringAsFixed(0)}',
                      Icons.payments_rounded, kDriverGold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _tile(
                      'Pending payout',
                      'Rs.${pending.toStringAsFixed(0)}',
                      Icons.hourglass_empty_rounded,
                      AppColors.warning),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'LIFETIME BREAKDOWN',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _breakdownCard(_summary),
            const SizedBox(height: 24),
            const Text(
              'HOW YOUR FARE IS CALCULATED',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w900,
                fontSize: 11,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_fareCard == null)
              _infoCard(
                  'Could not load your rate card. Pull down to retry.')
            else
              _fareCardView(_fareCard!),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const DriverHistoryScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_rounded,
                        color: AppColors.primary, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'View per-trip breakdowns',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kDriverCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  Widget _breakdownCard(Map<String, dynamic>? s) {
    if (s == null) {
      return _infoCard('Could not load your earnings. Pull down to retry.');
    }
    final collected = _d(s, 'collected');
    final commission = _d(s, 'commission');
    final outstanding = _d(s, 'outstanding_commission');
    final earnings = _d(s, 'earnings');
    final paid = _d(s, 'paid');
    final pending = _d(s, 'pending');
    final trips = (s['trips'] as num?)?.toInt() ?? 0;
    final maxSettle = s['max_settle_amount'] != null ? _d(s, 'max_settle_amount') : 1000.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kDriverCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL COLLECTED',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rs.${collected.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 26,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                '$trips trips',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: AppColors.divider),
          _rateRow('Admin commission', 'Rs.${commission.toStringAsFixed(2)}',
              negative: true),
          _rateRow('Driver earnings', 'Rs.${earnings.toStringAsFixed(2)}',
              highlight: true),
          const Divider(height: 24, color: AppColors.divider),
          _rateRow('Paid out', 'Rs.${paid.toStringAsFixed(2)}'),
          _rateRow('Pending payout', 'Rs.${pending.toStringAsFixed(2)}'),
          const SizedBox(height: 14),
          Row(
            children: [
              if (outstanding > 0)
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleSettleCommission(outstanding),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.error.withOpacity(0.24),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.payment_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Settle (-Rs.${outstanding.toStringAsFixed(0)})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (outstanding > 0 && pending >= 0) const SizedBox(width: 8),
              if (pending >= 0)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.24),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Pending (+Rs.${pending.toStringAsFixed(0)})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.divider.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.textTertiary,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Maximum settle commission amount is Rs.${maxSettle.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kDriverCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _fareCardView(Map<String, dynamic> c) {
    final driverShare = _d(c, 'driver_share_percent');
    final platformPct = _d(c, 'platform_fee_percent');
    final surge = _d(c, 'surge_multiplier');
    final pickup = _d(c, 'pickup_fee');
    final boost = _d(c, 'boost');
    final passDeduct = _d(c, 'passenger_deductible');
    final example = (c['example'] as Map?)?.cast<String, dynamic>();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kDriverCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  (c['display_name'] ?? c['service_type'] ?? '')
                      .toString()
                      .toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                'You keep ${driverShare.toStringAsFixed(1).replaceAll('.0', '')}%',
                style: const TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _rateRow('Base fare', 'Rs.${_d(c, 'base_fare').toStringAsFixed(2)}'),
          _rateRow('Per kilometre',
              'Rs.${_d(c, 'per_km_rate').toStringAsFixed(2)}'),
          _rateRow('Per minute',
              'Rs.${_d(c, 'per_minute_rate').toStringAsFixed(2)}'),
          _rateRow('Minimum fare',
              'Rs.${_d(c, 'min_fare').toStringAsFixed(2)}'),
          if (pickup > 0)
            _rateRow('Pickup fee', 'Rs.${pickup.toStringAsFixed(2)}'),
          if (boost > 0)
            _rateRow('Boost (100% yours)', 'Rs.${boost.toStringAsFixed(2)}'),
          if (passDeduct > 0)
            _rateRow('Passenger deductible',
                'Rs.${passDeduct.toStringAsFixed(2)}'),
          if (surge != 1.0)
            _rateRow('Surge multiplier', '×${surge.toStringAsFixed(2)}'),
          const Divider(height: 22, color: AppColors.divider),
          _rateRow('App usage charge (commission)',
              '${platformPct.toStringAsFixed(1).replaceAll('.0', '')}%',
              negative: true),
          _rateRow('Your share', '${driverShare.toStringAsFixed(1).replaceAll('.0', '')}%',
              highlight: true),
          if (example != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kDriverCardLight,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EXAMPLE — ${(_d(example, 'distance_km')).toStringAsFixed(0)} km · '
                    '${(_d(example, 'duration_min')).toStringAsFixed(0)} min trip',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _rateRow('Gross fare',
                      'Rs.${_d(example, 'gross_total').toStringAsFixed(2)}'),
                  _rateRow('− App usage charge',
                      'Rs.${_d(example, 'platform_fee').toStringAsFixed(2)}',
                      negative: true),
                  const Divider(height: 18, color: AppColors.divider),
                  _rateRow('You earn',
                      'Rs.${_d(example, 'driver_earnings').toStringAsFixed(2)}',
                      highlight: true),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rateRow(String label, String value,
      {bool negative = false, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: highlight ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: highlight ? FontWeight.w900 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: negative
                  ? AppColors.error
                  : (highlight ? AppColors.success : AppColors.textPrimary),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
