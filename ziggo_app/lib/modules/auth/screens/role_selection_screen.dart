import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/motion.dart';
import 'phone_login_screen.dart';
import 'registration_screen.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  void _navigateToLogin(BuildContext context, String role) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PhoneLoginScreen(role: role)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 36),
                  EntranceSlide(
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(34),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.16),
                            Colors.white.withOpacity(0.03),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.14),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.55),
                            blurRadius: 48,
                            spreadRadius: 2,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          'assets/images/logo.jpeg',
                          width: 96,
                          height: 96,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 90),
                    child: Text(
                      'WELCOME TO',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.55),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const EntranceSlide(
                    delay: Duration(milliseconds: 150),
                    child: ZiggoWordmark(onDark: true, size: 84),
                  ),
                  const SizedBox(height: 18),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 220),
                    child: Text(
                      'Your all-in-one platform for rides, food,\ndelivery and groceries across Sri Lanka.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 14.5,
                        height: 1.55,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 320),
                    child: _RoleCard(
                      title: 'RIDE & ORDER',
                      subtitle: 'Book rides, food, market & parcels',
                      icon: Icons.bolt_rounded,
                      featured: true,
                      onTap: () => _navigateToLogin(context, 'customer'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 400),
                    child: _RoleCard(
                      title: 'DRIVE & EARN',
                      subtitle: 'Join the fleet and start earning',
                      icon: Icons.directions_car_filled_rounded,
                      featured: false,
                      onTap: () => _navigateToLogin(context, 'driver'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 460),
                    child: _RoleCard(
                      title: 'RUN A RESTAURANT',
                      subtitle: 'Manage your restaurant orders and menus',
                      icon: Icons.restaurant_rounded,
                      featured: false,
                      onTap: () => _navigateToLogin(context, 'restaurant_owner'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 500),
                    child: _RoleCard(
                      title: 'MANAGE MARKET PLACE',
                      subtitle: 'Supermarkets, stalls, and grocery stores',
                      icon: Icons.storefront_rounded,
                      featured: false,
                      onTap: () => _navigateToLogin(context, 'market_owner'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 540),
                    child: Pressable(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegistrationScreen(),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.14),
                          ),
                        ),
                        child: Text.rich(
                          TextSpan(
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withOpacity(0.75),
                              fontWeight: FontWeight.w600,
                            ),
                            children: const [
                              TextSpan(text: "New to Ziggo?  "),
                              TextSpan(
                                text: 'Create an account',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        );
      }
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool featured;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.featured,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: featured
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
              )
            : null,
        color: featured ? null : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withOpacity(featured ? 0.18 : 0.10),
        ),
        boxShadow: featured
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.45),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: featured
                  ? Colors.white.withOpacity(0.18)
                  : AppColors.primary.withOpacity(0.18),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              icon,
              color: featured ? Colors.white : AppColors.primaryLight,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(featured ? 0.85 : 0.5),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white.withOpacity(featured ? 1 : 0.3),
            size: 20,
          ),
        ],
      ),
    );

    return Pressable(onTap: onTap, child: card);
  }
}
