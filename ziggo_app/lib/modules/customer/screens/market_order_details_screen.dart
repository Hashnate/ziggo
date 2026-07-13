import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';

class MarketOrderDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> order;

  const MarketOrderDetailsScreen({super.key, required this.order});

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
        '/market/orders/$orderId/details',
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
    final appUsageCharge = (order['app_usage_charge'] as num?)?.toDouble() ?? 0.0;
    final discount = (order['discount_amount'] as num?)?.toDouble() ?? 0.0;
    final itemTotal = finalAmount - deliveryFee - appUsageCharge + discount;

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
            Center(
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

                final storeName = details['store_name']?.toString() ?? 'Store';
                final storeAddress = details['store_address']?.toString() ?? 'Pickup location';
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
                                storeName,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                storeAddress,
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
                    Builder(builder: (context) {
                      final driverRaw = details['driver'];
                      final driverData = driverRaw is Map ? driverRaw : null;
                      if (driverData == null) return const SizedBox.shrink();

                      final driverName = driverData['full_name']?.toString() ?? 'Driver';
                      final driverRating = driverData['rating']?.toString() ?? '4.5';
                      final vehiclePlate = driverData['vehicle_number']?.toString() ?? 'N/A';
                      final serviceType = (driverData['vehicle_type'] ?? 'car').toString();
                      String? driverPhoto = driverData['profile_photo']?.toString();
                      if (driverPhoto != null && driverPhoto.isNotEmpty && driverPhoto.startsWith('/')) {
                        driverPhoto = '${ApiConfig.baseHost}$driverPhoto';
                      }

                      return Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4)),
                            ],
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: Colors.grey.shade100,
                                backgroundImage: driverPhoto != null && driverPhoto.isNotEmpty ? NetworkImage(driverPhoto) : null,
                                child: driverPhoto == null || driverPhoto.isEmpty ? const Icon(Icons.person, color: Colors.black26, size: 28) : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(driverName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.star_rounded, color: Colors.orange, size: 16),
                                        const SizedBox(width: 4),
                                        Text(driverRating, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black54)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      _vehicleAsset(serviceType),
                                      width: 36,
                                      height: 36,
                                      errorBuilder: (context, error, stackTrace) => Icon(_vehicleIcon(serviceType), size: 24, color: Colors.black54),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(vehiclePlate, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                                    if (serviceType.isNotEmpty)
                                      Text(
                                        '${serviceType[0].toUpperCase()}${serviceType.substring(1)}',
                                        style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
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
            if (deliveryFee > 0) _breakdownRow('Delivery Fee', fmt.format(deliveryFee)),
            if (appUsageCharge > 0) _breakdownRow('App usage charge', fmt.format(appUsageCharge)),
            if (discount > 0)
              _breakdownRow('Discount', fmt.format(discount), isNegative: true),
            const SizedBox(height: 12),
            const Divider(color: AppColors.divider, thickness: 2),
            const SizedBox(height: 12),
            _breakdownRow('Total Paid', fmt.format(finalAmount), isBold: true),
            const SizedBox(height: 40),
            Center(
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

  IconData _vehicleIcon(String type) {
    switch (type.toLowerCase()) {
      case 'bike':
        return Icons.motorcycle_rounded;
      case 'tuk':
        return Icons.electric_rickshaw_rounded;
      case 'van':
        return Icons.airport_shuttle_rounded;
      case 'truck':
        return Icons.local_shipping_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  String _vehicleAsset(String? type) {
    switch (type?.toLowerCase()) {
      case 'bike': return 'assets/icons/bike.png';
      case 'tuk': return 'assets/icons/tuk.png';
      case 'truck': return 'assets/icons/truck.png';
      case 'mini': return 'assets/icons/car.png';
      case 'van':
      case 'car':
      default: return 'assets/icons/car.png';
    }
  }
}
