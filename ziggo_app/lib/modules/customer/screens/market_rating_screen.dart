import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/confetti.dart';
import '../market_provider.dart';
import 'market_home_screen.dart';

// Market colour tokens (teal/green)
const _kTeal = Color(0xFF00B89F);
const _kTealDark = Color(0xFF009680);

class MarketRatingScreen extends StatefulWidget {
  final int orderId;
  final String orderRef;
  const MarketRatingScreen(
      {super.key, required this.orderId, required this.orderRef});

  @override
  State<MarketRatingScreen> createState() => _MarketRatingScreenState();
}

class _MarketRatingScreenState extends State<MarketRatingScreen>
    with TickerProviderStateMixin {
  int _stars = 0;
  final _feedbackCtrl = TextEditingController();
  bool _busy = false;

  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _checkScale =
        CurvedAnimation(parent: _checkController, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _checkController.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_stars == 0) return;
    setState(() => _busy = true);
    bool ok = false;
    try {
      ok = await context.read<MarketProvider>().rateOrder(
            widget.orderId,
            _stars,
            feedback: _feedbackCtrl.text.trim().isEmpty
                ? null
                : _feedbackCtrl.text.trim(),
          );
    } catch (_) {}
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _goHome();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not submit rating. Please try again.'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  void _goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const MarketHomeScreen()),
      (route) => route.isFirst,
    );
  }

  String get _ratingLabel {
    switch (_stars) {
      case 1:
        return 'Terrible';
      case 2:
        return 'Bad';
      case 3:
        return 'Okay';
      case 4:
        return 'Great';
      case 5:
        return 'Amazing!';
      default:
        return '';
    }
  }

  Color get _ratingColor {
    if (_stars <= 2) return AppColors.error;
    if (_stars == 3) return AppColors.warning;
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Confetti(
        trigger: true,
        particleCount: 80,
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 28),
                        // Animated success icon with market teal gradient
                        Center(
                          child: ScaleTransition(
                            scale: _checkScale,
                            child: Container(
                              width: 110,
                              height: 110,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [_kTeal, _kTealDark],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: _kTeal.withOpacity(0.4),
                                    blurRadius: 24,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.shopping_bag_rounded,
                                color: Colors.white,
                                size: 56,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text(
                          'Order Delivered!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'How was your delivery for ${widget.orderRef}?',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 36),
                        // Star rating card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: AppStyles.shadowSm,
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: List.generate(5, (i) {
                                  final filled = i < _stars;
                                  return GestureDetector(
                                    onTap: () =>
                                        setState(() => _stars = i + 1),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      curve: Curves.easeOutBack,
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(
                                        filled
                                            ? Icons.star_rounded
                                            : Icons.star_outline_rounded,
                                        color: filled
                                            ? Colors.amber
                                            : Colors.grey.shade300,
                                        size: filled ? 44 : 40,
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              if (_stars > 0) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _ratingColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    _ratingLabel,
                                    style: TextStyle(
                                      color: _ratingColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            'FEEDBACK (OPTIONAL)',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          child: TextField(
                            controller: _feedbackCtrl,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Anything to share about the delivery?',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _stars == 0 || _busy ? null : _submit,
                            icon: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Icon(Icons.send_rounded,
                                    color: Colors.white),
                            label: const Text(
                              'SUBMIT',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kTeal,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppStyles.radiusMd),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _goHome,
                          child: const Text(
                            'Skip for now',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
