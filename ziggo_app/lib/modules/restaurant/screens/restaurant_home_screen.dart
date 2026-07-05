import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/auth_provider.dart';
import '../../common/screens/merchant_pending_screen.dart';
import '../../market_vendor/market_vendor_provider.dart';
import '../../market_vendor/screens/market_vendor_home_screen.dart';
import '../../market_vendor/screens/market_vendor_ads_screen.dart';
import '../restaurant_provider.dart';
import '../widgets/image_picker_tile.dart';
import 'restaurant_commission_screen.dart';
import 'restaurant_earnings_screen.dart';
import 'restaurant_menu_screen.dart';
import 'restaurant_order_detail_screen.dart';
import 'restaurant_profile_edit_screen.dart';

class RestaurantHomeScreen extends StatefulWidget {
  const RestaurantHomeScreen({super.key});

  @override
  State<RestaurantHomeScreen> createState() => _RestaurantHomeScreenState();
}

class _RestaurantHomeScreenState extends State<RestaurantHomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _bootstrapped = false;
  bool _historyLoaded = false;
  RestaurantProvider? _pingSource;
  int _lastPing = 0;
  int _lastApproval = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(_maybeLoadHistory);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = context.read<RestaurantProvider>();
    if (_pingSource != p) {
      _pingSource?.newOrderPing.removeListener(_onNewOrderPing);
      _pingSource?.approvalPing.removeListener(_onApprovalPing);
      _pingSource = p;
      _lastPing = p.newOrderPing.value;
      _lastApproval = p.approvalPing.value;
      p.newOrderPing.addListener(_onNewOrderPing);
      p.approvalPing.addListener(_onApprovalPing);
    }
  }

  void _onApprovalPing() {
    final v = _pingSource?.approvalPing.value ?? 0;
    if (v == _lastApproval || !mounted) return;
    _lastApproval = v;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.celebration_rounded,
            color: AppColors.success, size: 40),
        title: const Text('You are approved!', textAlign: TextAlign.center),
        content: const Text(
          'Your restaurant is now live on Ziggo. New orders will start flowing in immediately.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Let\'s go'),
          ),
        ],
      ),
    );
  }

  void _onNewOrderPing() {
    final v = _pingSource?.newOrderPing.value ?? 0;
    if (v == _lastPing || !mounted) return;
    _lastPing = v;
    // Pop to the home if the user is deep inside another route — keeps the
    // new-order moment loud and unmissable.
    _tabs.animateTo(0);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.notifications_active_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'New order — check the Pending tab',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  @override
  void dispose() {
    _pingSource?.newOrderPing.removeListener(_onNewOrderPing);
    _pingSource?.approvalPing.removeListener(_onApprovalPing);
    _tabs.removeListener(_maybeLoadHistory);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_bootstrapped) return;
    _bootstrapped = true;
    final auth = context.read<AuthProvider>();
    final r = context.read<RestaurantProvider>();
    final m = context.read<MarketVendorProvider>();
    if (auth.token != null) {
      // Bootstrap both portals — a single owner can run a restaurant AND a
      // market stall under the same login. If they only have a market stall
      // (admin-created or self-registered without a restaurant), the build()
      // method routes them to the market home directly.
      await r.bootstrap(auth.token!);
      if (!m.hasProfile) {
        await m.bootstrap(auth.token!);
      }
    }
  }

  void _maybeLoadHistory() {
    if (_tabs.index == 2 && !_historyLoaded) {
      _historyLoaded = true;
      context.read<RestaurantProvider>().loadHistory();
    }
  }

  Future<void> _confirmLogout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 36),
        title: const Text('Log out?', textAlign: TextAlign.center),
        content: const Text(
          'You will need to sign in again with your phone number.',
          textAlign: TextAlign.center,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  child: const Text(
                    'Log out',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RestaurantProvider>();
    final m = context.watch<MarketVendorProvider>();

    // Wait for both providers to attempt their /me load before deciding
    // which screen to show. Without this, a 200-null response from either
    // endpoint would leave the UI stuck on a spinner forever.
    if (!r.profileLoaded || !m.profileLoaded) {
      return const _LoadingScreen();
    }

    // If the owner registered a market stall but no restaurant (e.g. they
    // picked "Set up market stall instead" on the registration screen, or
    // they're an admin-pre-created market_owner who happened to OTP-login
    // via the restaurant card), hand them straight to the market home.
    if (!r.hasProfile && m.hasProfile) {
      return const MarketVendorHomeScreen();
    }

    if (!r.hasProfile) {
      // Self-registration disabled — admin is the only path. Show a
      // "contact admin" screen with the phone number they signed in with so
      // they can give it to their account manager.
      return const MerchantPendingScreen(
        businessType: 'Restaurant',
        icon: Icons.restaurant_rounded,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(
              onLogout: _confirmLogout,
              onOpenMenu: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RestaurantMenuScreen(),
                ),
              ),
              onOpenEarnings: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RestaurantEarningsScreen(),
                ),
              ),
              onOpenProfile: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RestaurantProfileEditScreen(),
                ),
              ),
              onOpenAds: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MarketVendorAdsScreen(),
                ),
              ),
              onOpenCommission: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RestaurantCommissionScreen(),
                ),
              ),
            ),
            if (!r.isApproved) const _PendingApprovalBanner(),
            if (r.isApproved) const _TodayStatsCard(),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                boxShadow: AppStyles.shadowSm,
              ),
              child: TabBar(
                controller: _tabs,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                ),
                indicatorPadding: const EdgeInsets.all(4),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondary,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0.4,
                ),
                tabs: [
                  Tab(text: 'Pending (${r.pendingOrders.length})'),
                  Tab(text: 'Active (${r.activeOrders.length})'),
                  const Tab(text: 'History'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _OrderList(
                    orders: r.pendingOrders,
                    onTap: (o) => _openOrder(o),
                    emptyIcon: Icons.notifications_active_rounded,
                    emptyText: 'No new orders right now.\nYou will be notified when one comes in.',
                    onRefresh: r.loadOrders,
                    isLoading: r.loadingOrders,
                  ),
                  _OrderList(
                    orders: r.activeOrders,
                    onTap: (o) => _openOrder(o),
                    emptyIcon: Icons.restaurant_menu_rounded,
                    emptyText: 'No active orders.\nAccepted orders show up here.',
                    onRefresh: r.loadOrders,
                    isLoading: r.loadingOrders,
                  ),
                  _OrderList(
                    orders: r.historyOrders,
                    onTap: (o) => _openOrder(o),
                    emptyIcon: Icons.history_rounded,
                    emptyText: 'No past orders yet.',
                    onRefresh: r.loadHistory,
                    isLoading: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openOrder(Map<String, dynamic> order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RestaurantOrderDetailScreen(order: order),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onLogout;
  final VoidCallback onOpenMenu;
  final VoidCallback onOpenEarnings;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenAds;
  final VoidCallback onOpenCommission;
  const _Header({
    required this.onLogout,
    required this.onOpenMenu,
    required this.onOpenEarnings,
    required this.onOpenProfile,
    required this.onOpenAds,
    required this.onOpenCommission,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RestaurantProvider>();
    final p = r.profile ?? const <String, dynamic>{};
    final isOpen = r.isOpen;
    final canToggle = r.isApproved;
    final coverUrl = resolveImageUrl(p['image_url']?.toString());

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        boxShadow: AppStyles.shadowLg,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          if (coverUrl != null)
            Positioned.fill(
              child: Image.network(
                coverUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: coverUrl == null
                      ? const [
                          Color(0xFF172554),
                          Color(0xFF1E40AF),
                          Color(0xFF3B82F6),
                        ]
                      : [
                          const Color(0xFF0F172A).withOpacity(0.78),
                          const Color(0xFF1E40AF).withOpacity(0.72),
                          const Color(0xFF3B82F6).withOpacity(0.65),
                        ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
            child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'ZIGGO MERCHANT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 36,
                height: 36,
                child: PopupMenuButton<VoidCallback>(
                  color: const Color(0xFF1E293B),
                  surfaceTintColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                    icon: Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 20),
                    ),
                    onSelected: (fn) => fn(),
                    offset: const Offset(0, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: onOpenAds,
                        child: Row(
                          children: [
                            const Icon(Icons.campaign_rounded, color: Colors.white70, size: 20),
                            const SizedBox(width: 12),
                            const Text('Ads', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: onOpenEarnings,
                        child: Row(
                          children: [
                            const Icon(Icons.bar_chart_rounded, color: Colors.white70, size: 20),
                            const SizedBox(width: 12),
                            const Text('Earnings', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: onOpenCommission,
                        child: Row(
                          children: [
                            const Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 20),
                            const SizedBox(width: 12),
                            const Text('Commission', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: onOpenMenu,
                        child: Row(
                          children: [
                            const Icon(Icons.menu_book_rounded, color: Colors.white70, size: 20),
                            const SizedBox(width: 12),
                            const Text('Menu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: onOpenProfile,
                        child: Row(
                          children: [
                            const Icon(Icons.edit_rounded, color: Colors.white70, size: 20),
                            const SizedBox(width: 12),
                            const Text('Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: onLogout,
                        child: Row(
                          children: [
                            const Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
                            const SizedBox(width: 12),
                            const Text('Log out', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: onOpenProfile,
            child: Text(
              p['name']?.toString() ?? 'Your restaurant',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.place_rounded, color: Colors.white70, size: 14),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  p['address']?.toString() ?? '',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: canToggle && isOpen
                              ? AppColors.success
                              : AppColors.warning,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (canToggle && isOpen
                                      ? AppColors.success
                                      : AppColors.warning)
                                  .withOpacity(0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        !canToggle
                            ? 'Pending approval'
                            : (isOpen ? 'Open for orders' : 'Currently closed'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Opacity(
                opacity: canToggle ? 1 : 0.5,
                child: Switch.adaptive(
                  value: isOpen,
                  activeColor: Colors.white,
                  activeTrackColor: AppColors.success,
                  inactiveTrackColor: Colors.white24,
                  onChanged: canToggle
                      ? (v) async {
                          final ok = await context
                              .read<RestaurantProvider>()
                              .toggleOnline(v);
                          if (!context.mounted || ok) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not update status'),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _PendingApprovalBanner extends StatelessWidget {
  const _PendingApprovalBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        border: Border.all(color: AppColors.warning.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.2),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.hourglass_top_rounded,
                color: AppColors.warning, size: 18),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Waiting for approval',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Your restaurant will appear to customers once admin approves it.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
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

class _OrderList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final void Function(Map<String, dynamic>) onTap;
  final IconData emptyIcon;
  final String emptyText;
  final Future<void> Function() onRefresh;
  final bool isLoading;

  const _OrderList({
    required this.orders,
    required this.onTap,
    required this.emptyIcon,
    required this.emptyText,
    required this.onRefresh,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: orders.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(emptyIcon, size: 44, color: AppColors.textTertiary),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  emptyText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: orders.length,
              itemBuilder: (_, i) => EntranceSlide(
                delay: Duration(milliseconds: 50 * i),
                child: _OrderCard(order: orders[i], onTap: () => onTap(orders[i])),
              ),
            ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final VoidCallback onTap;
  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = order['status']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.receipt_long_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order['order_ref']?.toString() ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          order['customer_name']?.toString() ??
                              order['customer_phone']?.toString() ??
                              'Customer',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'Rs.${(order['final_amount'] as num? ?? 0).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _StatusPill(status: status),
                  const Spacer(),
                  Text(
                    (order['payment_method'] ?? '').toString().toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 1,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textTertiary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayStatsCard extends StatelessWidget {
  const _TodayStatsCard();

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RestaurantProvider>();
    final s = r.todayStats ?? const <String, dynamic>{};
    final orders = (s['today_orders'] as num?)?.toInt() ?? 0;
    final delivered = (s['today_delivered'] as num?)?.toInt() ?? 0;
    final inFlight = (s['today_in_flight'] as num?)?.toInt() ?? 0;
    final revenue = (s['today_revenue'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatTile(
              label: 'TODAY',
              value: 'Rs.${revenue.toStringAsFixed(0)}',
              subtitle: '$delivered delivered',
              color: AppColors.success,
              icon: Icons.attach_money_rounded,
            ),
          ),
          Container(width: 1, height: 38, color: AppColors.divider),
          Expanded(
            child: _StatTile(
              label: 'ORDERS',
              value: '$orders',
              subtitle: '$inFlight in progress',
              color: AppColors.primary,
              icon: Icons.receipt_long_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;
  const _StatTile({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final tone = _toneFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: tone,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Color _toneFor(String s) {
    switch (s) {
      case 'pending':
        return AppColors.warning;
      case 'confirmed':
      case 'preparing':
        return AppColors.info;
      case 'ready_for_pickup':
        return AppColors.primary;
      case 'out_for_delivery':
        return AppColors.accent;
      case 'delivered':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
    }
    return AppColors.textSecondary;
  }
}
