import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import '../market_provider.dart';
import 'customer_shell.dart';
import 'market_checkout_screen.dart';
import 'market_vendor_screen.dart';

class MarketHomeScreen extends StatefulWidget {
  const MarketHomeScreen({super.key});

  @override
  State<MarketHomeScreen> createState() => _MarketHomeScreenState();
}

class _MarketHomeScreenState extends State<MarketHomeScreen> {
  String _query = '';
  String _category = 'All';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MarketProvider>().refreshVendors();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
      return;
    }
    final shell = context.findAncestorStateOfType<CustomerShellState>();
    shell?.goToTab(2);
  }

  IconData _categoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('pharm')) return Icons.medical_services_rounded;
    if (c.contains('groc')) return Icons.shopping_basket_rounded;
    if (c.contains('elect')) return Icons.devices_rounded;
    if (c.contains('bake') || c.contains('bread')) return Icons.bakery_dining_rounded;
    return Icons.storefront_rounded;
  }

  Color _categoryColor(String category) {
    final c = category.toLowerCase();
    if (c.contains('pharm')) return AppColors.error;
    if (c.contains('groc')) return AppColors.success;
    if (c.contains('elect')) return AppColors.info;
    if (c.contains('bake') || c.contains('bread')) return AppColors.warning;
    return AppColors.primary;
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    final q = _query.trim().toLowerCase();
    return all.where((v) {
      if (_category != 'All') {
        final c = (v['category']?.toString() ?? '').toLowerCase();
        if (!c.contains(_category.toLowerCase())) return false;
      }
      if (q.isEmpty) return true;
      final name = (v['name']?.toString() ?? '').toLowerCase();
      final cat = (v['category']?.toString() ?? '').toLowerCase();
      return name.contains(q) || cat.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MarketProvider>();
    final vendors = _filtered(p.vendors);
    final categories = _availableCategories(p.vendors);
    final hasCart = p.cart.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => p.refreshVendors(),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _hero()),
            SliverToBoxAdapter(child: _categoryStrip(categories)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, hasCart ? 100 : 24),
              sliver: p.loading && p.vendors.isEmpty
                  ? _skeletonList()
                  : vendors.isEmpty
                      ? SliverToBoxAdapter(child: _empty())
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => EntranceSlide(
                              delay: Duration(milliseconds: 55 * i),
                              child: _vendorCard(vendors[i]),
                            ),
                            childCount: vendors.length,
                          ),
                        ),
            ),
          ],
        ),
      ),
      bottomSheet: hasCart ? _cartBar(p) : null,
    );
  }

  List<String> _availableCategories(List<Map<String, dynamic>> all) {
    final set = <String>{};
    for (final v in all) {
      final c = v['category']?.toString().trim();
      if (c != null && c.isNotEmpty) set.add(c);
    }
    return ['All', ...set];
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _handleBack,
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    'ZIGGO MART',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Shop essentials',
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Groceries, pharmacy, electronics & more',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            _searchField(),
          ],
        ),
      ),
    );
  }

  Widget _searchField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                hintText: 'Search shops or categories',
                hintStyle: TextStyle(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 16),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                setState(() => _query = '');
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _categoryStrip(List<String> cats) {
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        itemBuilder: (_, i) {
          final c = cats[i];
          final selected = _category == c;
          return GestureDetector(
            onTap: () => setState(() => _category = c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.cardBorder,
                ),
              ),
              child: Center(
                child: Text(
                  c,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: cats.length,
      ),
    );
  }

  Widget _vendorCard(Map<String, dynamic> v) {
    final category = v['category']?.toString() ?? '';
    final color = _categoryColor(category);
    final isOpenNow = v['is_open_now'] != false;
    final coverUrl = _resolveCover(v['image_url']?.toString());
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MarketVendorScreen(vendor: v)),
      ),
      child: Opacity(
        opacity: isOpenNow ? 1 : 0.65,
        child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppStyles.shadowSm,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: coverUrl == null
                  ? Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color.withOpacity(0.18), color.withOpacity(0.08)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(_categoryIcon(category), color: color, size: 28),
                    )
                  : Image.network(
                      coverUrl,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: AppColors.surfaceMuted,
                        child: Icon(_categoryIcon(category),
                            color: color, size: 28),
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          v['name']?.toString() ?? '',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!isOpenNow)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'CLOSED',
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.star_rounded, color: AppColors.warning, size: 14),
                      const SizedBox(width: 2),
                      Text(
                        '${v['rating'] ?? '—'}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  if ((v['address']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.place_rounded,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            v['address']!.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textTertiary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
      ),
    );
  }

  String? _resolveCover(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${ApiConfig.baseHost}$path';
  }

  Widget _cartBar(MarketProvider p) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MarketCheckoutScreen()),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${p.cartCount}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'View cart',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                Text(
                  'Rs.${p.cartTotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _skeletonList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, __) => Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: AppStyles.shadowSm,
          ),
          child: Shimmer.fromColors(
            baseColor: AppColors.surfaceMuted,
            highlightColor: Colors.white,
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 14, width: 160, color: Colors.black12),
                      const SizedBox(height: 8),
                      Container(height: 10, width: 80, color: Colors.black12),
                      const SizedBox(height: 6),
                      Container(height: 10, width: 120, color: Colors.black12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        childCount: 4,
      ),
    );
  }

  Widget _empty() {
    final filtering = _query.isNotEmpty || _category != 'All';
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
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(
                filtering ? Icons.search_off_rounded : Icons.storefront_rounded,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              filtering ? 'No results' : 'No vendors available',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              filtering
                  ? 'Try a different search or category'
                  : 'Pull to refresh',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (filtering) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {
                    _query = '';
                    _category = 'All';
                  });
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
