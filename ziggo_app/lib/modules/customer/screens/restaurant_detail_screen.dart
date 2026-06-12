import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../food_provider.dart';
import '../food_ui.dart';
import 'checkout_screen.dart';

class RestaurantDetailScreen extends StatefulWidget {
  final int restaurantId;
  const RestaurantDetailScreen({super.key, required this.restaurantId});

  @override
  State<RestaurantDetailScreen> createState() => _RestaurantDetailScreenState();
}

class _RestaurantDetailScreenState extends State<RestaurantDetailScreen> {
  late Future<Map<String, dynamic>?> _detailFuture;
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, GlobalKey> _sectionKeys = {};
  String _search = '';
  int _activeCategoryIndex = 0;

  @override
  void initState() {
    super.initState();
    _detailFuture = context.read<FoodProvider>().fetchRestaurantDetail(widget.restaurantId);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _sectionKeys.putIfAbsent(id, () => GlobalKey());

  void _scrollToSection(String keyId, int tabIndex) {
    setState(() => _activeCategoryIndex = tabIndex);
    final ctx = _keyFor(keyId).currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.0,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final food = context.watch<FoodProvider>();
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _detailFuture,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          final r = snap.data;
          if (r == null) {
            return const Center(
              child: Text('Restaurant not found', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            );
          }

          final categories = (r['categories'] as List).cast<Map<String, dynamic>>();
          final items = (r['items'] as List).cast<Map<String, dynamic>>();

          final byCat = <int, List<Map<String, dynamic>>>{};
          for (final it in items) {
            final cid = (it['category_id'] as int?) ?? 0;
            byCat.putIfAbsent(cid, () => []).add(it);
          }

          // Popular Picks come from the backend (most-ordered available items).
          final byId = {for (final it in items) it['id'] as int: it};
          final popularPicks = ((r['popular_item_ids'] as List?) ?? const [])
              .map((e) => byId[e as int])
              .whereType<Map<String, dynamic>>()
              .toList();

          final searching = _search.isNotEmpty;

          return CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              // 1. Cover Image Header (NOT an appbar, just a sliver that scrolls away)
              SliverToBoxAdapter(
                child: _buildHeader(r, food),
              ),

              // 2. Restaurant Info Text & Search
              SliverToBoxAdapter(
                child: _buildInfoSection(r),
              ),

              if (searching)
                ..._buildSearchResults(items, r)
              else ...[
                // 3. Popular Picks (real, most-ordered)
                if (popularPicks.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildPopularPicks(popularPicks, r),
                  ),

                // 4. Sticky Category Tabs
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyHeaderDelegate(
                    minHeight: 50,
                    maxHeight: 50,
                    child: Container(
                      color: Colors.white,
                      alignment: Alignment.centerLeft,
                      child: _buildCategoryTabs(popularPicks.isNotEmpty, categories, byCat),
                    ),
                  ),
                ),

                // 5. Category Lists
                _buildCategorySlivers(categories, byCat, r),
              ],
            ],
          );
        },
      ),
      floatingActionButton: _buildCartFab(food),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ----------- WIDGET BUILDERS -----------

  Widget _buildHeader(Map<String, dynamic> r, FoodProvider food) {
    final coverUrl = r['cover_url']?.toString() ?? r['image_url']?.toString();
    final logoUrl = r['image_url']?.toString();
    final firstLetter = (r['name']?.toString() ?? 'R').substring(0, 1).toUpperCase();
    final isFav = food.isFavorite(r['id'] as int);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Cover Image
        Container(
          height: 200,
          width: double.infinity,
          color: AppColors.surfaceMuted,
          child: coverUrl != null 
             ? Image.network(resolveFoodAsset(coverUrl) ?? '', fit: BoxFit.cover, errorBuilder: (_,__,___)=>const SizedBox())
             : const SizedBox(),
        ),
        // Action Buttons (Back & Icons)
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _circleBtn(Icons.arrow_back_rounded, () => Navigator.pop(context)),
              Row(
                children: [
                  _circleBtn(
                    isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded, 
                    () => food.toggleFavorite(r['id'] as int),
                    color: isFav ? Colors.red : Colors.black87,
                  ),
                  const SizedBox(width: 12),
                  _circleBtn(Icons.qr_code_2_rounded, () => _showPayQrCode(context, r)),
                ],
              ),
            ],
          ),
        ),
        // Logo (Overlapping)
        Positioned(
          bottom: -35,
          right: 16,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: AppStyles.shadowSm,
              border: Border.all(color: Colors.white, width: 3),
              image: logoUrl != null ? DecorationImage(image: NetworkImage(resolveFoodAsset(logoUrl) ?? ''), fit: BoxFit.cover) : null,
            ),
            child: logoUrl == null 
               ? Center(child: Text(firstLetter, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24)))
               : null,
          ),
        ),
      ],
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {Color color = Colors.black87}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildInfoSection(Map<String, dynamic> r) {
    final ratingStr = formatRating(r['rating'] as num?);
    final cuisine = r['cuisine']?.toString();
    final eta = r['eta_minutes'];
    final isOpenNow = r['is_open_now'] == true;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 42, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(r['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
              ),
              const SizedBox(width: 8),
              _openBadge(isOpenNow),
            ],
          ),
          if (cuisine != null && cuisine.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(cuisine, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.location_on, size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                   r['address']?.toString() ?? 'Location details not available',
                   style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                   maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.star_rounded, size: 16, color: ratingStr != null ? AppColors.warning : AppColors.textTertiary),
              const SizedBox(width: 4),
              Text(ratingStr ?? 'New', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('•', style: TextStyle(color: AppColors.textTertiary))),
              const Icon(Icons.timer_rounded, size: 14, color: AppColors.textTertiary),
              const SizedBox(width: 4),
              Text('Est: $eta mins', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('•', style: TextStyle(color: AppColors.textTertiary))),
              Text('Fee: ${formatRs(r['delivery_fee'] as num?)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 20),
          // Search Bar (filters this restaurant's menu)
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: AppColors.textTertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v.trim()),
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search in ${r['name']}',
                      hintStyle: const TextStyle(color: AppColors.textTertiary, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (_search.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchCtrl.clear();
                      setState(() => _search = '');
                      FocusScope.of(context).unfocus();
                    },
                    child: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _openBadge(bool isOpenNow) {
    final color = isOpenNow ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            isOpenNow ? 'Open' : 'Closed',
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildPopularPicks(List<Map<String, dynamic>> items, Map<String, dynamic> r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          key: _keyFor('popular'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: const Row(
            children: [
               Icon(Icons.star_rounded, color: AppColors.warning, size: 20),
               SizedBox(width: 8),
               Text('Popular Picks', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ],
          ),
        ),
        for (final it in items) DishTile(item: it, restaurant: r),
        const SizedBox(height: 8),
      ],
    );
  }

  // Tabs are built from the real sections: an optional Popular Picks tab plus
  // every category that actually has items. Tapping scrolls to the section.
  Widget _buildCategoryTabs(
    bool hasPopular,
    List<Map<String, dynamic>> categories,
    Map<int, List<Map<String, dynamic>>> byCat,
  ) {
    final tabs = <MapEntry<String, String>>[];
    if (hasPopular) tabs.add(const MapEntry('Popular Picks', 'popular'));
    for (final cat in categories) {
      final id = cat['id'] as int;
      if ((byCat[id] ?? const []).isNotEmpty) {
        tabs.add(MapEntry(cat['name']?.toString() ?? '', 'cat_$id'));
      }
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++)
            _catTab(tabs[i].key, i, tabs[i].value),
        ],
      ),
    );
  }

  Widget _catTab(String name, int index, String keyId) {
    final active = _activeCategoryIndex == index;
    return GestureDetector(
      onTap: () => _scrollToSection(keyId, index),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.textPrimary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? AppColors.textPrimary : AppColors.cardBorder),
        ),
        child: Text(
          name,
          style: TextStyle(
            color: active ? Colors.white : AppColors.textSecondary,
            fontWeight: active ? FontWeight.w900 : FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildCategorySlivers(
    List<Map<String, dynamic>> categories,
    Map<int, List<Map<String, dynamic>>> byCat,
    Map<String, dynamic> r,
  ) {
    final children = <Widget>[];
    for (final cat in categories) {
      final id = cat['id'] as int;
      final catItems = byCat[id] ?? const [];
      if (catItems.isEmpty) continue;
      children.add(Padding(
        key: _keyFor('cat_$id'),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(
          cat['name']?.toString().toUpperCase() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
      ));
      for (final it in catItems) {
        children.add(DishTile(item: it, restaurant: r));
      }
    }
    children.add(const SizedBox(height: 100));
    return SliverList(delegate: SliverChildListDelegate(children));
  }

  List<Widget> _buildSearchResults(List<Map<String, dynamic>> items, Map<String, dynamic> r) {
    final q = _search.toLowerCase();
    final results = items.where((it) {
      final name = it['name']?.toString().toLowerCase() ?? '';
      final desc = it['description']?.toString().toLowerCase() ?? '';
      return name.contains(q) || desc.contains(q);
    }).toList();

    if (results.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 40),
            child: Column(
              children: [
                const Icon(Icons.search_off_rounded, size: 48, color: AppColors.textTertiary),
                const SizedBox(height: 12),
                Text(
                  'No items match "$_search"',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      SliverList(
        delegate: SliverChildListDelegate([
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('RESULTS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: AppColors.textTertiary, letterSpacing: 0.5)),
          ),
          for (final it in results) DishTile(item: it, restaurant: r),
          const SizedBox(height: 100),
        ]),
      ),
    ];
  }

  Widget? _buildCartFab(FoodProvider food) {
    if (food.cart.isEmpty || food.activeRestaurantId != widget.restaurantId) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CheckoutScreen()),
        ),
        child: Container(
          height: 60,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppStyles.shadowLg,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${food.cartCount}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              const Text('View cart', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
              const Spacer(),
              Text('Rs.${food.cartTotal.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }

  void _showPayQrCode(BuildContext context, Map<String, dynamic> restaurant) {
    final qrData = 'ziggopay://pay?type=restaurant&id=${restaurant['id']}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              restaurant['name']?.toString() ?? 'Merchant',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              'Scan to Pay QR Code',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 200.0,
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              qrData,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
        ),
        actions: [
          Center(
            child: SizedBox(
              width: 120,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Delegate for Sticky Tabs
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyHeaderDelegate({required this.minHeight, required this.maxHeight, required this.child});
  final double minHeight;
  final double maxHeight;
  final Widget child;

  @override double get minExtent => minHeight;
  @override double get maxExtent => maxHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return maxHeight != oldDelegate.maxHeight || minHeight != oldDelegate.minHeight || child != oldDelegate.child;
  }
}
