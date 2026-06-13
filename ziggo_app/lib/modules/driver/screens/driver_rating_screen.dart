import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';
import '../driver_provider.dart';

class DriverRatingScreen extends StatefulWidget {
  final int bookingId;
  const DriverRatingScreen({super.key, required this.bookingId});

  @override
  State<DriverRatingScreen> createState() => _DriverRatingScreenState();
}

class _DriverRatingScreenState extends State<DriverRatingScreen> with TickerProviderStateMixin {
  int _stars = 5;
  final _feedbackCtrl = TextEditingController();
  bool _busy = false;

  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  Map<String, dynamic>? _bookingData;
  bool _loadingBooking = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _checkScale = CurvedAnimation(parent: _checkController, curve: Curves.elasticOut);

    _fetchBooking();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _checkController.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchBooking() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings/${widget.bookingId}');
      if (resp.data != null) {
        if (!mounted) return;
        setState(() {
          _bookingData = Map<String, dynamic>.from(resp.data);
          _loadingBooking = false;
        });
        if (_bookingData?['customer_rating'] != null) {
          _pollingTimer?.cancel();
        }
      }
    } catch (e) {
      debugPrint('Error fetching booking: $e');
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_bookingData?['customer_rating'] == null) {
        _fetchBooking();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final driver = context.read<DriverProvider>();
    bool ok = false;
    String? caughtError;
    try {
      ok = await driver.rateBooking(
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
          caughtError ?? 'Failed to submit rating. Please try again.',
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
        return 'Terrible customer';
      case 2:
        return 'Bad behavior';
      case 3:
        return 'Okay passenger';
      case 4:
        return 'Good passenger';
      case 5:
        return 'Excellent customer';
      default:
        return '';
    }
  }

  Color get _ratingColor {
    if (_stars <= 2) return AppColors.error;
    if (_stars == 3) return AppColors.warning;
    return AppColors.success;
  }

  Widget _buildCustomerReviewSection() {
    if (_loadingBooking && _bookingData == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final rating = _bookingData?['customer_rating'];
    final feedback = _bookingData?['customer_feedback'];

    if (rating == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Waiting for passenger\'s review...',
                style: TextStyle(
                  color: AppColors.primary.withOpacity(0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Customer rating has been submitted! Let's show it beautifully.
    final int stars = (rating as num).toInt();
    String label = '';
    Color ratingColor = AppColors.success;
    switch (stars) {
      case 1:
        label = 'Terrible';
        ratingColor = AppColors.error;
        break;
      case 2:
        label = 'Bad';
        ratingColor = AppColors.error;
        break;
      case 3:
        label = 'Okay';
        ratingColor = AppColors.warning;
        break;
      case 4:
        label = 'Great';
        ratingColor = AppColors.success;
        break;
      case 5:
        label = 'Amazing';
        ratingColor = AppColors.success;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppStyles.shadowSm,
        border: Border.all(color: ratingColor.withOpacity(0.2), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: ratingColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_pin_rounded,
                  color: ratingColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Passenger\'s Review for You',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ratingColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: ratingColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(5, (i) {
              final filled = i < stars;
              return Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: filled ? ratingColor : AppColors.divider,
                size: 24,
              );
            }),
          ),
          if (feedback != null && feedback.toString().trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '"$feedback"',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
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
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      color: Colors.white,
                      size: 60,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Trip Completed!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'How was the passenger? Rate your experience.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              _buildCustomerReviewSection(),
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
                              color: filled ? AppColors.primary : AppColors.divider,
                              size: filled ? 44 : 40,
                            ),
                          ),
                        );
                      }),
                    ),
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
                    hintText: 'Any comments about the ride?',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: 'SUBMIT REVIEW',
                icon: Icons.send_rounded,
                gold: false,
                busy: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text(
                  'Skip',
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
    );
  }
}
