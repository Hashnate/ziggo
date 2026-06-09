import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';

/// Favourite outlets. No favourites backend yet, so this shows the empty
/// state; outlet cards will populate it once the heart action is wired.
class MarketFavouritesScreen extends StatelessWidget {
  const MarketFavouritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
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
      body: Center(
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
                  color: AppColors.primary.withOpacity(0.07),
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
                      size: 42, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 26),
              const Text(
                'No favourite outlets added',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can add favourite outlets by clicking the "Heart" icon '
                'on an outlet card or at the top of the outlet page.',
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
      ),
    );
  }
}
