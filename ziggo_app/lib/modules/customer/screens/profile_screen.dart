import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/auth_provider.dart';
import '../wallet_provider.dart';
import '../promos_provider.dart';
import 'promotions_screen.dart';
import 'ride_history_screen.dart';
import 'saved_addresses_screen.dart';
import 'subscription_screen.dart';
import 'support_screen.dart';
import 'wallet_screen.dart';
import 'payment_methods_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletProvider>().refresh();
    });
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final wallet = context.watch<WalletProvider>();
    final promos = context.watch<PromosProvider>();
    final name = auth.fullName ?? '';
    final initial = name.isNotEmpty
        ? name[0].toUpperCase()
        : (auth.phoneNumber?.isNotEmpty ?? false
            ? auth.phoneNumber![auth.phoneNumber!.length - 1]
            : 'Z');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: staggered([
          GestureDetector(
            onTap: () => _open(const EditProfileScreen()),
            child: _heroCard(name: name, phone: auth.phoneNumber ?? '', initial: initial, role: auth.role ?? 'customer', profilePhoto: auth.profilePhoto),
          ),
          const SizedBox(height: 16),
          _walletStrip(balance: wallet.balance, currency: wallet.currency),
          const SizedBox(height: 10),
          _loyaltyStrip(points: promos.points, value: promos.pointsValue),
          // BRD: CD-34 — profile completeness ring (only shown when there's
          // still work to do).
          if (auth.completeness != null &&
              ((auth.completeness!['percent'] as num?)?.toInt() ?? 100) < 100) ...[
            const SizedBox(height: 10),
            _completenessStrip(auth.completeness!),
          ],
          const SizedBox(height: 22),
          _sectionLabel('ACCOUNT'),
          const SizedBox(height: 10),
          _menuCard(items: [
            _MenuItem(
              icon: Icons.account_balance_wallet_rounded,
              color: AppColors.primary,
              label: 'My Wallet',
              subtitle: 'Top up & transactions',
              onTap: () => _open(const WalletScreen()),
            ),
            _MenuItem(
              icon: Icons.credit_card_rounded,
              color: AppColors.accent,
              label: 'Payment Methods',
              subtitle: 'Manage saved cards',
              onTap: () => _open(const PaymentMethodsScreen()),
            ),
            _MenuItem(
              icon: Icons.receipt_long_rounded,
              color: AppColors.info,
              label: 'My Rides',
              subtitle: 'History & receipts',
              onTap: () => _open(const RideHistoryScreen()),
            ),
            _MenuItem(
              icon: Icons.bookmark_rounded,
              color: AppColors.flash,
              label: 'Saved Places',
              subtitle: 'Home, work & favourites',
              onTap: () => _open(const SavedAddressesScreen()),
            ),
          ]),
          const SizedBox(height: 22),
          _sectionLabel('PERKS & SUPPORT'),
          const SizedBox(height: 10),
          _menuCard(items: [
            _MenuItem(
              icon: Icons.local_offer_rounded,
              color: AppColors.success,
              label: 'Promotions',
              subtitle: 'Active codes & offers',
              onTap: () => _open(const PromotionsScreen()),
            ),
            _MenuItem(
              icon: Icons.workspace_premium_rounded,
              color: AppColors.accent,
              label: 'Ziggo Gold',
              subtitle: 'Premium subscription',
              onTap: () => _open(const SubscriptionScreen()),
            ),
            _MenuItem(
              icon: Icons.support_agent_rounded,
              color: AppColors.warning,
              label: 'Help & Support',
              subtitle: 'Chat with our team',
              onTap: () => _open(const SupportScreen()),
            ),
          ]),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Ziggo • v1.0.0',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _heroCard({
    required String name,
    required String phone,
    required String initial,
    required String role,
    String? profilePhoto,
  }) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.32),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 74,
            height: 74,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              image: profilePhoto != null && profilePhoto.isNotEmpty
                  ? DecorationImage(
                      image: profilePhoto.startsWith('http')
                          ? NetworkImage(profilePhoto)
                          : FileImage(File(profilePhoto)) as ImageProvider,
                      fit: BoxFit.cover,
                    )
                  : null,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryDark.withOpacity(0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: profilePhoto == null || profilePhoto.isEmpty
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    role.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  name.isEmpty ? 'Add your name' : name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.phone_rounded, color: Colors.white70, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 28),
        ],
      ),
    );
  }

  /// BRD: RW-01 — loyalty points balance strip below the wallet card.
  Widget _loyaltyStrip({required int points, required double value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0x14F59E0B),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.stars_rounded, color: AppColors.warning, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LOYALTY POINTS',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    )),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('$points',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        )),
                    const SizedBox(width: 4),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Text('pts',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          )),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('≈ Rs.${value.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textSecondary,
                  letterSpacing: 0.5,
                )),
          ),
        ],
      ),
    );
  }

  Widget _walletStrip({required double balance, required String currency}) {
    return GestureDetector(
      onTap: () => _open(const WalletScreen()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: AppStyles.shadowSm,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.account_balance_wallet_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WALLET BALANCE',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rs.${balance.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(100),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'TOP UP',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  Widget _menuCard({required List<_MenuItem> items}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _menuRow(items[i]),
            if (i < items.length - 1)
              const Divider(height: 1, indent: 70, color: AppColors.divider),
          ],
        ],
      ),
    );
  }

  Widget _menuRow(_MenuItem item) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: item.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(item.icon, color: item.color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  /// BRD: CD-34 — strip that nudges the user to finish their profile.
  Widget _completenessStrip(Map<String, dynamic> c) {
    final percent = ((c['percent'] as num?)?.toInt() ?? 0).clamp(0, 100);
    final missing = (c['missing'] as List?)?.cast<String>() ?? const <String>[];
    final friendly = {
      'full_name': 'Add your name',
      'email': 'Add an email',
      'profile_photo': 'Upload a photo',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 48, height: 48,
                  child: CircularProgressIndicator(
                    value: percent / 100,
                    strokeWidth: 5,
                    backgroundColor: AppColors.surfaceMuted,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                Text('$percent%',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      color: AppColors.textPrimary,
                    )),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PROFILE COMPLETENESS',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    )),
                const SizedBox(height: 2),
                Text(
                  missing.isEmpty
                      ? 'Your profile looks great.'
                      : missing.map((k) => friendly[k] ?? k).join(' · '),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _MenuItem {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
}
