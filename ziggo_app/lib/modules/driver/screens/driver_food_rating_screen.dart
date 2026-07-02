import 'dart:async';
import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';

// Food color tokens
const _kOrange = Color(0xFFFF7849);

class DriverFoodRatingScreen extends StatefulWidget {
  final int orderId;
  const DriverFoodRatingScreen({super.key, required this.orderId});

  @override
  State<DriverFoodRatingScreen> createState() => _DriverFoodRatingScreenState();
}

class _DriverFoodRatingScreenState extends State<DriverFoodRatingScreen> with TickerProviderStateMixin {
  late final AnimationController _checkController;
  late final Animation<double> _checkScale;

  Map<String, dynamic>? _orderData;
  bool _loading = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _checkScale = CurvedAnimation(parent: _checkController, curve: Curves.elasticOut);

    _fetchOrder();
    _startPolling();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _checkController.dispose();
    super.dispose();
  }

  Future<void> _fetchOrder() async {
    try {
      final resp = await ApiClient.instance.dio.get('/food/orders/${widget.orderId}');
      if (resp.data != null) {
        if (!mounted) return;
        setState(() {
          _orderData = Map<String, dynamic>.from(resp.data);
          _loading = false;
        });
        if (_orderData?['customer_rating'] != null) {
          _pollingTimer?.cancel();
        }
      }
    } catch (e) {
      debugPrint('Error fetching food order: $e');
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_orderData?['customer_rating'] == null) {
        _fetchOrder();
      } else {
        timer.cancel();
      }
    });
  }

  Widget _buildCustomerReviewSection() {
    if (_loading && _orderData == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: _kOrange),
          ),
        ),
      );
    }

    final rating = _orderData?['customer_rating'];
    final feedback = _orderData?['customer_feedback'];

    if (rating == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: _kOrange.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kOrange.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                valueColor: AlwaysStoppedAnimation<Color>(_kOrange),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Waiting for customer\'s review...',
                style: TextStyle(
                  color: _kOrange.withOpacity(0.8),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

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
                  'Customer\'s Review for You',
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
                      color: _kOrange,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _kOrange.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.delivery_dining_rounded,
                      color: Colors.white,
                      size: 60,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Food Delivered!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Thank you for completing the delivery safely. Here is the feedback left by your customer.',
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
              ElevatedButton.icon(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                icon: const Icon(Icons.home_rounded, color: Colors.white),
                label: const Text(
                  'GO TO DASHBOARD',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
