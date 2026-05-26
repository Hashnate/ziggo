import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/ambient_orbs.dart';
import '../../../core/widgets/animated_counter.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/motion.dart';
import '../wallet_provider.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().refresh();
    });
  }

  Future<void> _topUp(BuildContext context, double amount) async {
    // Goes through PayHere when the server has merchant credentials,
    // automatically falls back to the dev mock when it doesn't.
    final error = await context.read<WalletProvider>().topUpViaPayHere(amount);
    if (!mounted) return;
    final ok = error == null;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Added Rs.${amount.toStringAsFixed(0)} to wallet'
            : error),
        backgroundColor: ok ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _customTopUp(BuildContext context) async {
    final controller = TextEditingController(text: '500');
    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const Text('Enter amount',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                decoration: const InputDecoration(
                  prefixText: 'Rs. ',
                  prefixStyle: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text) ?? 0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text('TOP UP',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
    if (amount != null && amount > 0 && mounted) {
      await _topUp(context, amount);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WalletProvider>();
    final fmt = NumberFormat.currency(symbol: 'Rs.', decimalDigits: 2);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Wallet'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<WalletProvider>().refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: staggered([
            // Premium hero card with ambient orbs + shimmer + glass border
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                children: [
                  // Base dark gradient
                  Container(
                    height: 260,
                    decoration: const BoxDecoration(gradient: AppColors.blackGradient),
                  ),
                  // Drifting blue + gold orbs in the background
                  const Positioned.fill(
                    child: AmbientOrbs(
                      colors: [
                        AppColors.primaryLight,
                        AppColors.accent,
                        AppColors.primary,
                      ],
                    ),
                  ),
                  // Premium shimmer highlight that sweeps across
                  const Positioned(
                    top: 0, left: 0, right: 0,
                    child: ShimmerHighlight(height: 260),
                  ),
                  // Foreground content (glass-tinted)
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                      boxShadow: AppStyles.shadowLg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(color: Colors.white.withOpacity(0.18)),
                              ),
                              child: const Text(
                                'ZIGGO WALLET',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: 36,
                              height: 36,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.account_balance_wallet_rounded,
                                  color: AppColors.accent, size: 18),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          'Available balance',
                          style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            AnimatedCounter(
                              value: w.balance,
                              prefix: 'Rs.',
                              decimals: 2,
                              duration: const Duration(milliseconds: 900),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.5,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _customTopUp(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_rounded, color: Colors.white, size: 20),
                                SizedBox(width: 4),
                                Text('Top up',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    )),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.send_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text('Send',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  )),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Quick top up amounts
            const Text(
              'Quick top up',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w900, letterSpacing: 1.4),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final amt in const [200, 500, 1000, 2000])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => _topUp(context, amt.toDouble()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: Text(
                            'Rs.$amt',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            // Transactions header
            Row(
              children: [
                const Text(
                  'Recent activity',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const Spacer(),
                if (w.transactions.isNotEmpty)
                  Text(
                    '${w.transactions.length} entries',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (w.transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.receipt_long_rounded,
                            color: AppColors.textTertiary, size: 36),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No transactions yet',
                        style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ...w.transactions.map((t) {
              final isCredit = t['type'] == 'credit';
              final amount = (t['amount'] as num).toDouble();
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (isCredit ? AppColors.success : AppColors.error).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        color: isCredit ? AppColors.success : AppColors.error,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t['description']?.toString() ?? 'Transaction',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            t['created_at']?.toString().substring(0, 16) ?? '',
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${isCredit ? '+' : '-'} ${fmt.format(amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isCredit ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ]),
        ),
      ),
    );
  }
}
