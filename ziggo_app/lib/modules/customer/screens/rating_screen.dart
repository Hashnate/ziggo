import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/confetti.dart';
import '../booking_provider.dart';

class RatingScreen extends StatefulWidget {
  final int bookingId;
  const RatingScreen({super.key, required this.bookingId});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> with TickerProviderStateMixin {
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
    _checkScale = CurvedAnimation(parent: _checkController, curve: Curves.elasticOut);
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
    final booking = context.read<BookingProvider>();
    bool ok = false;
    String? caughtError;
    try {
      ok = await booking.rate(
        bookingId: widget.bookingId,
        rating: _stars,
        feedback: _feedbackCtrl.text.trim().isEmpty ? null : _feedbackCtrl.text.trim(),
      );
    } catch (e) {
      caughtError = e.toString();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Navigator.popUntil(context, (r) => r.isFirst);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 36),
        title: const Text('Could not submit', textAlign: TextAlign.center),
        content: Text(
          caughtError ?? booking.lastError ?? 'Failed to submit rating. Please try again.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
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
        return 'Amazing';
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
        particleCount: 100,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 28),
              Center(
                child: ScaleTransition(
                  scale: _checkScale,
                  child: Container(
                    width: 110,
                    height: 110,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.goldGradient,
                      shape: BoxShape.circle,
                      boxShadow: AppStyles.goldGlow,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.black,
                      size: 60,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Ride completed!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'How was your ride? Your feedback helps everyone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 36),
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
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(5, (i) {
                        final filled = i < _stars;
                        return GestureDetector(
                          onTap: () => setState(() => _stars = i + 1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutBack,
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              filled ? Icons.star_rounded : Icons.star_outline_rounded,
                              color: filled ? Colors.amber : Colors.grey.shade300,
                              size: filled ? 44 : 40,
                            ),
                          ),
                        );
                      }),
                    ),
                    if (_stars > 0) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                    hintText: 'Anything we should know?',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              const Spacer(),
              PrimaryButton(
                label: 'SUBMIT',
                icon: Icons.send_rounded,
                gold: true,
                busy: _busy,
                onPressed: _stars == 0 ? null : _submit,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  context.read<BookingProvider>().clearActiveBookingLocally();
                  Navigator.popUntil(context, (r) => r.isFirst);
                },
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
      ),
    );
  }
}
