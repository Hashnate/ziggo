import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../driver_theme.dart';
import '../../../core/utils/amount_format.dart';

/// Bonus wallet: money Ziggo gave the driver. It pays their commission
/// automatically until each bonus expires and can't be withdrawn.
class DriverWalletScreen extends StatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  State<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends State<DriverWalletScreen> {
  Map<String, dynamic>? _wallet;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await ApiClient.instance.dio.get('/driver/wallet');
      if (!mounted) return;
      setState(() {
        _wallet = Map<String, dynamic>.from(res.data);
        _error = null;
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.response?.data?['detail']?.toString() ??
            'Could not load your wallet. Pull down to retry.';
        _loading = false;
      });
    }
  }

  double _d(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;

  String _rs(double v) => 'Rs.${formatAmount(v, 2)}';

  String _day(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '—' : DateFormat('d MMM yyyy').format(d);
  }

  String _when(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    return d == null ? '' : DateFormat('d MMM yyyy, hh:mm a').format(d.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: driverTheme(context),
      child: Scaffold(
        backgroundColor: kDriverBg,
        appBar: AppBar(
          backgroundColor: kDriverBg,
          elevation: 0,
          title: const Text('Bonus wallet'),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, 30 + MediaQuery.of(context).padding.bottom),
            children: _loading
                ? const [
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 60),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ]
                : _wallet == null
                    ? [_note(_error ?? 'Could not load your wallet.')]
                    : _content(_wallet!),
          ),
        ),
      ),
    );
  }

  List<Widget> _content(Map<String, dynamic> w) {
    final credits = (w['credits'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final payments = (w['payments'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final due = _d(w, 'commission_due');
    return [
      _hero(w),
      const SizedBox(height: 12),
      if (due > 0) ...[
        _note('Commission still due: ${_rs(due)}. Your bonus money was not enough to cover it.',
            color: AppColors.error),
        const SizedBox(height: 12),
      ],
      _howItWorks(),
      const SizedBox(height: 24),
      _heading('YOUR BONUSES'),
      const SizedBox(height: 10),
      if (credits.isEmpty)
        _note('No bonus yet. When Ziggo gives you one, it shows here.')
      else
        ...credits.map(_creditCard),
      if (payments.isNotEmpty) ...[
        const SizedBox(height: 24),
        _heading('COMMISSION PAID FROM YOUR WALLET'),
        const SizedBox(height: 10),
        _paymentsCard(payments),
      ],
    ];
  }

  Widget _hero(Map<String, dynamic> w) {
    final next = w['next_expiry'] is Map
        ? Map<String, dynamic>.from(w['next_expiry'])
        : null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.bonus, AppColors.primary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AVAILABLE FOR COMMISSION',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _rs(_d(w, 'available')),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
            ),
          ),
          if (next != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_rs(_d(next, 'amount'))} can be used until ${_day(next['date']?.toString())}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _howItWorks() {
    const lines = [
      'Pays the commission you owe Ziggo automatically, after each trip.',
      'The bonus ending soonest is used first.',
      'It can\'t be withdrawn as cash.',
      'Anything left after the end date is lost.',
    ];
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
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.check_circle_rounded,
                        size: 15, color: AppColors.bonus),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
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

  Widget _creditCard(Map<String, dynamic> c) {
    final status = c['status']?.toString() ?? '';
    final active = status == 'active';
    final daysLeft = ((c['days_left'] as num?)?.toInt() ?? 0) + 1;
    final (label, color) = switch (status) {
      'active' => ('$daysLeft day${daysLeft == 1 ? '' : 's'} left', AppColors.bonus),
      'used' => ('Used up', AppColors.success),
      'expired' => ('Expired', AppColors.textTertiary),
      _ => ('Removed', AppColors.error),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              Expanded(
                child: Text(
                  (c['note'] ?? 'Bonus').toString(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            active
                ? 'Use until ${_day(c['expires_on']?.toString())}'
                : 'Ended ${_day(c['expires_on']?.toString())}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _figure('Given', _rs(_d(c, 'amount')), AppColors.textPrimary),
              _figure('Used', _rs(_d(c, 'used')), AppColors.warning),
              _figure('Left', _rs(_d(c, 'remaining')),
                  active ? AppColors.bonus : AppColors.textTertiary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _figure(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentsCard(List<Map<String, dynamic>> payments) {
    return Container(
      decoration: BoxDecoration(
        color: kDriverCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          for (var i = 0; i < payments.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            ListTile(
              dense: true,
              leading: const Icon(Icons.receipt_long_rounded,
                  color: AppColors.bonus),
              title: const Text(
                'Commission paid',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              subtitle: Text(
                _when(payments[i]['at']?.toString()),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              trailing: Text(
                '-${_rs(_d(payments[i], 'amount'))}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heading(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontWeight: FontWeight.w900,
        fontSize: 11,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _note(String text, {Color color = AppColors.textSecondary}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kDriverCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
