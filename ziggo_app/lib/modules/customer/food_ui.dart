import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_colors.dart';
import '../../app/app_styles.dart';
import '../../core/network/api_client.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/skeleton.dart';
import 'food_provider.dart';

/// Shared building blocks for the food module so every screen — home, category,
/// restaurant detail, checkout, tracking — speaks the same visual language:
/// image-forward, borderless soft-shadow cards, one money format, one rating chip.

/// Format an LKR amount the way the rest of the app does: `Rs.<int>` with
/// thousands grouping and no stray decimals (Rs.180, Rs.1,250).
String formatRs(num? value) {
  final n = (value ?? 0).round();
  final neg = n < 0;
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return 'Rs.${neg ? '-' : ''}$buf';
}

/// One decimal rating, or `null` when the restaurant has no rating yet.
String? formatRating(num? rating) {
  if (rating == null || rating <= 0) return null;
  return rating.toStringAsFixed(1);
}

/// Resolve an image path that may be remote (http) or a backend-relative
/// `/static` path into a fully-qualified URL.
String? resolveFoodAsset(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '${ApiConfig.baseHost}$path';
}

/// Network image with a consistent muted placeholder + graceful error state.
/// Used for every food/restaurant photo so fallbacks look intentional.
class FoodImage extends StatelessWidget {
  final String? url;
  final double? width;
  final double height;
  final double radius;
  final IconData icon;
  final BoxFit fit;

  const FoodImage({
    super.key,
    required this.url,
    required this.height,
    this.width,
    this.radius = AppStyles.radiusSm,
    this.icon = Icons.restaurant_rounded,
    this.fit = BoxFit.cover,
  });

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: AppColors.surfaceMuted,
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.textTertiary, size: height * 0.32),
      );

  @override
  Widget build(BuildContext context) {
    final resolved = resolveFoodAsset(url);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: resolved == null
          ? _placeholder()
          : Image.network(
              resolved,
              width: width,
              height: height,
              fit: fit,
              loadingBuilder: (_, child, progress) =>
                  progress == null ? child : Skeleton(width: width, height: height, radius: radius),
              errorBuilder: (_, __, ___) => _placeholder(),
            ),
    );
  }
}

/// Compact green rating chip (★ 4.5). Shows a neutral "New" chip when there is
/// no rating yet — the convention standard food apps use.
class RatingPill extends StatelessWidget {
  final num? rating;
  final num? distanceKm;

  const RatingPill({super.key, required this.rating, this.distanceKm});

  @override
  Widget build(BuildContext context) {
    final value = formatRating(rating);
    final dist = distanceKm != null ? ' · ${(distanceKm!).toStringAsFixed(1)} km' : '';
    if (value == null) {
      return _wrap(
        color: AppColors.textSecondary,
        bg: AppColors.surfaceMuted,
        icon: Icons.star_rounded,
        text: 'New$dist',
      );
    }
    return _wrap(
      color: AppColors.success,
      bg: AppColors.success.withOpacity(0.12),
      icon: Icons.star_rounded,
      text: '$value$dist',
    );
  }

  Widget _wrap({
    required Color color,
    required Color bg,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Small veg / non-veg square indicator (green / red), as used in SL/IN apps.
class VegDot extends StatelessWidget {
  final bool isVeg;
  const VegDot({super.key, required this.isVeg});

  @override
  Widget build(BuildContext context) {
    final c = isVeg ? AppColors.success : AppColors.error;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        border: Border.all(color: c, width: 1.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Center(
        child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
      ),
    );
  }
}

/// The single menu-item row used by both the restaurant detail menu and the
/// category dish list. Image-right with an overlapping add / quantity control —
/// the standard food-app pattern. Pass [subtitle] to show the restaurant name
/// (used on the category screen, where dishes from many outlets are mixed).
class DishTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic> restaurant;
  final String? subtitle;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  const DishTile({
    super.key,
    required this.item,
    required this.restaurant,
    this.subtitle,
    this.onTap,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    final food = context.watch<FoodProvider>();
    final id = item['id'] as int;
    final qty = (food.cart[id]?['quantity'] as int?) ?? 0;
    final available = item['is_available'] != false;
    final price = (item['price'] as num?) ?? 0;
    final desc = item['description']?.toString() ?? '';

    return Padding(
      padding: margin,
      child: Pressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppStyles.radiusMd),
            boxShadow: AppStyles.shadowSm,
          ),
          child: Opacity(
            opacity: available ? 1 : 0.55,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          VegDot(isVeg: item['is_veg'] == true),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item['name']?.toString() ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                          ),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textTertiary,
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        formatRs(price),
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _trailing(context, available, qty),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _trailing(BuildContext context, bool available, int qty) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: FoodImage(url: item['image_url']?.toString(), height: 92, width: 92, radius: 14, icon: Icons.fastfood_rounded),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            right: 6,
            child: _control(context, available, qty),
          ),
        ],
      ),
    );
  }

  Widget _control(BuildContext context, bool available, int qty) {
    if (!available) {
      return Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          boxShadow: AppStyles.shadowSm,
        ),
        child: const Text(
          'SOLD OUT',
          style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w900, fontSize: 9, letterSpacing: 0.5),
        ),
      );
    }
    if (qty == 0) {
      return GestureDetector(
        onTap: () {
          final food = context.read<FoodProvider>();
          food.setActiveRestaurant(restaurant);
          food.addToCart(item);
        },
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.primary, width: 1.4),
            boxShadow: AppStyles.shadowSm,
          ),
          child: const Text(
            'ADD',
            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1),
          ),
        ),
      );
    }
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _stepBtn(Icons.remove_rounded, () => context.read<FoodProvider>().changeQty(item['id'] as int, -1)),
          Text('$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13)),
          _stepBtn(Icons.add_rounded, () => context.read<FoodProvider>().changeQty(item['id'] as int, 1)),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(width: 28, height: 30, child: Icon(icon, color: Colors.white, size: 16)),
    );
  }
}

/// Skeleton placeholder matching [DishTile]'s footprint.
class DishTileSkeleton extends StatelessWidget {
  const DishTileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          boxShadow: AppStyles.shadowSm,
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 140, height: 14),
                  SizedBox(height: 10),
                  Skeleton(width: 200, height: 11),
                  SizedBox(height: 6),
                  Skeleton(width: 90, height: 11),
                  SizedBox(height: 12),
                  Skeleton(width: 60, height: 14),
                ],
              ),
            ),
            SizedBox(width: 12),
            Skeleton(width: 92, height: 92, radius: 14),
          ],
        ),
      ),
    );
  }
}

/// Skeleton placeholder matching the home/list restaurant card.
class RestaurantCardSkeleton extends StatelessWidget {
  const RestaurantCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(height: 150, radius: AppStyles.radiusMd),
          Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 160, height: 16),
                SizedBox(height: 10),
                Skeleton(width: 220, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
