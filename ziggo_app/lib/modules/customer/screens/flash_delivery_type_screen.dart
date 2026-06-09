import 'package:flutter/material.dart';
import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import 'flash_home_screen.dart';
import 'courier_home_screen.dart';

class FlashDeliveryTypeScreen extends StatefulWidget {
  const FlashDeliveryTypeScreen({super.key});

  @override
  State<FlashDeliveryTypeScreen> createState() => _FlashDeliveryTypeScreenState();
}

class _FlashDeliveryTypeScreenState extends State<FlashDeliveryTypeScreen> {
  void _showIWantToSheet({bool isCourier = false}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.primarySoft, // Ziggo brand soft blue
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 24),
                const Text(
                  'I want to',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildActionTypeCard(
                    title: 'Send',
                    icon: Icons.arrow_upward_rounded,
                    iconBg: AppColors.primary,
                    cardBg: AppColors.primarySoft, // Ziggo brand soft blue
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => FlashHomeScreen(isSend: true, isCourier: isCourier)),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildActionTypeCard(
                    title: 'Receive',
                    icon: Icons.arrow_downward_rounded,
                    iconBg: AppColors.primaryLight, // Blue for receive
                    cardBg: AppColors.primarySoft, // Ziggo brand soft blue
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => FlashHomeScreen(isSend: false, isCourier: isCourier)),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Select if you want to send or receive',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTypeCard({
    required String title,
    required IconData icon,
    required Color iconBg,
    required Color cardBg,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.black.withOpacity(0.05)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.topCenter,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Icon(Icons.inventory_2_rounded, size: 54, color: Color(0xFFB4835A)), // Box color
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(icon, color: Colors.white, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primarySoft, // Ziggo brand soft blue background
      body: SafeArea(
        child: Column(
          children: [
            // App Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ),

            // Illustration
            const Spacer(),
            Icon(Icons.inventory_2_rounded, size: 80, color: AppColors.primary.withOpacity(0.7)), // Ziggo blue box
            const SizedBox(height: 24),
            
            // Text
            const Text(
              'Pick a delivery type',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Now you have options to select for\ninstant delivery and courier',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const Spacer(),

            // Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildDeliveryCard(
                    title: 'Flash',
                    subtitle: 'Instant Delivery',
                    icon: Icons.flash_on_rounded,
                    iconColor: AppColors.primary, // Ziggo primary blue
                    onTap: _showIWantToSheet,
                  ),
                  const SizedBox(height: 12),
                  _buildDeliveryCard(
                    title: 'Courier',
                    subtitle: '2-3 Delivery Days',
                    icon: Icons.schedule_rounded,
                    iconColor: AppColors.primaryDark, // Ziggo dark blue
                    isNew: true,
                    bullets: [
                      'Island-wide delivery coverage',
                      'Affordable weight-based pricing',
                      'Powered by CityPak',
                    ],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CourierHomeScreen()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: AppColors.blackGradient, // Ziggo branded dark bottom bar
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.workspace_premium_rounded, color: Colors.white70, size: 18),
            SizedBox(width: 8),
            Text(
              'Recommended for deliveries over 10 km',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    bool isNew = false,
    List<String> bullets = const [],
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon Stack
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 6),
                      child: Icon(Icons.inventory_2_rounded, color: AppColors.primary.withOpacity(0.7), size: 36),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: iconColor, size: 16),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (isNew) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'New',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (bullets.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        ...bullets.map((b) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Icon(Icons.stars_rounded, size: 14, color: AppColors.primaryLight),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  b,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )).toList(),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
