import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../restaurant_provider.dart';
import 'restaurant_order_detail_screen.dart';

class RestaurantDailyReportScreen extends StatefulWidget {
  final String date;

  const RestaurantDailyReportScreen({
    super.key,
    required this.date,
  });

  @override
  State<RestaurantDailyReportScreen> createState() =>
      _RestaurantDailyReportScreenState();
}

class _RestaurantDailyReportScreenState
    extends State<RestaurantDailyReportScreen> {
  bool _loading = true;
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    final p = context.read<RestaurantProvider>();
    final data = await p.fetchDailyReport(date: widget.date);
    if (!mounted) return;
    setState(() {
      _report = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    DateTime? parsedDate;
    try {
      parsedDate = DateTime.parse(widget.date);
    } catch (_) {}
    final formattedDate = parsedDate != null
        ? DateFormat('EEEE, MMMM d, y').format(parsedDate)
        : widget.date;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Daily Report',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadReport,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _report == null
              ? const Center(
                  child: Text(
                    "Couldn't load report details",
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildOverviewCard(_report!),
                    const SizedBox(height: 20),
                    const Text(
                      'Items Sold',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildItemsSoldList(_report!),
                    const SizedBox(height: 20),
                    const Text(
                      'Orders',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildOrdersList(_report!),
                  ],
                ),
    );
  }

  Widget _buildOverviewCard(Map<String, dynamic> data) {
    final revenue = (data['revenue'] as num? ?? 0).toDouble();
    final delivered = (data['total_delivered'] as num? ?? 0).toInt();
    final orders = (data['total_orders'] as num? ?? 0).toInt();
    final cancelled = (data['total_cancelled'] as num? ?? 0).toInt();
    final aov = (data['average_order_value'] as num? ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF172554), Color(0xFF1E40AF), Color(0xFF3B82F6)],
        ),
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        boxShadow: AppStyles.shadowLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DAILY INCOME',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Rs.${NumberFormat('#,##0').format(revenue.round())}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.between,
            children: [
              _buildMetricItem('Completed', '$delivered', Colors.greenAccent),
              _buildMetricItem('Cancelled', '$cancelled', Colors.redAccent),
              _buildMetricItem('Avg Order', 'Rs.${aov.round()}', Colors.white),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricItem(String label, String value, Color valColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valColor,
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildItemsSoldList(Map<String, dynamic> data) {
    final items = (data['items_sold'] as List? ?? []).cast<Map<String, dynamic>>();

    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          boxShadow: AppStyles.shadowSm,
        ),
        child: const Center(
          child: Text(
            'No items sold on this day',
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final item = items[index];
          final name = item['name']?.toString() ?? '';
          final qty = (item['quantity'] as num? ?? 0).toInt();
          final rev = (item['revenue'] as num? ?? 0).toDouble();

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  'x$qty',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 24),
                Text(
                  'Rs.${NumberFormat('#,##0').format(rev.round())}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrdersList(Map<String, dynamic> data) {
    final orders = (data['orders'] as List? ?? []).cast<Map<String, dynamic>>();

    if (orders.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          boxShadow: AppStyles.shadowSm,
        ),
        child: const Center(
          child: Text(
            'No orders on this day',
            style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final order = orders[index];
          final ref = order['order_ref']?.toString() ?? '';
          final status = order['status']?.toString() ?? '';
          final finalAmount = (order['final_amount'] as num? ?? 0).toDouble();
          final itemsSummary = order['items_summary']?.toString() ?? '';
          final dateStr = order['created_at']?.toString() ?? '';

          String timeLabel = '';
          try {
            final dt = DateTime.parse(dateStr).toLocal();
            timeLabel = DateFormat('jm').format(dt);
          } catch (_) {}

          Color statusColor = AppColors.textSecondary;
          if (status == 'delivered') {
            statusColor = Colors.green;
          } else if (status == 'cancelled') {
            statusColor = Colors.red;
          } else if (status == 'pending') {
            statusColor = Colors.orange;
          }

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RestaurantOrderDetailScreen(order: order),
                ),
              );
            },
            borderRadius: BorderRadius.circular(AppStyles.radiusMd),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              ref,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 9,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          itemsSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (timeLabel.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            timeLabel,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Rs.${NumberFormat('#,##0').format(finalAmount.round())}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textTertiary,
                    size: 18,
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
