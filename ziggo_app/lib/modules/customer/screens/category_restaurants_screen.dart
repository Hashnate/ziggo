import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import '../food_provider.dart';
import 'food_home_screen.dart';
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
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.category['name']?.toString() ?? 'Category',
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.food))
          : _restaurants.isEmpty
              ? _empty()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  itemCount: _restaurants.length,
                  itemBuilder: (context, i) {
                    return EntranceSlide(
                      delay: Duration(milliseconds: 55 * i),
                      child: _RestaurantCategoryCard(
                        restaurant: _restaurants[i],
                        category: widget.category,
                      ),
                    );
                  },
                ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
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
              child: const Icon(Icons.restaurant_menu_rounded, size: 44, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 18),
            const Text(
              'No restaurants found',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class _RestaurantCategoryCard extends StatefulWidget {
  final Map<String, dynamic> restaurant;
  final Map<String, dynamic> category;

  const _RestaurantCategoryCard({required this.restaurant, required this.category});

  @override
  State<_RestaurantCategoryCard> createState() => _RestaurantCategoryCardState();
}

class _RestaurantCategoryCardState extends State<_RestaurantCategoryCard> {
  late Future<Map<String, dynamic>?> _detailFuture;

  @override
  void initState() {
    super.initState();
    _detailFuture = context.read<FoodProvider>().fetchRestaurantDetail(widget.restaurant['id'] as int);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: RestaurantCard(restaurant: widget.restaurant),
        ),
        FutureBuilder<Map<String, dynamic>?>(
          future: _detailFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done || snap.data == null) {
              return const SizedBox(height: 16);
            }
            final r = snap.data!;
            final allItems = (r['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final matchedItems = allItems.where((it) => it['category_id'] == widget.category['id']).toList();

            if (matchedItems.isEmpty) return const SizedBox(height: 16);

            return Transform.translate(
              offset: const Offset(0, -12), // Pull up slightly to reduce gap from the 20px bottom margin
              child: SizedBox(
                height: 150,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: matchedItems.length,
                  itemBuilder: (context, index) {
                    final item = matchedItems[index];
                    return _MatchedItemCard(item: item, restaurant: widget.restaurant);
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MatchedItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final Map<String, dynamic> restaurant;
  const _MatchedItemCard({required this.item, required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final img = item['image_url']?.toString();
    final price = (item['price'] as num).toStringAsFixed(0);
    return GestureDetector(
      onTap: () {
         Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: restaurant['id'] as int)),
         );
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
                child: img != null && img.isNotEmpty
                    ? Image.network(img, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: AppColors.surfaceMuted))
                    : Container(color: AppColors.surfaceMuted, width: double.infinity, child: const Icon(Icons.fastfood_rounded, color: AppColors.textTertiary)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('Rs.$price', style: const TextStyle(fontWeight: FontWeight.w900, color: AppColors.primary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
