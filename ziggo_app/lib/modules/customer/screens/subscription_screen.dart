import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import '../wallet_provider.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  Map<String, dynamic>? _status;
  bool _busy = false;
  int _months = 1;

  @override
  void initState() {
    super.initState();
    _loadStatus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().refresh();
    });
  }

  Future<void> _loadStatus() async {
    try {
      final resp = await ApiClient.instance.dio.get('/gold/status');
      if (mounted) setState(() => _status = Map<String, dynamic>.from(resp.data));
    } on DioException {
      // ignore
    }
  }

  Future<void> _subscribe() async {
    setState(() => _busy = true);
    try {
      final resp = await ApiClient.instance.dio.post('/gold/subscribe', data: {'months': _months});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Activated Ziggo Gold until ${resp.data['expires_at'].toString().substring(0, 10)}'),
        ),
      );
      await _loadStatus();
      await context.read<WalletProvider>().refresh();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.response?.data?['detail']?.toString() ?? 'Subscription failed')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final pricePerMonth = ((_status?['price_per_month'] ?? 500) as num).toInt();
    final total = pricePerMonth * _months;
    final active = _status?['gold_member'] == true;
    final expires = _status?['expires_at']?.toString();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Ziggo Gold',
            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900)),
        iconTheme: const IconThemeData(color: AppColors.accent),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: staggered([
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.goldTierGradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.stars, size: 32, color: Colors.black),
                    const SizedBox(width: 8),
                    const Text('ZIGGO GOLD',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: 2)),
                    const Spacer(),
                    if (active)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('ACTIVE',
                            style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 11)),
                      ),
                  ],
                ),
                if (active && expires != null) ...[
                  const SizedBox(height: 10),
                  Text('Valid until ${expires.substring(0, 10)}',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('PREMIUM PERKS',
              style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 11)),
          const SizedBox(height: 10),
          ..._perks.map((p) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(p['icon'] as IconData, color: AppColors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(p['label'] as String,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 24),
          const Text('CHOOSE A PLAN',
              style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w900, letterSpacing: 1.2, fontSize: 11)),
          const SizedBox(height: 10),
          Row(
            children: [
              _planChip(1, '1 Month'),
              const SizedBox(width: 8),
              _planChip(3, '3 Months'),
              const SizedBox(width: 8),
              _planChip(6, '6 Months'),
              const SizedBox(width: 8),
              _planChip(12, '1 Year'),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Pay from wallet',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('Balance: Rs.${wallet.balance.toStringAsFixed(0)}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    ],
                  ),
                ),
                Text('Rs.$total',
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 18)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _busy ? null : _subscribe,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3))
                  : Text(active ? 'EXTEND ($_months month${_months > 1 ? 's' : ''}) • Rs.$total'
                      : 'GO GOLD • Rs.$total',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _planChip(int months, String label) {
    final sel = _months == months;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _months = months),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: sel ? AppColors.accent : Colors.white12,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                color: sel ? Colors.black : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              )),
        ),
      ),
    );
  }

  static const _perks = [
    {'icon': Icons.bolt, 'label': 'Priority driver matching'},
    {'icon': Icons.local_offer, 'label': 'Exclusive promo codes'},
    {'icon': Icons.support_agent, 'label': '24/7 premium support'},
    {'icon': Icons.percent, 'label': 'Lower platform fees'},
    {'icon': Icons.directions_car, 'label': 'Free ride cancellations'},
  ];
}
