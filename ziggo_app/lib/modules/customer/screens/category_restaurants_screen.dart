import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/skeleton.dart';
import '../food_provider.dart';
import '../food_ui.dart';
import 'checkout_screen.dart';
import 'restaurant_detail_screen.dart';

class CategoryRestaurantsScreen extends StatefulWidget {
  final Map<String, dynamic> category;

  const CategoryRestaurantsScreen({super.key, required this.category});

  @override
  State<CategoryRestaurantsScreen> createState() => _CategoryRestaurantsScreenState();
}

class _CategoryRestaurantsScreenState extends State<CategoryRestaurantsScreen> {
  List<Map<String, dynamic>> _restaurants = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchCategoryRestaurants();
  }

  Future<void> _fetchCategoryRestaurants() async {
    try {
      final p = context.read<FoodProvider>();
      final qp = <String, dynamic>{'category_id': widget.category['id']};
      if (p.deliveryLat != null && p.deliveryLng != null) {
        qp['lat'] = p.deliveryLat;
        qp['lng'] = p.deliveryLng;
      }
      final resp = await ApiClient.instance.dio.get('/food/restaurants', queryParameters: qp);

      if (!mounted) return;
      setState(() {
        _restaurants = List<Map<String, dynamic>>.from(
          (resp.data as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)),
        );
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.category['name']?.toString() ?? 'Category';
    final cartCount = context.select<FoodProvider, int>((f) => f.cartCount);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          name,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? _loadingState()
          : _restaurants.isEmpty
              ? _empty()
              : ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 120),
                  itemCount: _restaurants.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          "${_restaurants.length} place${_restaurants.length == 1 ? '' : 's'} serving $name",
                          style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      );
                    }
                    final idx = i - 1;
                    return EntranceSlide(
                      delay: Duration(milliseconds: 50 * idx),
                      child: _RestaurantSection(
                        restaurant: _restaurants[idx],
                        category: widget.category,
                      ),
                    );
                  },
                ),
      bottomNavigationBar: cartCount == 0 ? null : const _CartBar(),
    );
  }

  Widget _loadingState() {
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: List.generate(
        3,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Skeleton(width: 180, height: 18),
              ),
              DishTileSkeleton(),
              DishTileSkeleton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(28)),
            child: const Icon(Icons.restaurant_menu_rounded, size: 44, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 18),
          const Text('No restaurants found', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }
}

class _RestaurantSection extends StatefulWidget {
  final Map<String, dynamic> restaurant;
  final Map<String, dynamic> category;

  const _RestaurantSection({required this.restaurant, required this.category});

  @override
  State<_RestaurantSection> createState() => _RestaurantSectionState();
}

class _RestaurantSectionState extends State<_RestaurantSection> {
  late Future<Map<String, dynamic>?> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = context.read<FoodProvider>().fetchRestaurantDetail(widget.restaurant['id'] as int);
  }

  void _openDetail() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: widget.restaurant['id'] as int)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _detailFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Column(
            children: [
              _HeaderSkeleton(),
              DishTileSkeleton(),
            ],
          );
        }
        final r = snap.data;
        if (r == null) return const SizedBox.shrink();

        final allItems = (r['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final internalCategories = (r['categories'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final globalCatName = widget.category['name']?.toString().toLowerCase() ?? '';

        final matchingCatIds = internalCategories
            .where((c) => c['name']?.toString().toLowerCase().contains(globalCatName) ?? false)
            .map((c) => c['id'])
            .toSet();

        var matchedItems = allItems.where((it) {
          final isCatMatch = matchingCatIds.contains(it['category_id']);
          final isNameMatch = it['name']?.toString().toLowerCase().contains(globalCatName) ?? false;
          return isCatMatch || isNameMatch;
        }).toList();

        // The backend already tagged this restaurant with the category, so it
        // genuinely serves it — never hide it just because no dish name happens
        // to contain the category word. Fall back to its available menu.
        if (matchedItems.isEmpty) {
          matchedItems = allItems.where((it) => it['is_available'] != false).toList();
        }

        if (matchedItems.isEmpty) return const SizedBox.shrink();
        final shown = matchedItems.take(3).toList();
        final extra = matchedItems.length - shown.length;

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(r),
              ...shown.map(
                (it) => DishTile(
                  item: it,
                  restaurant: widget.restaurant,
                  onTap: _openDetail,
                ),
              ),
              if (extra > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  child: GestureDetector(
                    onTap: _openDetail,
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Text(
                          'See all ${matchedItems.length} items',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 13),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_forward_rounded, size: 16, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(Map<String, dynamic> r) {
    final eta = r['eta_minutes'];
    final fee = r['delivery_fee'] as num?;
    final dist = widget.restaurant['distance_km'] as num?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Pressable(
        onTap: _openDetail,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        child: Row(
          children: [
            FoodImage(url: r['image_url']?.toString(), height: 52, width: 52, radius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r['name']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      RatingPill(rating: r['rating'] as num?, distanceKm: dist),
                      const SizedBox(width: 8),
                      const Icon(Icons.timer_rounded, size: 13, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        '${eta ?? 30} min',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.delivery_dining_rounded, size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        formatRs(fee),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Skeleton(width: 52, height: 52, radius: 14),
          SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Skeleton(width: 140, height: 15),
              SizedBox(height: 8),
              Skeleton(width: 180, height: 12),
            ],
          ),
        ],
      ),
    );
  }
}

/// Floating "view cart" bar shown once the user adds an item from the category
/// list, mirroring the restaurant detail screen.
class _CartBar extends StatelessWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context) {
    final food = context.watch<FoodProvider>();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
              borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              boxShadow: AppStyles.shadowLg,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    '${food.cartCount}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 12),
                const Text('View cart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
                const Spacer(),
                Text(
                  formatRs(food.cartTotal),
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
