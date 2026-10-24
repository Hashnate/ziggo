import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../promos_provider.dart';

/// Keeps a chosen promo code checked with the server (POST /promos/check) for
/// checkouts that have no server quote: food, market and events. The order
/// itself checks the code again, so this only drives what the customer sees.
class PromoCheck {
  Map<String, dynamic>? result;
  bool checking = false;
  String? _checkedCode;
  double? _checkedAmount;

  bool isFor(String code) => code.isNotEmpty && _checkedCode == code;

  /// What the server will take off for [code], or 0.
  double discount(String code) {
    if (!isFor(code) || checking || result?['applies'] != true) return 0;
    return (result!['discount_amount'] as num?)?.toDouble() ?? 0;
  }

  /// One line for the customer: checking, the discount, or why not.
  String status(String code) {
    if (code.isEmpty) return 'Tap to add a promo code';
    if (checking || !isFor(code)) return 'Checking…';
    if (result == null) return "Couldn't check this code right now";
    if (result!['applies'] == true) return 'Applied: -Rs.${discount(code).toStringAsFixed(0)}';
    return 'Not applied: ${result!['message'] ?? "this code can't be used here"}';
  }

  Color statusColor(String code) {
    if (code.isEmpty) return AppColors.primary;
    if (checking || !isFor(code) || result == null) return AppColors.textSecondary;
    return result!['applies'] == true ? AppColors.success : AppColors.error;
  }

  /// Checks again after this frame when the code or the order amount changed.
  void keepFresh(BuildContext context, String code, String category, double amount, VoidCallback changed) {
    if (code.isEmpty || checking || (_checkedCode == code && _checkedAmount == amount)) return;
    checking = true;
    _checkedCode = code;
    _checkedAmount = amount;
    result = null;
    // Called from build, where Provider doesn't allow context.read.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) {
        checking = false;
        return;
      }
      final r = await context.read<PromosProvider>().check(code, category, amount);
      checking = false;
      result = r;
      changed();
    });
  }
}

/// Promo row for food, market and event checkouts: the chosen code with the
/// discount it gives, or the server's reason it doesn't apply.
class PromoCodeTile extends StatelessWidget {
  const PromoCodeTile({
    super.key,
    required this.code,
    required this.check,
    required this.onTap,
    required this.onClear,
  });

  final String code;
  final PromoCheck check;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final color = check.statusColor(code);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.local_offer_rounded, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  code.isEmpty ? 'Add promo code' : code,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  check.status(code),
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (code.isEmpty)
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary)
          else
            IconButton(
              tooltip: 'Remove code',
              icon: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}
