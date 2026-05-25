import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../promos_provider.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PromosProvider>().refresh();
    });
  }

  String _displayValue(Map<String, dynamic> p) {
    final t = p['discount_type']?.toString();
    final v = (p['discount_value'] as num?)?.toDouble() ?? 0;
    if (t == 'percentage') return '${v.toStringAsFixed(0)}%';
    return 'Rs.${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PromosProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Promos & Offers'),
      ),
      body: RefreshIndicator(
        onRefresh: () => p.refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // BRD: RW-01 — loyalty balance card on top of the inbox.
            _LoyaltyCard(loyalty: p.loyalty),
            const SizedBox(height: 14),
            // BRD: RW-04 — category filter chips + claimed-only toggle.
            _CategoryChips(provider: p),
            const SizedBox(height: 12),
            if (p.loading && p.items.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: CircularProgressIndicator()))
            else if (p.items.isEmpty)
              _empty()
            else
              ...p.items.asMap().entries.map((e) => EntranceSlide(
                    delay: Duration(milliseconds: 55 * e.key),
                    child: _PromoCard(
                      promo: e.value,
                      value: _displayValue(e.value),
                      onClaim: () => p.claim(e.value['id'] as int),
                      onUnclaim: () => p.unclaim(e.value['id'] as int),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 140),
        Center(
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.local_offer_outlined,
                    size: 44, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 18),
              const Text('No active promotions',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Check back soon for great deals',
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PromoCard extends StatelessWidget {
  final Map<String, dynamic> promo;
  final String value;
  final VoidCallback onClaim;
  final VoidCallback onUnclaim;
  const _PromoCard({
    required this.promo,
    required this.value,
    required this.onClaim,
    required this.onUnclaim,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  Widget _chip(String text, {Color? bg, Color? fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg ?? AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  List<Widget> _metaChips(Map<String, dynamic> p) {
    final chips = <Widget>[];
    final min = p['min_order_amount'] as num?;
    if (min != null && min > 0) {
      chips.add(_chip('Min Rs.${min.toStringAsFixed(0)}'));
    }
    final validTo = p['valid_to']?.toString();
    if (validTo != null && validTo.isNotEmpty) {
      try {
        final d = DateTime.parse(validTo).toLocal();
        chips.add(_chip(
          'Until ${d.day} ${_months[d.month - 1]}',
          bg: const Color(0x14F59E0B),
          fg: AppColors.warning,
        ));
      } catch (_) {}
    }
    return chips;
  }

  Future<void> _copy(BuildContext context, String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Copied $code'),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = promo['code'] as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 100,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomLeft: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_offer_rounded, size: 24, color: Colors.black),
                const SizedBox(height: 6),
                Text(value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      color: Colors.black,
                    )),
                const Text('OFF',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1.5,
                    )),
              ],
            ),
          ),
          // Notch
          Container(
            width: 2,
            color: AppColors.background,
            child: Column(
              children: List.generate(
                10,
                (_) => Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 1),
                    color: AppColors.divider,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          code,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      if (promo['claimed_at'] != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0x1410B981),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, size: 11, color: AppColors.success),
                              SizedBox(width: 3),
                              Text('SAVED',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                  )),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (promo['description'] as String?) ?? '',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_metaChips(promo).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _metaChips(promo),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // BRD: RW-04 — Save/Saved toggle
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: promo['claimed_at'] != null ? onUnclaim : onClaim,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            side: BorderSide(
                              color: promo['claimed_at'] != null ? AppColors.success : AppColors.cardBorder,
                            ),
                          ),
                          icon: Icon(
                            promo['claimed_at'] != null ? Icons.bookmark_remove_rounded : Icons.bookmark_add_rounded,
                            size: 14,
                            color: promo['claimed_at'] != null ? AppColors.success : AppColors.textSecondary,
                          ),
                          label: Text(
                            promo['claimed_at'] != null ? 'Saved' : 'Save',
                            style: TextStyle(
                              color: promo['claimed_at'] != null ? AppColors.success : AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: GestureDetector(
              onTap: () => _copy(context, code),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// BRD: RW-01 — loyalty balance card on top of the promo inbox.
class _LoyaltyCard extends StatelessWidget {
  final Map<String, dynamic> loyalty;
  const _LoyaltyCard({required this.loyalty});

  @override
  Widget build(BuildContext context) {
    final pts = (loyalty['points'] as num?)?.toInt() ?? 0;
    final value = (loyalty['value'] as num?)?.toDouble() ?? 0;
    final min = (loyalty['min_redeem_points'] as num?)?.toInt() ?? 100;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.blackGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 52, height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.stars_rounded, color: Colors.black, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your points',
                    style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
                const SizedBox(height: 2),
                Text('$pts pts',
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                Text('≈ Rs.${value.toStringAsFixed(0)} · Redeem from $min pts',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


/// BRD: RW-04 — category-tagged inbox + saved-only toggle.
class _CategoryChips extends StatelessWidget {
  final PromosProvider provider;
  const _CategoryChips({required this.provider});

  static const _cats = [
    ('all', 'All'),
    ('rides', 'Rides'),
    ('food', 'Food'),
    ('market', 'Market'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _cats.map((c) {
                final selected = provider.category == c.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(c.$2),
                    selected: selected,
                    onSelected: (_) => provider.category = c.$1,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                    selectedColor: Colors.black,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: selected ? Colors.black : AppColors.cardBorder),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text('Saved'),
          selected: provider.onlyClaimed,
          onSelected: (v) => provider.onlyClaimed = v,
          labelStyle: TextStyle(
            color: provider.onlyClaimed ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
          selectedColor: AppColors.success,
          backgroundColor: Colors.white,
          side: BorderSide(color: provider.onlyClaimed ? AppColors.success : AppColors.cardBorder),
        ),
      ],
    );
  }
}
