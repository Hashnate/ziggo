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

  Widget _buildCustomerReviewSection() {
    if (_loadingBooking && _bookingData == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final rating = _bookingData?['customer_rating'];
    final feedback = _bookingData?['customer_feedback'];

    if (rating == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Waiting for passenger\'s review...',
                style: TextStyle(
                  color: AppColors.primary.withOpacity(0.8),
                  fontSize: 14,
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
      padding: const EdgeInsets.all(20),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: ratingColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_pin_rounded,
                  color: ratingColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Passenger\'s Review for You',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: ratingColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: ratingColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(5, (i) {
              final filled = i < stars;
              return Icon(
                filled ? Icons.star_rounded : Icons.star_outline_rounded,
                color: filled ? ratingColor : Colors.grey.shade300,
                size: 28,
              );
            }),
          ),
          if (feedback != null && feedback.toString().trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '"$feedback"',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
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
              const SizedBox(height: 40),
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
              const SizedBox(height: 8),
              const Text(
                'Thank you for completing the ride safely. Here is the feedback left by your passenger.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),
              _buildCustomerReviewSection(),
              const SizedBox(height: 24),
              PrimaryButton(
                label: 'GO TO DASHBOARD',
                icon: Icons.home_rounded,
                gold: false,
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
