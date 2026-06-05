import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../wallet_provider.dart';
import 'qr_pay_success_screen.dart';

class QrPayConfirmScreen extends StatefulWidget {
  final Map<String, dynamic> merchantInfo;

  const QrPayConfirmScreen({
    super.key,
    required this.merchantInfo,
  });

  @override
  State<QrPayConfirmScreen> createState() => _QrPayConfirmScreenState();
}

class _QrPayConfirmScreenState extends State<QrPayConfirmScreen> {
  final TextEditingController _amountController = TextEditingController(text: '');
  double _amount = 0.0;
  bool _isPaying = false;
  double _sliderProgress = 0.0; // Slider offset progress (0.0 to 1.0)

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() {
      setState(() {
        _amount = double.tryParse(_amountController.text) ?? 0.0;
      });
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _executePayment() async {
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _sliderProgress = 0.0;
      });
      return;
    }

    final balance = context.read<WalletProvider>().balance;
    if (_amount > balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Insufficient wallet balance'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _sliderProgress = 0.0;
      });
      return;
    }

    setState(() {
      _isPaying = true;
    });

    try {
      final String merchantType = widget.merchantInfo['merchant_type'] ?? '';
      final int merchantId = widget.merchantInfo['merchant_id'] ?? 0;
      
      final payResult = await context.read<WalletProvider>().payMerchant(
        merchantType,
        merchantId,
        _amount,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => QrPaySuccessScreen(
            amount: _amount,
            merchantName: widget.merchantInfo['name'] ?? 'Merchant',
            referenceId: payResult['reference_id'] ?? 'QR-SUCCESS',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {
        _sliderProgress = 0.0;
        _isPaying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallet = context.watch<WalletProvider>();
    final balance = wallet.balance;
    final isInsufficient = _amount > balance;
    final merchantName = widget.merchantInfo['name'] ?? 'Merchant';
    final merchantAddress = widget.merchantInfo['address'] ?? 'Colombo, Sri Lanka';
    final merchantType = widget.merchantInfo['merchant_type'] == 'restaurant' ? 'Restaurant' : 'Market Store';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Confirm Payment', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Merchant Profile Card
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: AppStyles.shadowSm,
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.merchantInfo['merchant_type'] == 'restaurant'
                                    ? Icons.restaurant_rounded
                                    : Icons.store_rounded,
                                color: AppColors.primary,
                                size: 30,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              merchantName,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              merchantType,
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              merchantAddress,
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Amount Entry Section
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: AppStyles.shadowSm,
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Payment Amount',
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 1.2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1.0,
                              ),
                              decoration: const InputDecoration(
                                hintText: '0.00',
                                prefixText: 'Rs. ',
                                prefixStyle: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                              autofocus: true,
                            ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Your Wallet Balance',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'Rs.${balance.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: isInsufficient ? AppColors.error : Colors.black,
                                  ),
                                ),
                              ],
                            ),
                            if (isInsufficient) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Insufficient balance. Please top up your wallet.',
                                        style: TextStyle(
                                          color: AppColors.error,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Premium Slide-to-Pay Slider
                  Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: _isPaying
                        ? Container(
                            height: 64,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Processing Payment...',
                                  style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black),
                                ),
                              ],
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, box) {
                              final sliderWidth = box.maxWidth;
                              const handleSize = 56.0;
                              final maxOffset = sliderWidth - handleSize - 8.0;

                              return Container(
                                height: 64,
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: isInsufficient ? Colors.grey[200] : Colors.black,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Guide Text
                                    Text(
                                      isInsufficient
                                          ? 'INSUFFICIENT BALANCE'
                                          : 'SLIDE TO PAY',
                                      style: TextStyle(
                                        color: isInsufficient
                                            ? Colors.grey[500]
                                            : Colors.white.withOpacity(0.6),
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        letterSpacing: 1.5,
                                      ),
                                    ),

                                    // Sliding Handle
                                    Positioned(
                                      left: _sliderProgress * maxOffset,
                                      child: GestureDetector(
                                        onHorizontalDragUpdate: isInsufficient
                                            ? null
                                            : (details) {
                                                setState(() {
                                                  _sliderProgress += details.primaryDelta! / maxOffset;
                                                  _sliderProgress = _sliderProgress.clamp(0.0, 1.0);
                                                });
                                              },
                                        onHorizontalDragEnd: isInsufficient
                                            ? null
                                            : (details) {
                                                if (_sliderProgress > 0.85) {
                                                  setState(() {
                                                    _sliderProgress = 1.0;
                                                  });
                                                  _executePayment();
                                                } else {
                                                  setState(() {
                                                    _sliderProgress = 0.0;
                                                  });
                                                }
                                              },
                                        child: Container(
                                          width: handleSize,
                                          height: handleSize,
                                          decoration: BoxDecoration(
                                            color: isInsufficient ? Colors.grey[400] : AppColors.primary,
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: const Icon(
                                            Icons.arrow_forward_rounded,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
