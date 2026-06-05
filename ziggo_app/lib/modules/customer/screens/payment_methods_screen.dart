import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/ambient_orbs.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/motion.dart';
import '../payment_methods_provider.dart';
import '../wallet_provider.dart';
import 'wallet_screen.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentMethodsProvider>().fetchCards();
      context.read<WalletProvider>().refresh();
    });
  }

  Future<void> _addCard() async {
    final provider = context.read<PaymentMethodsProvider>();
    final err = await provider.addCardViaPayHere(context);
    if (!mounted) return;

    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Card authorized and saved successfully!'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteCard(int cardId, String cardNo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Card'),
        content: Text('Are you sure you want to remove the card ending in ${cardNo.substring(cardNo.length - 4)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('REMOVE'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final ok = await context.read<PaymentMethodsProvider>().deleteCard(cardId);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Card removed successfully.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PaymentMethodsProvider>();
    final wallet = context.watch<WalletProvider>();
    
    // Find the default card, or fallback to the first card, or null
    final defaultCard = p.cards.firstWhere(
      (c) => c['is_default'] == true,
      orElse: () => p.cards.isNotEmpty ? p.cards.first : <String, dynamic>{},
    );

    final bool hasDefault = defaultCard.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Payment Methods'),
      ),
      body: p.isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: () async {
                await context.read<PaymentMethodsProvider>().fetchCards();
                await context.read<WalletProvider>().refresh();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                children: [
                  // Premium Hero Card Section representing the primary/default card
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      children: [
                        Container(
                          height: 200,
                          decoration: const BoxDecoration(
                            gradient: AppColors.blackGradient,
                          ),
                        ),
                        const Positioned.fill(
                          child: AmbientOrbs(
                            colors: [
                              AppColors.primary,
                              AppColors.accent,
                              AppColors.primaryLight,
                            ],
                          ),
                        ),
                        const Positioned(
                          top: 0, left: 0, right: 0,
                          child: ShimmerHighlight(height: 200),
                        ),
                        Container(
                          height: 200,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                            boxShadow: AppStyles.shadowLg,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                                    ),
                                    child: const Text(
                                      'PRIMARY METHOD',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    hasDefault ? (defaultCard['card_type'] ?? 'CARD').toString().toUpperCase() : 'ZIGGO',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                              if (hasDefault) ...[
                                Text(
                                  _formatCardNumber(defaultCard['card_no'] ?? ''),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 3,
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('CARDHOLDER', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text(
                                          (defaultCard['card_holder_name'] ?? 'VALUED CUSTOMER').toString().toUpperCase(),
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        const Text('EXPIRES', style: TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatExpiry(defaultCard['card_expiry'] ?? ''),
                                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              ] else ...[
                                const Text(
                                  'Cash & Wallet Enabled',
                                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const Text(
                                  'Add a card for seamless cashless payments.',
                                  style: TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Digital Wallet Balance Card
                  const Text(
                    'IN-APP WALLET',
                    style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w900, letterSpacing: 1.4),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Ziggo Wallet',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Balance: Rs.${wallet.balance.toStringAsFixed(2)}',
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // List of Saved Cards
                  Row(
                    children: [
                      const Text(
                        'SAVED CARDS',
                        style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w900, letterSpacing: 1.4),
                      ),
                      const Spacer(),
                      Text(
                        '${p.cards.length} card(s)',
                        style: const TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (p.cards.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
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
                  else
                    ...p.cards.map((c) {
                      final bool isDefault = c['is_default'] == true;
                      final String cardNo = c['card_no'] ?? '';
                      final int cardId = c['id'] ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDefault ? AppColors.primary : AppColors.cardBorder,
                            width: isDefault ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: (isDefault ? AppColors.primary : AppColors.textTertiary).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.credit_card_rounded,
                                color: isDefault ? AppColors.primary : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${c['card_type'] ?? 'Card'} ending in ${cardNo.length > 4 ? cardNo.substring(cardNo.length - 4) : cardNo}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Expires: ${_formatExpiry(c['card_expiry'] ?? '')}',
                                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            if (!isDefault)
                              TextButton(
                                onPressed: () => p.setAsDefault(cardId),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  foregroundColor: AppColors.primary,
                                ),
                                child: const Text('SET DEFAULT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'DEFAULT',
                                  style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w900),
                                ),
                              ),
                            const SizedBox(width: 6),
                            IconButton(
                              onPressed: () => _deleteCard(cardId, cardNo),
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(
            label: 'ADD NEW CREDIT / DEBIT CARD',
            icon: Icons.add_rounded,
            busy: p.isLoading,
            onPressed: _addCard,
          ),
        ),
      ),
    );
  }

  String _formatCardNumber(String number) {
    if (number.isEmpty) return '';
    // Show masked visa like **** **** **** 1234 or similar
    final last4 = number.length > 4 ? number.substring(number.length - 4) : number;
    return '••••  ••••  ••••  $last4';
  }

  String _formatExpiry(String expiry) {
    if (expiry.length == 4) {
      return '${expiry.substring(0, 2)}/${expiry.substring(2)}';
    }
    return expiry;
  }
}
