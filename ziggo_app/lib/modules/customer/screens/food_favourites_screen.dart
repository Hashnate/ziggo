import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/motion.dart';
import '../food_provider.dart';
import 'food_home_screen.dart';

class FoodFavouritesScreen extends StatelessWidget {
  const FoodFavouritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FoodProvider>();
    
    // We only show favorites from the loaded list of restaurants.
    final list = provider.restaurants;
    final favRestaurants = list.where((r) => provider.isFavorite(r['id'] as int)).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Favourites',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: favRestaurants.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 150,
                      height: 150,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.food.withOpacity(0.07),
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        width: 84,
                        height: 84,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.heart_broken_rounded,
                            size: 42, color: AppColors.food),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'No favourite restaurants',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'You can add favourite restaurants by clicking the "Heart" icon '
                      'on a restaurant card or page.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              itemCount: favRestaurants.length,
              itemBuilder: (context, i) {
                return EntranceSlide(
                  delay: Duration(milliseconds: 45 * i),
                  child: RestaurantCard(restaurant: favRestaurants[i]),
                );
              },
            ),
    );
  }
}
