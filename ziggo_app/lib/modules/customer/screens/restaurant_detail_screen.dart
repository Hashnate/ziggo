import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../food_provider.dart';
import 'checkout_screen.dart';


class RestaurantDetailScreen extends StatefulWidget {
  final int restaurantId;
  const RestaurantDetailScreen({super.key, required this.restaurantId});

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  late Future<Map<String, dynamic>?> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = context.read<FoodProvider>().fetchRestaurantDetail(widget.restaurantId);
  }

  @override
  Widget build(BuildContext context) {
    final food = context.watch<FoodProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _detailFuture,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final r = snap.data;
          if (r == null) {
            return const Center(
              child: Text('Restaurant not found',
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            );
          }

          final categories = (r['categories'] as List).cast<Map<String, dynamic>>();
          final items = (r['items'] as List).cast<Map<String, dynamic>>();
          final byCat = <int, List<Map<String, dynamic>>>{};
          for (final it in items) {
            final cid = (it['category_id'] as int?) ?? 0;
            byCat.putIfAbsent(cid, () => []).add(it);
          }

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                expandedHeight: 280,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 10, top: 6),
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 16, top: 6),
                    child: GestureDetector(
                      onTap: () => _showPayQrCode(context, r),
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.qr_code_2_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(

                  titlePadding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                  title: Text(
                    r['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 60, 24, 60),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.22),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            (r['cuisine']?.toString() ?? '').toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Info chips card
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: AppStyles.shadowMd,
                  ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _infoChip(
                            icon: Icons.star_rounded,
                            color: AppColors.success,
                            label: '${r['rating']}',
                            sub: 'rating',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: AppColors.divider,
                        ),
                        Expanded(
                          child: _infoChip(
                            icon: Icons.timer_rounded,
                            color: AppColors.warning,
                            label: '${r['eta_minutes']} min',
                            sub: 'delivery',
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 36,
                          color: AppColors.divider,
                        ),
                        Expanded(
                          child: _infoChip(
                            icon: Icons.delivery_dining_rounded,
                            color: AppColors.primary,
                            label: 'Rs.${r['delivery_fee']}',
                            sub: 'fee',
                          ),
                        ),
                      ],
                    ),
                  ),
              ),
              SliverList(
                delegate: SliverChildListDelegate([
                  for (final cat in categories) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
                      child: Row(
                        children: [
                          Container(
                            width: 4,
                            height: 18,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            cat['name']?.toString() ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...(byCat[cat['id'] as int] ?? []).map(
                      (it) => _MenuItemRow(item: it, restaurant: r),
                    ),
                  ],
                  const SizedBox(height: 100),
                ]),
              ),
            ],
          );
        },
      ),
      floatingActionButton: food.cart.isEmpty || food.activeRestaurantId != widget.restaurantId
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CheckoutScreen()),
                ),
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: AppStyles.shadowLg,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${food.cartCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'View cart',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Rs.${food.cartTotal.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _infoChip({
    required IconData icon,
    required Color color,
    required String label,
    required String sub,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            Text(
              sub,
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showPayQrCode(BuildContext context, Map<String, dynamic> restaurant) {
    final qrData = 'ziggopay://pay?type=restaurant&id=${restaurant['id']}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              restaurant['name']?.toString() ?? 'Merchant',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Scan to Pay QR Code',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              qrData,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
        ),
        actions: [
          Center(
            child: SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _MenuItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic> restaurant;
  const _MenuItemRow({required this.item, required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final food = context.watch<FoodProvider>();
    final qty = (food.cart[item['id'] as int]?['quantity'] as int?) ?? 0;
    final available = item['is_available'] != false;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Opacity(
        opacity: available ? 1 : 0.55,
        child: Row(
        children: [
          if (item['image_url'] != null && item['image_url'].toString().isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                item['image_url'].toString(),
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 80, height: 80, color: AppColors.surfaceMuted),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: item['is_veg'] == true ? AppColors.success : AppColors.error,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Center(
                        child: Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: item['is_veg'] == true ? AppColors.success : AppColors.error,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item['name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ),
                    if (!available)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'SOLD OUT',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                  ],
                ),
                if ((item['description']?.toString() ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      item['description'].toString(),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Rs.${(item['price'] as num).toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: !available
                ? Container(
                    key: const ValueKey('soldout'),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'UNAVAILABLE',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        letterSpacing: 0.8,
                      ),
                    ),
                  )
                : qty == 0
                ? GestureDetector(
                    key: const ValueKey('add'),
                    onTap: () {
                      context.read<FoodProvider>().setActiveRestaurant(restaurant);
                      context.read<FoodProvider>().addToCart(item);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Text(
                        'ADD',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  )
                : Container(
                    key: const ValueKey('qty'),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () =>
                              context.read<FoodProvider>().changeQty(item['id'] as int, -1),
                          icon: const Icon(Icons.remove_rounded, color: Colors.white),
                          constraints: const BoxConstraints(maxHeight: 32, maxWidth: 32),
                          padding: EdgeInsets.zero,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '$qty',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              context.read<FoodProvider>().changeQty(item['id'] as int, 1),
                          icon: const Icon(Icons.add_rounded, color: Colors.white),
                          constraints: const BoxConstraints(maxHeight: 32, maxWidth: 32),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      ),
    );
  }
}
