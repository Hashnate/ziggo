import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../food_provider.dart';
import '../food_ui.dart';
import 'food_order_details_screen.dart';
import 'food_tracking_screen.dart';

class FoodOrdersScreen extends StatefulWidget {
  const FoodOrdersScreen({super.key});

  @override
  State<FoodOrdersScreen> createState() => _FoodOrdersScreenState();
}

class _FoodOrdersScreenState extends State<FoodOrdersScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<FoodProvider>().fetchMyOrders();
  }

  void _reload() {
    setState(() => _future = context.read<FoodProvider>().fetchMyOrders());
  }

  static const _activeStatuses = {
    'pending',
    'confirmed',
    'preparing',
    'ready_for_pickup',
    'out_for_delivery',
  };

  String _pretty(String? status) {
    if (status == null || status.isEmpty) return '—';
    return status
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      case 'out_for_delivery':
        return AppColors.food;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'My Orders',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w900, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _reload(),
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: AppColors.food));
            }
            final orders = snap.data ?? const [];
            if (orders.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Icon(Icons.receipt_long_rounded, size: 56, color: AppColors.textTertiary),
                  SizedBox(height: 16),
                  Center(
                    child: Text('No food orders yet',
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              itemCount: orders.length,
              itemBuilder: (context, i) {
                final o = orders[i];
                final status = o['status']?.toString();
                final ref = o['order_ref']?.toString() ?? '';
                final isActive = _activeStatuses.contains(status);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                    boxShadow: AppStyles.shadowSm,
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.food.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.fastfood_rounded, color: AppColors.food),
                    ),
                    title: Text('#$ref', style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _statusColor(status).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              _pretty(status),
                              style: TextStyle(
                                color: _statusColor(status),
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            formatRs(o['final_amount'] as num?),
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    onTap: ref.isNotEmpty
                        ? () {
                            if (isActive) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => FoodTrackingScreen(orderRef: ref)),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => FoodOrderDetailsScreen(order: o)),
                              );
                            }
                          }
                        : null,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
