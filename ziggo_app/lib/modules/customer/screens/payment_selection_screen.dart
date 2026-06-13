import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../payment_methods_provider.dart';
import '../wallet_provider.dart';
import '../promos_provider.dart';
import 'payment_methods_screen.dart';

class PaymentSelectionScreen extends StatefulWidget {
  final String currentPayment;

  const PaymentSelectionScreen({
    super.key,
    required this.currentPayment,
  });

  @override
  State<PaymentSelectionScreen> createState() => _PaymentSelectionScreenState();
}

class _PaymentSelectionScreenState extends State<PaymentSelectionScreen> {
  late String _selectedPayment;

  @override
  void initState() {
    super.initState();
    _selectedPayment = widget.currentPayment;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PaymentMethodsProvider>().fetchCards();
      context.read<PaymentMethodsProvider>().fetchCorporateProfile();
      context.read<WalletProvider>().refresh();
      context.read<PromosProvider>().refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cardsProvider = context.watch<PaymentMethodsProvider>();
    final walletProvider = context.watch<WalletProvider>();
    final promosProvider = context.watch<PromosProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Payment',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Business Section
            _buildSectionHeader('Business'),
            if (cardsProvider.corporateProfile == null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Text(
                  "You haven't added any business profiles to show here",
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              _buildAddAction(
                label: 'Add business account',
                onTap: () {
                  // Link to business registration if available, or show mock dialog
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Business profiles are currently managed by your administrator.')),
                  );
                },
              ),
            ] else ...[
              _buildPaymentTile(
                value: 'corporate',
                title: cardsProvider.corporateProfile!['company_name'] ?? 'Corporate Account',
                icon: const Icon(Icons.business_rounded, color: AppColors.primary, size: 24),
                onTap: () => _selectPayment('corporate'),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(height: 1),

            // Personal Section
            _buildSectionHeader('Personal'),
            
            // Cash Option
            _buildPaymentTile(
              value: 'cash',
              title: 'Cash',
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.payments_rounded, color: Colors.green, size: 22),
              ),
              onTap: () => _selectPayment('cash'),
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),

            // Points Option
            _buildPaymentTile(
              value: 'points',
              title: 'Points ${promosProvider.points}',
              icon: const Icon(Icons.stars_rounded, color: Colors.amber, size: 24),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () {
                // Toggle point redemption logic if needed, or simply return 'points'
                _selectPayment('points');
              },
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),

            // Wallet Option
            _buildPaymentTile(
              value: 'wallet',
              title: 'Ziggo Wallet (Rs. ${walletProvider.balance.toStringAsFixed(2)})',
              icon: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 24),
              onTap: () => _selectPayment('wallet'),
            ),
            const Divider(height: 1, indent: 20, endIndent: 20),

            // Saved Cards
            ...cardsProvider.cards.map((card) {
              final String cardNo = card['card_no'] ?? '';
              final String value = 'card_${card['id']}';
              final String last4 = cardNo.length > 4 ? cardNo.substring(cardNo.length - 4) : cardNo;
              return Column(
                children: [
                  _buildPaymentTile(
                    value: value,
                    title: '${card['card_type'] ?? 'Card'} ending in $last4',
                    icon: const Icon(Icons.credit_card_rounded, color: Colors.blueGrey, size: 24),
                    onTap: () => _selectPayment(value),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                ],
              );
            }),

            // Add payment method action
            _buildAddAction(
              label: 'Add payment method',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PaymentMethodsScreen()),
                );
                if (mounted) {
                  context.read<PaymentMethodsProvider>().fetchCards();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      width: double.infinity,
      color: Colors.grey.withOpacity(0.05),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildPaymentTile({
    required String value,
    required String title,
    required Widget icon,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final isSelected = _selectedPayment == value;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            // Radio Circle
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            // Payment Icon
            icon,
            const SizedBox(width: 16),
            // Title
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildAddAction({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.indigo,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const Icon(Icons.add, color: Colors.indigo),
          ],
        ),
      ),
    );
  }

  void _selectPayment(String method) {
    setState(() {
      _selectedPayment = method;
    });
    Navigator.pop(context, method);
  }
}
