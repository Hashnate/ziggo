import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import '../driver_theme.dart';

class DriverHistoryScreen extends StatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  State<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends State<DriverHistoryScreen> {
  List<Map<String, dynamic>> _rides = [];
  bool _loading = true;
  int? _expandedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await ApiClient.instance.dio.get('/bookings');
      if (mounted) {
        setState(() {
          _rides = List<Map<String, dynamic>>.from(resp.data as List);
          _loading = false;
        });
      }
    } on DioException {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _totalEarned => _rides
      .where((r) => r['status'] == 'completed')
      .fold(0.0, (s, r) => s + ((r['driver_earnings'] as num?)?.toDouble() ?? (r['final_amount'] as num?)?.toDouble() ?? 0));

  int get _completedCount => _rides.where((r) => r['status'] == 'completed').length;
  int get _cancelledCount => _rides.where((r) => r['status'] == 'cancelled').length;

  ({Color color, IconData icon, String label}) _statusMeta(String s) {
    switch (s) {
      case 'completed':
        return (color: AppColors.success, icon: Icons.check_circle_rounded, label: 'Completed');
      case 'cancelled':
        return (color: AppColors.error, icon: Icons.cancel_rounded, label: 'Cancelled');
      default:
        return (color: AppColors.warning, icon: Icons.directions_car_rounded, label: 'Active');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: driverTheme(context),
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: kDriverBg,
      appBar: AppBar(
        backgroundColor: kDriverBg,
        elevation: 0,
        title: const Text('My Rides'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                children: staggered([
                  // Earnings hero
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: AppStyles.shadowLg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Text(
                            'TOTAL EARNED',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Rs.${_totalEarned.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 36,
                            letterSpacing: -1,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: _stat(
                                'Completed',
                                '$_completedCount',
                                AppColors.success,
                                Icons.check_circle_rounded,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 32,
                              color: AppColors.divider,
                            ),
                            Expanded(
                              child: _stat(
                                'Cancelled',
                                '$_cancelledCount',
                                AppColors.error,
                                Icons.cancel_rounded,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Rides list
                  if (_rides.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 50),
                      child: Center(
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
                              child: const Icon(Icons.history_rounded,
                                  size: 44, color: AppColors.textTertiary),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'No rides yet',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._rides.map((r) {
                      final status = (r['status'] ?? '').toString();
                      final meta = _statusMeta(status);
                      final isExpanded = _expandedId == r['id'];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _expandedId = isExpanded ? null : r['id'];
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: kDriverCard,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: meta.color.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(meta.icon, color: meta.color, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            r['booking_ref']?.toString() ?? '',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Text(
                                            r['booked_at']?.toString().substring(0, 16) ?? '',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textTertiary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: meta.color.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(100),
                                      ),
                                      child: Text(
                                        meta.label,
                                        style: TextStyle(
                                          color: meta.color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1, color: AppColors.divider),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.my_location_rounded,
                                            color: AppColors.flash, size: 13),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            r['pickup_address']?.toString() ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on_rounded,
                                            color: AppColors.error, size: 13),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            r['drop_address']?.toString() ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (isExpanded) ...[
                                const Divider(height: 1, color: AppColors.divider),
                                Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _formatServiceType(r['service_type']?.toString(), r),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _breakdownRow(
                                        'Duration',
                                        _formatDuration(r),
                                      ),
                                      _breakdownRow(
                                        'Distance',
                                        _formatDistance(r),
                                      ),
                                      const SizedBox(height: 10),
                                      const Divider(height: 1, color: AppColors.divider),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'FARE BREAKDOWN',
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          letterSpacing: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _breakdownRow(
                                        'Trip Fare / Base Fare',
                                        'Rs.${((r['fare_amount'] as num?) ?? 0).toStringAsFixed(2)}',
                                      ),
                                      if (((r['pickup_fee'] as num?) ?? 0) > 0)
                                        _breakdownRow(
                                          '  • Included Pickup Fee',
                                          'Rs.${((r['pickup_fee'] as num?) ?? 0).toStringAsFixed(2)}',
                                        ),
                                      if (((r['boost'] as num?) ?? 0) > 0)
                                        _breakdownRow(
                                          'Boost Incentive (100% to you)',
                                          'Rs.${((r['boost'] as num?) ?? 0).toStringAsFixed(2)}',
                                        ),
                                      if (((r['passenger_deductible'] as num?) ?? 0) > 0)
                                        _breakdownRow(
                                          'Passenger Deductible (Added)',
                                          'Rs.${((r['passenger_deductible'] as num?) ?? 0).toStringAsFixed(2)}',
                                        ),
                                      if (((r['discount_amount'] as num?) ?? 0) > 0)
                                        _breakdownRow(
                                          'Promo / Redemption Discount',
                                          'Rs.${((r['discount_amount'] as num?) ?? 0).toStringAsFixed(2)}',
                                          isNegative: true,
                                        ),
                                      _breakdownRow(
                                        'Gross Total',
                                        'Rs.${((r['final_amount'] as num?) ?? 0).toStringAsFixed(2)}',
                                        isBold: true,
                                      ),
                                      const SizedBox(height: 6),
                                      const Divider(height: 1, color: AppColors.divider),
                                      const SizedBox(height: 6),
                                      _breakdownRow(
                                        'App Usage Charges (Commission)',
                                        'Rs.${((r['app_usage_charges'] as num?) ?? (r['platform_fee'] as num?) ?? 0).toStringAsFixed(2)}',
                                        isNegative: true,
                                      ),
                                      if (((r['passenger_deductible'] as num?) ?? 0) > 0)
                                        _breakdownRow(
                                          'Passenger Deductible (Deducted)',
                                          'Rs.${((r['passenger_deductible'] as num?) ?? 0).toStringAsFixed(2)}',
                                          isNegative: true,
                                        ),
                                      _breakdownRow(
                                        'Total Deductions',
                                        'Rs.${((r['deductions'] as num?) ?? 0).toStringAsFixed(2)}',
                                        isNegative: true,
                                        isBold: true,
                                      ),
                                      const SizedBox(height: 6),
                                      const Divider(height: 1, color: AppColors.divider),
                                      const SizedBox(height: 6),
                                      _breakdownRow(
                                        'Net Driver Earnings',
                                        'Rs.${((r['driver_earnings'] as num?) ?? (r['final_amount'] as num?) ?? 0).toStringAsFixed(2)}',
                                        isBold: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: const BoxDecoration(
                                  color: AppColors.surfaceMuted,
                                  borderRadius: BorderRadius.only(
                                    bottomLeft: Radius.circular(18),
                                    bottomRight: Radius.circular(18),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Text(
                                      'YOU EARNED',
                                      style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Rs.${((r['driver_earnings'] as num?) ?? (r['final_amount'] as num?) ?? 0).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ]),
              ),
            ),
    );
  }

  String _formatServiceType(String? serviceType, Map<String, dynamic> r) {
    if (serviceType == null) return 'Ride';
    if (serviceType.toLowerCase() == 'food' || r['is_food'] == true) {
      return 'Bike food';
    }
    if (serviceType.toLowerCase() == 'market' || r['is_market'] == true) {
      return 'Market Delivery';
    }
    return serviceType[0].toUpperCase() + serviceType.substring(1);
  }

  String _formatDuration(Map<String, dynamic> r) {
    final startedStr = r['started_at']?.toString();
    final completedStr = r['completed_at']?.toString();
    if (startedStr != null && completedStr != null) {
      try {
        final started = DateTime.parse(startedStr);
        final completed = DateTime.parse(completedStr);
        final diff = completed.difference(started);
        final secs = diff.inMilliseconds / 1000.0;
        if (secs < 60) {
          return '${secs.toStringAsFixed(2)}s';
        } else {
          final mins = secs / 60.0;
          return '${mins.toStringAsFixed(2)} min';
        }
      } catch (_) {}
    }
    final durationMin = r['duration_min'];
    if (durationMin != null) {
      return '$durationMin min';
    }
    return '0 min';
  }

  String _formatDistance(Map<String, dynamic> r) {
    final raw = r['distance_km'];
    final dist = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
    if (dist != null) {
      return '${dist.toStringAsFixed(2)} km';
    }
    return '0.00 km';
  }

  Widget _breakdownRow(String label, String value, {bool isNegative = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          Text(
            isNegative ? '-$value' : value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isNegative
                  ? AppColors.error
                  : (isBold ? kDriverGold : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color, IconData icon) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
