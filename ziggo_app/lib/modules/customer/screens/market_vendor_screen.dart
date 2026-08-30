import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';
import '../market_provider.dart';
import 'market_checkout_screen.dart';

class MarketVendorScreen extends StatefulWidget {
  final Map<String, dynamic> vendor;
  const MarketVendorScreen({super.key, required this.vendor});

  @override
  State<MarketVendorScreen> createState() => _MarketVendorScreenState();
}

class _MarketVendorScreenState extends State<MarketVendorScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  final _searchCtrl = TextEditingController();
  String _search = '';
  String? _activeCategory;

  int get _vendorId => widget.vendor['id'] as int;
  String get _vendorName => widget.vendor['name']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    final mp = context.read<MarketProvider>();
    mp.setActiveVendor(widget.vendor);
    _future = mp.fetchProducts(_vendorId);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isOffer(Map<String, dynamic> p) {
    final orig = (p['original_price'] as num?)?.toDouble();
    final price = (p['price'] as num?)?.toDouble() ?? 0;
    return orig != null && orig > price;
  }

  List<String> _categories(List<Map<String, dynamic>> products) {
    final set = <String>{};
    var hasUncategorised = false;
    for (final p in products) {
      final c = p['category']?.toString().trim();
      if (c != null && c.isNotEmpty) {
        set.add(c);
      } else {
        hasUncategorised = true;
      }
    }
    final list = set.toList()..sort();
    if (hasUncategorised && list.isNotEmpty) list.add('Other');
    if (list.isNotEmpty) list.insert(0, 'All');
    return list;
  }

  List<Map<String, dynamic>> _inCategory(
      List<Map<String, dynamic>> products, String category) {
    if (category == 'All') {
      return products;
    }
    if (category == 'Other') {
      return products
          .where((p) => (p['category']?.toString().trim() ?? '').isEmpty)
          .toList();
    }
    return products
        .where((p) => (p['category']?.toString().trim() ?? '') == category)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final mp = context.watch<MarketProvider>();
    final showCart = mp.cart.isNotEmpty && mp.activeVendorId == _vendorId;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snap.data ?? [];
          final searching = _search.trim().isNotEmpty;
          final offers = products.where(_isOffer).toList();
          final populars =
              products.where((p) => p['is_popular'] == true).toList();
          final categories = _categories(products);
          final selected = _activeCategory != null &&
                  categories.contains(_activeCategory)
              ? _activeCategory!
              : (categories.isNotEmpty ? categories.first : '');

          final List<Map<String, dynamic>> listProducts;
          if (searching) {
            final q = _search.trim().toLowerCase();
            listProducts = products.where((p) {
              final n = (p['name']?.toString() ?? '').toLowerCase();
              final d = (p['description']?.toString() ?? '').toLowerCase();
              return n.contains(q) || d.contains(q);
            }).toList();
          } else if (selected.isNotEmpty) {
            listProducts = _inCategory(products, selected);
          } else {
            listProducts = products;
          }

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _infoSheet()),
              if (!searching && categories.length > 1)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsHeader(
                    categories: categories,
                    selected: selected,
                    onTap: (c) => setState(() => _activeCategory = c),
                  ),
                ),
              SliverToBoxAdapter(child: _searchField()),
              if (!searching && offers.isNotEmpty)
                SliverToBoxAdapter(child: _carousel('Offers', offers)),
              if (!searching && populars.isNotEmpty)
                SliverToBoxAdapter(
                    child: _carousel('Popular Picks', populars,
                        icon: Icons.star_rounded)),
              SliverToBoxAdapter(
                child: _listTitle(searching ? 'Results' : selected,
                    count: listProducts.length),
              ),
              if (listProducts.isEmpty)
                SliverToBoxAdapter(child: _emptyProducts(searching))
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, showCart ? 110 : 28),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) => _ProductRow(
                        product: listProducts[i],
                        vendorId: _vendorId,
                        isOffer: _isOffer(listProducts[i]),
                      ),
                      childCount: listProducts.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: showCart ? _cartBar(mp) : null,
    );
  }

  // -------------------------------------------------------------- header stack
  Widget _buildHeader() {
    final cover = _resolveImg(widget.vendor['image_url']?.toString());
    final logo = _resolveImg((widget.vendor['logo_url'] ?? widget.vendor['image_url'])?.toString());
    final isOpenNow = widget.vendor['is_open_now'] != false;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Cover Image
        Container(
          height: 200,
          width: double.infinity,
          color: AppColors.surfaceMuted,
          child: cover == null
              ? Container(
                  decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                  child: const Center(
                    child: Icon(Icons.storefront_rounded, color: Colors.white, size: 54),
                  ),
                )
              : Image.network(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                  ),
                ),
        ),
        // subtle scrim so the white circle buttons read on any image
        Container(
          height: 200,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.18),
                Colors.transparent,
              ],
            ),
          ),
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
                    context.watch<MarketProvider>().isFavourite(widget.vendor['id'] as int)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    _favourite,
                    iconColor: context.watch<MarketProvider>().isFavourite(widget.vendor['id'] as int)
                        ? AppColors.error
                        : AppColors.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  _circleBtn(Icons.qr_code_2_rounded,
                      () => _showPayQrCode(context, widget.vendor)),
                ],
              ),
            ],
          ),
        ),
        // Logo & Open Badge (Overlapping)
        Positioned(
          bottom: -45,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: AppStyles.shadowSm,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: logo != null
                      ? Image.network(
                          logo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.storefront_rounded,
                              color: AppColors.textTertiary,
                              size: 34),
                        )
                      : const Icon(Icons.storefront_rounded,
                          color: AppColors.textTertiary, size: 34),
                ),
              ),
              const SizedBox(height: 4),
              _openBadge(isOpenNow),
            ],
          ),
        ),
      ],
    );
  }

  Widget _openBadge(bool isOpenNow) {
    final color = isOpenNow ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(100),
        boxShadow: AppStyles.shadowSm,
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            isOpenNow ? 'Open' : 'Closed',
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {Color? iconColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.8),
          shape: BoxShape.circle,
          boxShadow: AppStyles.shadowSm,
        ),
        child: Icon(icon, color: iconColor ?? AppColors.textPrimary, size: 20),
      ),
    );
  }

  void _favourite() {
    context.read<MarketProvider>().toggleFavourite(widget.vendor['id'] as int);
  }

  // --------------------------------------------------------------- info
  Widget _infoSheet() {
    final area = widget.vendor['address']?.toString().trim() ?? '';
    final rating = (widget.vendor['rating'] as num?)?.toDouble() ?? 0;
    final eta = widget.vendor['eta_minutes'];
    final pickupFee = (widget.vendor['pickup_fee'] as num?)?.toDouble() ?? 70.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 52, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _vendorName,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24,
              letterSpacing: -0.5,
              height: 1.05,
            ),
          ),
          if (area.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    area,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.thumb_up_alt_rounded,
                  size: 15, color: AppColors.success),
              const SizedBox(width: 4),
              Text(
                rating > 0 ? '${(rating * 20).toStringAsFixed(0)}%' : '96%',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: AppColors.success,
                ),
              ),
              _dot(),
              const Icon(Icons.timer_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(
                'Est: ${eta ?? 27}mins',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              _dot(),
              const Icon(Icons.delivery_dining_rounded,
                  size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(
                'Fee: ${pickupFee.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _promoRow(),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _dot() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        width: 3,
        height: 3,
        decoration: const BoxDecoration(
          color: AppColors.textTertiary,
          shape: BoxShape.circle,
        ),
      );

  Widget _promoRow() {
    final code = context.watch<MarketProvider>().pendingPromoCode;
    final has = code != null;
    return GestureDetector(
      onTap: _promoDialog,
      child: CustomPaint(
        painter: has
            ? null
            : DashedRectPainter(
                color: AppColors.textTertiary.withOpacity(0.5),
                radius: 10,
                strokeWidth: 1.2,
                gap: 5,
              ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: has ? AppColors.primary.withOpacity(0.07) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: has
                ? Border.all(
                    color: AppColors.primary,
                    width: 1.2,
                  )
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.local_offer_outlined,
                  size: 18,
                  color: has ? AppColors.primary : AppColors.textTertiary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  has ? 'Promo "$code" applied' : 'Add promo code',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                    color: has ? AppColors.primary : AppColors.textSecondary,
                  ),
                ),
              ),
              Icon(
                has ? Icons.close_rounded : Icons.add_rounded,
                size: 18,
                color: has ? AppColors.primary : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promoDialog() async {
    final mp = context.read<MarketProvider>();
    if (mp.pendingPromoCode != null) {
      mp.setPromoCode(null);
      return;
    }
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Add promo code',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: 'e.g. ZIGGO50',
            filled: true,
            fillColor: AppColors.surfaceMuted,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (code != null && code.isNotEmpty) {
      mp.setPromoCode(code.toUpperCase());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Promo code applied at checkout'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1300),
        ),
      );
    }
  }

  // -------------------------------------------------------------- search
  Widget _searchField() {
    final addressStr = widget.vendor['address'] != null ? ' (${widget.vendor['address']})' : '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(Icons.search_rounded,
                color: AppColors.textTertiary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search in $_vendorName$addressStr',
                  hintStyle: const TextStyle(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            if (_search.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                  FocusScope.of(context).unfocus();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.close_rounded,
                      color: AppColors.textTertiary, size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- carousels
  Widget _carousel(String title, List<Map<String, dynamic>> items,
      {IconData icon = Icons.local_offer_rounded}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 15, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 252,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _ProductTile(
                product: items[i],
                vendorId: _vendorId,
                isOffer: _isOffer(items[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listTitle(String title, {required int count}) {
    if (title.isEmpty) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 16, 10),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 16,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _emptyProducts(bool searching) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Center(
        child: Column(
          children: [
            Icon(
              searching ? Icons.search_off_rounded : Icons.inventory_2_rounded,
              size: 44,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              searching ? 'No matching products' : 'No products here yet',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- cart
  Widget _cartBar(MarketProvider mp) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '${mp.cartCount}',
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
                  'Rs.${mp.cartTotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _resolveImg(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${ApiConfig.baseHost}$path';
  }

  void _showPayQrCode(BuildContext context, Map<String, dynamic> vendor) {
    final qrData = 'ziggopay://pay?type=market&id=${vendor['id']}';
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Text(
                vendor['name']?.toString() ?? 'Merchant',
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
              const SizedBox(height: 20),
              SizedBox(
                width: 130,
                height: 46,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ====================================================================
//  Pinned category tabs
// ====================================================================
class _TabsHeader extends SliverPersistentHeaderDelegate {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onTap;
  _TabsHeader({
    required this.categories,
    required this.selected,
    required this.onTap,
  });

  @override
  double get minExtent => 56;
  @override
  double get maxExtent => 56;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = categories[i];
          final active = c == selected;
          return GestureDetector(
            onTap: () => onTap(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.textPrimary : AppColors.surface,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: active ? AppColors.textPrimary : AppColors.cardBorder,
                ),
              ),
              child: Text(
                c.toUpperCase(),
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _TabsHeader old) =>
      old.selected != selected || old.categories != categories;
}

// ====================================================================
//  Shared add-to-cart control (+ / quantity stepper)
// ====================================================================
class _AddControl extends StatelessWidget {
  final Map<String, dynamic> product;
  final int vendorId;
  final bool disabled;
  const _AddControl({
    required this.product,
    required this.vendorId,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final mp = context.watch<MarketProvider>();
    final qty = (mp.cart[product['id'] as int]?['quantity'] as int?) ?? 0;

    if (disabled) {
      return Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(Icons.block_rounded,
            color: AppColors.textTertiary, size: 16),
      );
    }

    if (qty == 0) {
      return GestureDetector(
        onTap: () => mp.addToCart(vendorId, product),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: AppColors.primary.withOpacity(0.5)),
            boxShadow: AppStyles.shadowSm,
          ),
          child: const Icon(Icons.add_rounded,
              color: AppColors.primary, size: 20),
        ),
      );
    }

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepBtn(Icons.remove_rounded,
              () => mp.changeQty(product['id'] as int, -1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              '$qty',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          _stepBtn(Icons.add_rounded,
              () => mp.changeQty(product['id'] as int, 1)),
        ],
      ),
    );
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 26,
        height: 30,
        child: Icon(icon, color: Colors.white, size: 16),
      ),
    );
  }
}

// ====================================================================
//  Price + discount badge helpers
// ====================================================================
String _money(num v) => 'LKR ${v.toStringAsFixed(2)}';

int _discountPct(Map<String, dynamic> p) {
  final orig = (p['original_price'] as num?)?.toDouble() ?? 0;
  final price = (p['price'] as num?)?.toDouble() ?? 0;
  if (orig <= 0 || price >= orig) return 0;
  return (((orig - price) / orig) * 100).round();
}

Widget _discountBadge(Map<String, dynamic> p) {
  final pct = _discountPct(p);
  if (pct <= 0) return const SizedBox.shrink();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.blue.shade600,
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      '$pct% OFF',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9.5,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.2,
      ),
    ),
  );
}

Widget _priceRow(Map<String, dynamic> p, bool isOffer) {
  final price = (p['price'] as num?)?.toDouble() ?? 0;
  final orig = (p['original_price'] as num?)?.toDouble() ?? 0;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        _money(price),
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 13.5,
          color: AppColors.textPrimary,
        ),
      ),
      if (isOffer) ...[
        const SizedBox(height: 1),
        Text(
          _money(orig),
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    ],
  );
}

String? _imgUrl(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '${ApiConfig.baseHost}$path';
}

bool _isOutOfStock(Map<String, dynamic> p) {
  final available = p['is_available'] != false;
  final stock = (p['stock_quantity'] as num?)?.toInt();
  return !available || (stock != null && stock <= 0);
}

Widget _productPlaceholder(double size) {
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          AppColors.primary.withOpacity(0.10),
          AppColors.primary.withOpacity(0.04),
        ],
      ),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(Icons.shopping_basket_rounded,
        color: AppColors.primary.withOpacity(0.45), size: size * 0.34),
  );
}

Widget _productImage(Map<String, dynamic> p, double size) {
  final url = _imgUrl(p['image_url']?.toString());
  if (url == null) return _productPlaceholder(size);
  return ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : _productPlaceholder(size),
      errorBuilder: (_, __, ___) => _productPlaceholder(size),
    ),
  );
}

// ====================================================================
//  Carousel card (Offers / Popular Picks)
// ====================================================================
class _ProductTile extends StatelessWidget {
  final Map<String, dynamic> product;
  final int vendorId;
  final bool isOffer;
  const _ProductTile({
    required this.product,
    required this.vendorId,
    required this.isOffer,
  });

  @override
  Widget build(BuildContext context) {
    final out = _isOutOfStock(product);
    return Opacity(
      opacity: out ? 0.55 : 1,
      child: SizedBox(
        width: 156,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 144,
                  height: 144,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: _productImage(product, 128),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: _AddControl(
                    product: product,
                    vendorId: vendorId,
                    disabled: out,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              product['name']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 4),
            if (isOffer) ...[
              _discountBadge(product),
              const SizedBox(height: 4),
            ],
            _priceRow(product, isOffer),
          ],
        ),
      ),
    );
  }
}

// ====================================================================
//  Vertical product row (category list)
// ====================================================================
class _ProductRow extends StatelessWidget {
  final Map<String, dynamic> product;
  final int vendorId;
  final bool isOffer;
  const _ProductRow({
    required this.product,
    required this.vendorId,
    required this.isOffer,
  });

  @override
  Widget build(BuildContext context) {
    final out = _isOutOfStock(product);
    final unit = product['unit']?.toString() ?? '';
    return Opacity(
      opacity: out ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product['name']?.toString() ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                      height: 1.2,
                    ),
                  ),
                  if (unit.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Per $unit',
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (isOffer) ...[
                    _discountBadge(product),
                    const SizedBox(height: 6),
                  ],
                  _priceRow(product, isOffer),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.thumb_up_alt_rounded,
                          size: 13, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(
                        '96% (25+)',
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Stack(
              clipBehavior: Clip.none,
              children: [
                _productImage(product, 84),
                Positioned(
                  right: -6,
                  bottom: -6,
                  child: _AddControl(
                    product: product,
                    vendorId: vendorId,
                    disabled: out,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DashedRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;
  final double radius;

  DashedRectPainter({
    this.color = Colors.grey,
    this.strokeWidth = 1.0,
    this.gap = 5.0,
    this.radius = 12.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Radius.circular(radius),
      ));

    final dashedPath = Path();
    double distance = 0.0;
    for (final metric in path.computeMetrics()) {
      while (distance < metric.length) {
        dashedPath.addPath(
          metric.extractPath(distance, distance + gap),
          Offset.zero,
        );
        distance += gap * 2;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
