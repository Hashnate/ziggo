import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';

class FoodOrderDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const FoodOrderDetailsScreen({super.key, required this.order});

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(date);
    } catch (_) {
      if (dateStr.length >= 16) return dateStr.substring(0, 16);
      return dateStr;
    }
  }

  Future<Map<String, dynamic>> _fetchDetails(int orderId) async {
    try {
      final res = await ApiClient.instance.dio.get(
        '/food/orders/$orderId/details',
      );
      return Map<String, dynamic>.from(res.data);
    } catch (_) {
      return {'items': []};
    }
  }

  Widget _breakdownRow(
    String label,
    String value, {
    bool isNegative = false,
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          Text(
            isNegative ? '-$value' : value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              color: isNegative
                  ? AppColors.error
                  : (isBold ? AppColors.success : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'Rs.', decimalDigits: 2);
    final bookingRef = order['order_ref']?.toString() ?? '';
    final date = _formatDate(order['created_at']?.toString());

    final finalAmount = (order['final_amount'] as num?)?.toDouble() ?? 0.0;
    final deliveryFee = (order['delivery_fee'] as num?)?.toDouble() ?? 0.0;
    final discount = (order['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final itemTotal = finalAmount - deliveryFee + discount;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Order Details',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Image.asset('assets/images/light.png', height: 100)),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                'INVOICE',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primary,
                  letterSpacing: 2,
                ),
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order Ref: $bookingRef',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                Text(
                  date,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),

            FutureBuilder<Map<String, dynamic>>(
              future: _fetchDetails(order['id'] as int),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final details = snapshot.data ?? {};
                final rawItems = details['items'];
                final items = rawItems is List ? rawItems.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
                if (items.isEmpty) return const SizedBox.shrink();

                final restName = details['restaurant_name']?.toString() ?? 'Restaurant';
                final restAddress = details['restaurant_address']?.toString() ?? 'Pickup location';
                final deliveryAddress = order['delivery_address']?.toString() ?? 'Delivery location';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DELIVERY DETAILS',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.storefront_rounded, size: 20, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                restName,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                restAddress,
                                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(left: 9.5, top: 4, bottom: 4),
                      child: SizedBox(
                        height: 20,
                        child: VerticalDivider(
                          color: AppColors.primary,
                          thickness: 2,
                        ),
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on_rounded, size: 20, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Delivery Drop-off',
                                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                deliveryAddress,
                                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.route_outlined, color: AppColors.primary, size: 20),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Distance', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                                    Text('${details['distance_km'] ?? '0.0'} km', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.timer_outlined, color: AppColors.primary, size: 20),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Duration', style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                                    Text('${details['duration_min'] ?? '0'} mins', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'ORDER ITEMS',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...items.map((item) {
                      final name = item['name']?.toString() ?? '';
                      final qty = item['quantity'] ?? 1;
                      final price =
                          (item['price_at_order'] as num?)?.toDouble() ?? 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '${qty}x $name',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Text(
                              fmt.format(price * qty),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 20),
                  ],
                );
              },
            ),

            const Text(
              'FARE BREAKDOWN',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.textSecondary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            const Divider(color: AppColors.divider),
            const SizedBox(height: 12),
            _breakdownRow('Items Total', fmt.format(itemTotal)),
            _breakdownRow('Delivery Fee', fmt.format(deliveryFee)),
            if (discount > 0)
              _breakdownRow('Discount', fmt.format(discount), isNegative: true),
            const SizedBox(height: 12),
            const Divider(color: AppColors.divider, thickness: 2),
            const SizedBox(height: 12),
            _breakdownRow('Total Paid', fmt.format(finalAmount), isBold: true),
            const SizedBox(height: 40),
            const Center(
              child: Text(
                'Thank you for ordering with Ziggo!',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
