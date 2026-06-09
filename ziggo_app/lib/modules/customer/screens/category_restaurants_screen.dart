import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import '../food_provider.dart';
import 'food_home_screen.dart';

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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  itemCount: _restaurants.length,
                  itemBuilder: (context, i) {
                    return EntranceSlide(
                      delay: Duration(milliseconds: 55 * i),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: RestaurantCard(restaurant: _restaurants[i]),
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
