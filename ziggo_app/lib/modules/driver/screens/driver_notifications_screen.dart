import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../../customer/notifications_provider.dart';
import '../driver_provider.dart';
import '../driver_theme.dart';
import 'driver_documents_screen.dart';
import 'driver_earnings_screen.dart';
import 'driver_history_screen.dart';
import 'driver_profile_screen.dart';

class DriverNotificationsScreen extends StatefulWidget {
  const DriverNotificationsScreen({super.key});

  @override
  State<DriverNotificationsScreen> createState() =>
      _DriverNotificationsScreenState();
}

class _DriverNotificationsScreenState extends State<DriverNotificationsScreen> {
  String _selectedFilter = 'all'; // 'all', 'rides', 'earnings', 'system'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationsProvider>().refresh();
    });
  }

  ({IconData icon, Color color, String category}) _getNotificationStyle(
      String type, String body, String title) {
    final t = type.toLowerCase().trim();
    final titleLower = title.toLowerCase().trim();

    // 1. Explicit payment / earnings / payout
    if (t == 'payment' ||
        t == 'earnings' ||
        t == 'payout' ||
        t == 'wallet' ||
        titleLower.contains('payout') ||
        titleLower.contains('commission deducted') ||
        titleLower.contains('wallet top') ||
        titleLower.contains('tip received') ||
        titleLower.contains('cancellation fee')) {
      return (
        icon: Icons.account_balance_wallet_rounded,
        color: AppColors.success,
        category: 'earnings',
      );
    }

    // 2. Rides, deliveries, and bookings
    if (t == 'ride_update' ||
        t == 'order_update' ||
        t == 'market_order_update' ||
        t == 'booking' ||
        titleLower.contains('ride') ||
        titleLower.contains('trip') ||
        titleLower.contains('booking') ||
        titleLower.contains('delivery') ||
        titleLower.contains('pickup')) {
      return (
        icon: Icons.directions_car_filled_rounded,
        color: AppColors.primary,
        category: 'rides',
      );
    }

    // 3. KYC and verification documents
    if (t == 'kyc' ||
        t == 'document' ||
        t == 'verification' ||
        titleLower.contains('document') ||
        titleLower.contains('kyc') ||
        titleLower.contains('license') ||
        titleLower.contains('nic verification') ||
        titleLower.contains('approval')) {
      return (
        icon: Icons.verified_user_rounded,
        color: AppColors.warning,
        category: 'system',
      );
    }

    // 4. Promos and surge incentives
    if (t == 'promo' ||
        t == 'surge' ||
        t == 'bonus' ||
        titleLower.contains('promo') ||
        titleLower.contains('surge') ||
        titleLower.contains('incentive')) {
      return (
        icon: Icons.local_fire_department_rounded,
        color: AppColors.flash,
        category: 'system',
      );
    }

    // 5. General announcements / system notices / welcome messages
    return (
      icon: Icons.campaign_rounded,
      color: const Color(0xFF2563EB),
      category: 'system',
    );
  }

  String _formatDate(dynamic rawDate) {
    if (rawDate == null) return '';
    try {
      final dt = DateTime.parse(rawDate.toString()).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) {
        return 'Just now';
      } else if (diff.inHours < 1) {
        return '${diff.inMinutes}m ago';
      } else if (diff.inHours < 24 && dt.day == now.day) {
        return DateFormat('hh:mm a').format(dt);
      } else if (diff.inDays < 7) {
        return '${DateFormat('EEE').format(dt)}, ${DateFormat('hh:mm a').format(dt)}';
      } else {
        return DateFormat('MMM d, yyyy · hh:mm a').format(dt);
      }
    } catch (_) {
      return rawDate.toString().substring(0, 16);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifs = context.watch<NotificationsProvider>();
    final allItems = notifs.items;

    // Filter items based on active chip
    final filteredItems = allItems.where((n) {
      if (_selectedFilter == 'all') return true;
      final type = (n['type'] ?? '').toString();
      final body = (n['body'] ?? '').toString();
      final title = (n['title'] ?? '').toString();
      final style = _getNotificationStyle(type, body, title);
      return style.category == _selectedFilter;
    }).toList();

    return Theme(
      data: driverTheme(context),
      child: Scaffold(
        backgroundColor: kDriverBg,
        appBar: AppBar(
          backgroundColor: kDriverBg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              const Text(
                'Notifications',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: AppColors.textPrimary,
                ),
              ),
              if (notifs.unreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${notifs.unreadCount}',
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
          actions: [
            if (notifs.unreadCount > 0)
              TextButton.icon(
                onPressed: () => notifs.markAllAsRead(),
                icon: const Icon(Icons.done_all_rounded,
                    size: 16, color: AppColors.primary),
                label: const Text(
                  'Mark all read',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            const SizedBox(width: 6),
          ],
        ),
        body: Column(
          children: [
            _buildFilterChips(allItems),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => notifs.refresh(),
                child: notifs.loading && allItems.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      )
                    : filteredItems.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: filteredItems.length,
                            itemBuilder: (context, i) {
                              final item = filteredItems[i];
                              return EntranceSlide(
                                delay: Duration(milliseconds: 30 * i),
                                child: _buildNotificationCard(context, item),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips(List<Map<String, dynamic>> items) {
    int unreadTotal = 0;
    int unreadRides = 0;
    int unreadEarnings = 0;
    int unreadSystem = 0;

    for (final item in items) {
      final isUnread = item['is_read'] != true;
      if (isUnread) {
        unreadTotal++;
        final type = (item['type'] ?? '').toString();
        final body = (item['body'] ?? '').toString();
        final title = (item['title'] ?? '').toString();
        final cat = _getNotificationStyle(type, body, title).category;
        if (cat == 'rides') unreadRides++;
        if (cat == 'earnings') unreadEarnings++;
        if (cat == 'system') unreadSystem++;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _chip('all', 'All', unreadTotal),
          const SizedBox(width: 8),
          _chip('rides', 'Rides & Trips', unreadRides),
          const SizedBox(width: 8),
          _chip('earnings', 'Earnings & Wallet', unreadEarnings),
          const SizedBox(width: 8),
          _chip('system', 'System & KYC', unreadSystem),
        ],
      ),
    );
  }

  Widget _chip(String key, String label, int unreadCount) {
    final isSelected = _selectedFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryDark : kDriverCard,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected ? AppColors.primaryDark : AppColors.divider,
            width: 1.2,
          ),
          boxShadow: isSelected ? AppStyles.shadowSm : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.25)
                      : AppColors.error,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
      BuildContext context, Map<String, dynamic> item) {
    final isUnread = item['is_read'] != true;
    final type = (item['type'] ?? '').toString();
    final title = (item['title'] ?? 'Notification').toString();
    final body = (item['body'] ?? '').toString();
    final rawDate = item['created_at'];
    final timeStr = _formatDate(rawDate);

    final style = _getNotificationStyle(type, body, title);

    // Look for booking or order reference code in the body or data
    final refMatch =
        RegExp(r'\b(ZG|CR|FL|RT|FO|MK|EV)[0-9A-Z]{8}\b').firstMatch(body);
    final String? refCode = refMatch?.group(0);

    return GestureDetector(
      onTap: () => _handleItemTap(context, item, style.category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnread ? Colors.white : kDriverCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUnread
                ? style.color.withOpacity(0.5)
                : AppColors.divider.withOpacity(0.6),
            width: isUnread ? 1.5 : 1.0,
          ),
          boxShadow: isUnread ? AppStyles.shadowSm : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon container with colored gradient
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    style.color.withOpacity(0.85),
                    style.color,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(style.icon, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 12),
            // Text info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight:
                                isUnread ? FontWeight.w900 : FontWeight.w700,
                            fontSize: 14,
                            color: isUnread
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      if (isUnread) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 4),
                          decoration: BoxDecoration(
                            color: style.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        color: isUnread
                            ? AppColors.textPrimary.withOpacity(0.85)
                            : AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight:
                            isUnread ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded,
                          size: 11, color: AppColors.textTertiary),
                      const SizedBox(width: 4),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (refCode != null) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Text(
                            refCode,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 90,
                height: 90,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 44,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No notifications yet',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  'Trip updates, payout alerts, KYC status, and system notices will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleItemTap(
      BuildContext context, Map<String, dynamic> item, String category) async {
    final notifs = context.read<NotificationsProvider>();
    final id = item['id'];
    if (id is int) {
      notifs.markRead(id);
    }

    final type = (item['type'] ?? '').toString().toLowerCase().trim();
    final title = (item['title'] ?? '').toString().toLowerCase().trim();
    final body = (item['body'] ?? '').toString();

    // Check for trip/order ref
    final match =
        RegExp(r'\b(ZG|CR|FL|RT|FO|MK|EV)[0-9A-Z]{8}\b').firstMatch(body);
    final String? ref = match?.group(0);

    // Deep-linking based on explicit categorization
    if (ref != null ||
        type == 'ride_update' ||
        type == 'order_update' ||
        type == 'market_order_update' ||
        category == 'rides') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DriverHistoryScreen()),
      );
    } else if (type == 'payment' ||
        type == 'earnings' ||
        type == 'payout' ||
        (category == 'earnings' &&
            (title.contains('payout') ||
                title.contains('commission') ||
                title.contains('wallet')))) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DriverEarningsScreen()),
      );
    } else if (type == 'kyc' ||
        type == 'document' ||
        title.contains('document') ||
        title.contains('kyc') ||
        title.contains('license')) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const DriverDocumentsScreen()),
      );
    }
    // General system announcements stay in the notifications screen and simply mark as read.
  }
}
