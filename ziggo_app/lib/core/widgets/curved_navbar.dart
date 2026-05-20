import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_colors.dart';
import '../../app/app_styles.dart';

/// Foodix-style floating bottom navigation: a soft-shadowed white pill with
/// five slots — the middle one (Home) is a raised, gradient circle that lifts
/// above the bar. Indexes: 0 Mart · 1 Rides · 2 Home (center) · 3 Alerts · 4 Profile.
class CurvedNavbar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const CurvedNavbar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  void _tap(int i) {
    HapticFeedback.selectionClick();
    onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: SizedBox(
          height: 78,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              // The floating white bar
              Container(
                height: 66,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppStyles.radiusLg),
                  boxShadow: AppStyles.shadowMd,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NavItem(
                      icon: Icons.storefront_rounded,
                      label: 'Mart',
                      active: currentIndex == 0,
                      onTap: () => _tap(0),
                    ),
                    _NavItem(
                      icon: Icons.directions_car_rounded,
                      label: 'Rides',
                      active: currentIndex == 1,
                      onTap: () => _tap(1),
                    ),
                    const SizedBox(width: 64), // gap cradling the center FAB
                    _NavItem(
                      icon: Icons.notifications_rounded,
                      label: 'Alerts',
                      active: currentIndex == 3,
                      onTap: () => _tap(3),
                    ),
                    _NavItem(
                      icon: Icons.person_rounded,
                      label: 'Profile',
                      active: currentIndex == 4,
                      onTap: () => _tap(4),
                    ),
                  ],
                ),
              ),
              // Raised center Home button
              Positioned(
                bottom: 30,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onTap(2);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: 60,
                    height: 60,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 5),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(
                              currentIndex == 2 ? 0.5 : 0.3),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.home_rounded,
                        color: Colors.white, size: 26),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.textTertiary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 62,
        height: 66,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 23, color: color),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                letterSpacing: 0.2,
                color: color,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
