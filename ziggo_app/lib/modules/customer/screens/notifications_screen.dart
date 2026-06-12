import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../notifications_provider.dart';
import '../booking_provider.dart';
import 'ride_tracking_screen.dart';
import 'ride_history_screen.dart';
import 'food_tracking_screen.dart';
import 'market_tracking_screen.dart';
import 'promotions_screen.dart';
import 'wallet_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p = context.read<NotificationsProvider>();
      await p.refresh();
      await p.markAllAsRead();
    });
  }

  ({IconData icon, Color color}) _styleFor(String type) {
    switch (type) {
      case 'ride_update':
        return (icon: Icons.directions_car_rounded, color: AppColors.flash);
      case 'order_update':
        return (icon: Icons.restaurant_rounded, color: AppColors.primary);
      case 'market_order_update':
        return (icon: Icons.shopping_basket_rounded, color: AppColors.market);
      case 'promo':
        return (icon: Icons.local_offer_rounded, color: AppColors.success);
      case 'payment':
        return (icon: Icons.payments_rounded, color: AppColors.warning);
      case 'system':
        return (icon: Icons.campaign_rounded, color: AppColors.bike);
      default:
        return (icon: Icons.notifications_rounded, color: AppColors.textSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<NotificationsProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Row(
          children: [
            const Text('Notifications'),
            if (p.unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${p.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => p.refresh(),
        child: p.loading && p.items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : p.items.isEmpty
                ? _EmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: p.items.length,
                    itemBuilder: (_, i) {
                      final n = p.items[i];
                      final type = (n['type'] ?? '').toString();
                      final unread = n['is_read'] != true;
                      final style = _styleFor(type);
                      return EntranceSlide(
                        delay: Duration(milliseconds: 45 * i),
                        child: GestureDetector(
                        onTap: () => _onNotificationTap(context, n),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: unread ? style.color.withOpacity(0.4) : AppColors.cardBorder,
                              width: unread ? 1.5 : 1,
                            ),
                            boxShadow: unread ? AppStyles.shadowSm : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  gradient: AppColors.serviceGradient(style.color),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(style.icon, color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            n['title']?.toString() ?? '',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 14,
                                              color: unread
                                                  ? AppColors.textPrimary
                                                  : AppColors.textSecondary,
                                            ),
                                          ),
                                        ),
                                        if (unread)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: style.color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    if ((n['body']?.toString() ?? '').isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        n['body'].toString(),
                                        style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      (n['created_at']?.toString().substring(0, 16) ?? ''),
                                      style: const TextStyle(
                                        color: AppColors.textTertiary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      );
                    },
                  ),
      ),
    );
  }

  void _onNotificationTap(BuildContext context, Map<String, dynamic> n) async {
    final type = (n['type'] ?? '').toString();
    final body = (n['body'] ?? '').toString();

    // Mark as read
    context.read<NotificationsProvider>().markRead(n['id'] as int);

    // Extract reference from body (e.g. ZG62C3F4F7, FOA1B2C3D4, MK1A2B3C4D)
    final match = RegExp(r'\b(ZG|CR|FL|RT|FO|MK|EV)[0-9A-Z]{8}\b').firstMatch(body);
    final String? ref = match?.group(0);

    if (ref != null) {
      if (ref.startsWith('ZG') || ref.startsWith('CR') || ref.startsWith('FL') || ref.startsWith('RT')) {
        // Ride/Courier/Flash/Rental
        final bp = context.read<BookingProvider>();
        await bp.loadActive();
        if (context.mounted) {
          if (bp.activeBooking != null && bp.activeBooking!['booking_ref'] == ref) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RideTrackingScreen()),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RideHistoryScreen()),
            );
          }
        }
        return;
      } else if (ref.startsWith('FO')) {
        // Food Order
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FoodTrackingScreen(orderRef: ref)),
        );
        return;
      } else if (ref.startsWith('MK')) {
        // Market Order
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MarketTrackingScreen(orderRef: ref)),
        );
        return;
      }
    }

    // Fallbacks based on notification type if no reference matched in body
    if (type == 'promo') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PromotionsScreen()),
      );
    } else if (type == 'payment') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WalletScreen()),
      );
    } else if (type == 'ride_update') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RideHistoryScreen()),
      );
    }
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 140),
        Center(
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
                child: const Icon(
                  Icons.notifications_off_rounded,
                  size: 48,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No notifications yet',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const SizedBox(height: 4),
              const Text(
                "We'll let you know when something happens",
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
