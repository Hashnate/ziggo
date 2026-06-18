import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/places.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import '../addresses_provider.dart';
import '../market_provider.dart';
import 'choose_location_screen.dart';
import 'customer_shell.dart';
import 'market_checkout_screen.dart';
import 'market_favourites_screen.dart';
import 'market_orders_screen.dart';
import 'market_group_screen.dart';
import 'market_vendor_screen.dart';

class MarketHomeScreen extends StatefulWidget {
  const MarketHomeScreen({super.key});

  @override
  State<MarketHomeScreen> createState() => _MarketHomeScreenState();
}

class _MarketHomeScreenState extends State<MarketHomeScreen> {
  String _query = '';
  final _searchCtrl = TextEditingController();

  /// Delivery location chosen via the Choose-Location screen. When null the
  /// location bar falls back to the customer's default saved address.
  Place? _selectedPlace;

  final _bannerCtrl = PageController();
  int _bannerPage = 0;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MarketProvider>().refreshVendors();
      context.read<MarketProvider>().fetchAds();
      context.read<AddressesProvider>().refresh();
    });
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_bannerCtrl.hasClients || _kBanners.isEmpty) return;
      final next = (_bannerPage + 1) % _kBanners.length;
      _bannerCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _bannerCtrl.dispose();
    _bannerTimer?.cancel();
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

  void _soon(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label coming soon'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  void _selectCategory(String label) {
    _searchCtrl.text = label;
    setState(() => _query = label);
  }

  Future<void> _openChooseLocation() async {
    final picked = await Navigator.push<Place>(
      context,
      MaterialPageRoute(builder: (_) => const ChooseLocationScreen()),
    );
    if (picked != null && mounted) {
      setState(() => _selectedPlace = picked);
      context.read<MarketProvider>().refreshVendors(
            lat: picked.location.latitude,
            lng: picked.location.longitude,
          );
      context.read<MarketProvider>().fetchAds(
            lat: picked.location.latitude,
            lng: picked.location.longitude,
          );
    }
  }

  String? _resolveImg(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${ApiConfig.baseHost}$path';
  }

  Future<void> _handleAdTap(Map<String, dynamic> ad) async {
    final provider = context.read<MarketProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final vendor = await provider.fetchVendorById(ad['vendor_id'] as int);
    if (mounted) Navigator.pop(context);
    if (vendor != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MarketVendorScreen(vendor: vendor)),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open vendor shop'), backgroundColor: AppColors.warning),
      );
    }
  }

  void _openFavourites() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MarketFavouritesScreen()),
      );

  void _openOrders() => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MarketOrdersScreen()),
      );

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((v) {
      final name = (v['name']?.toString() ?? '').toLowerCase();
      final cat = (v['category']?.toString() ?? '').toLowerCase();
      return name.contains(q) || cat.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<MarketProvider>();
    final searching = _query.trim().isNotEmpty;
    final outlets = _filtered(p.vendors);
    final hasCart = p.cart.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            final lat = _selectedPlace?.location.latitude;
            final lng = _selectedPlace?.location.longitude;
            await p.refreshVendors(lat: lat, lng: lng);
            await p.fetchAds(lat: lat, lng: lng);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _header()),
              SliverToBoxAdapter(child: _locationBar()),
              SliverToBoxAdapter(child: _search()),
              if (!searching) ...[
                SliverToBoxAdapter(child: _bannerCarousel()),
                SliverToBoxAdapter(child: _categories()),
                SliverToBoxAdapter(child: _pickedForYou()),
                SliverToBoxAdapter(child: _deals()),
              ],
              SliverToBoxAdapter(
                child: _sectionHeader(
                  searching ? 'Results' : 'Outlets near you',
                  trailing: searching ? '${outlets.length} found' : null,
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, hasCart ? 120 : 28),
                sliver: p.loading && p.vendors.isEmpty
                    ? _skeletonList()
                    : outlets.isEmpty
                        ? SliverToBoxAdapter(child: _empty(searching))
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => EntranceSlide(
                                delay: Duration(milliseconds: 45 * i),
                                child: MarketOutletCard(vendor: outlets[i]),
                              ),
                              childCount: outlets.length,
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      bottomSheet: hasCart ? _cartBar(p) : null,
    );
  }

  // ---------------------------------------------------------------- header
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _headerIcon(Icons.arrow_back_rounded, _handleBack),
          const SizedBox(width: 12),
          const Text(
            'Market',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.4,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          _headerIcon(Icons.favorite_border_rounded, _openFavourites),
          const SizedBox(width: 18),
          _headerIcon(Icons.receipt_long_rounded, _openOrders),
        ],
      ),
    );
  }

  Widget _headerIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Icon(icon, size: 26, color: AppColors.textPrimary),
    );
  }

  // -------------------------------------------------------------- location
  Widget _locationBar() {
    final addresses = context.watch<AddressesProvider>().items;
    String? title;
    String? subtitle;

    if (_selectedPlace != null) {
      title = _selectedPlace!.name;
      subtitle = _selectedPlace!.area;
    } else {
      Map<String, dynamic>? def;
      for (final a in addresses) {
        if (a['is_default'] == true) {
          def = a;
          break;
        }
      }
      def ??= addresses.isNotEmpty ? addresses.first : null;
      title = def?['label']?.toString().trim();
      subtitle = def?['address']?.toString().trim();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: InkWell(
        onTap: _openChooseLocation,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.location_on_rounded,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title?.isNotEmpty == true ? title! : 'Set delivery location',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle?.isNotEmpty == true
                        ? subtitle!
                        : 'Tap to choose where to deliver',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_right_rounded,
                color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- search
  Widget _search() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppStyles.shadowSm,
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search_rounded,
                color: AppColors.textTertiary, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Looking for something?',
                  hintStyle: TextStyle(
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
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

  int get _clampedBannerPage {
    final p = context.read<MarketProvider>();
    final itemsCount = p.ads.isNotEmpty ? p.ads.length : _kBanners.length;
    if (_bannerPage >= itemsCount) {
      return 0;
    }
    return _bannerPage;
  }

  Widget _bannerCarousel() {
    final p = context.watch<MarketProvider>();
    final ads = p.ads;
    final itemsCount = ads.isNotEmpty ? ads.length : _kBanners.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 4),
      child: Column(
        children: [
          SizedBox(
            height: 188,
            child: PageView.builder(
              controller: _bannerCtrl,
              onPageChanged: (i) => setState(() => _bannerPage = i),
              itemCount: itemsCount,
              itemBuilder: (_, i) {
                if (ads.isNotEmpty) {
                  final ad = ads[i];
                  final imageUrl = _resolveImg(ad['image_url']?.toString());
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GestureDetector(
                      onTap: () => _handleAdTap(ad),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
                        child: imageUrl != null
                            ? Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppColors.surfaceMuted,
                                  child: const Center(
                                    child: Icon(Icons.broken_image_rounded, color: AppColors.textTertiary, size: 44),
                                  ),
                                ),
                              )
                            : Container(color: AppColors.surfaceMuted),
                      ),
                    ),
                  );
                } else {
                  return _bannerCard(_kBanners[i]);
                }
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(itemsCount, (i) {
              final active = i == _clampedBannerPage;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(100),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _bannerCard(_Banner b) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        child: b.image != null
            ? Image.asset(
                b.image!,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => _bannerGradient(b),
              )
            : _bannerGradient(b),
      ),
    );
  }

  Widget _bannerGradient(_Banner b) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: b.gradient,
        ),
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        boxShadow: AppStyles.shadowMd,
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -24,
            child: Icon(b.icon,
                size: 168, color: Colors.white.withOpacity(0.14)),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    b.tag,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  b.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                    height: 1.05,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  b.subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------- categories
  Widget _categories() {
    // Column-major fill: each on-screen column stacks two categories
    // (item i on top, item i+1 below), scrolling horizontally for the rest.
    final columns = <Widget>[];
    for (var i = 0; i < _kCategories.length; i += 2) {
      columns.add(Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            _categoryTile(_kCategories[i]),
            const SizedBox(height: 10),
            if (i + 1 < _kCategories.length)
              _categoryTile(_kCategories[i + 1])
            else
              const SizedBox(width: 66, height: 86),
          ],
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          _sectionHeader('Popular Categories'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: columns,
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryTile(_MarketCategory c) {
    return GestureDetector(
      onTap: () => _selectCategory(c.label),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 66,
        child: Column(
          children: [
            SizedBox(
              width: 62,
              height: 62,
              child: c.image != null
                  ? Image.asset(
                      c.image!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          Icon(c.icon, color: c.color, size: 28),
                    )
                  : Icon(c.icon, color: c.color, size: 28),
            ),
            const SizedBox(height: 6),
            Text(
              c.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------- picked for you
  Widget _pickedForYou() {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        children: [
          _sectionHeader('Picked Up For You'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: [
                for (var i = 0; i < _kPicks.length; i++) ...[
                  Expanded(child: _pickCard(_kPicks[i])),
                  if (i != _kPicks.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickCard(_PickItem p) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MarketGroupScreen(groupName: p.label),
        ),
      ),
      child: Container(
        height: 122,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          boxShadow: AppStyles.shadowSm,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p.image != null ? null : p.color.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: p.image != null
                      ? Image.asset(
                          p.image!,
                          fit: BoxFit.contain,
                          width: 48,
                          height: 48,
                          errorBuilder: (_, __, ___) => Icon(p.icon, color: p.color, size: 26),
                        )
                      : Icon(p.icon, color: p.color, size: 26),
                ),
                if (p.isNew)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              p.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                height: 1.1,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- deals
  Widget _deals() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [
          _sectionHeader('Deals and Offers'),
          SizedBox(
            height: 206,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              itemCount: _kDeals.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _dealCard(_kDeals[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dealCard(_Deal d) {
    return GestureDetector(
      onTap: () => _soon(d.title.replaceAll('\n', ' ')),
      child: Container(
        width: 166,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: d.gradient,
          ),
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
          boxShadow: AppStyles.shadowSm,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -10,
              bottom: -10,
              child: d.image != null
                  ? Image.asset(
                      d.image!,
                      width: 106,
                      height: 106,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(d.icon,
                          size: 82, color: Colors.white.withOpacity(0.22)),
                    )
                  : Icon(d.icon, size: 82, color: Colors.white.withOpacity(0.22)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Flexible(
                    child: Text(
                      d.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '*T&C Apply',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chevron_right_rounded,
                        color: d.gradient.last, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- section head
  Widget _sectionHeader(String title, {String? trailing, VoidCallback? onTrailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            GestureDetector(
              onTap: onTrailing,
              child: Text(
                trailing,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- cart
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------- skeleton / empty
  Widget _skeletonList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, __) => Container(
          margin: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppStyles.shadowSm,
          ),
          child: Shimmer.fromColors(
            baseColor: AppColors.surfaceMuted,
            highlightColor: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 140,
                  decoration: const BoxDecoration(
                    color: Colors.black12,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(22)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 14, width: 180, color: Colors.black12),
                      const SizedBox(height: 8),
                      Container(height: 10, width: 120, color: Colors.black12),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        childCount: 3,
      ),
    );
  }

  Widget _empty(bool searching) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
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
                searching ? Icons.search_off_rounded : Icons.storefront_rounded,
                size: 44,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              searching ? 'No outlets found' : 'No outlets available',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              searching ? 'Try a different search' : 'Pull to refresh',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (searching) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Clear search'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ====================================================================
//  Outlet card — "Outlets near you"
// ====================================================================
class MarketOutletCard extends StatelessWidget {
  final Map<String, dynamic> vendor;
  const MarketOutletCard({required this.vendor});

  String? _resolveCover(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${ApiConfig.baseHost}$path';
  }

  Widget _coverPlaceholder() {
    return Container(
      height: 144,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 46),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOpenNow = vendor['is_open_now'] != false;
    final coverUrl = _resolveCover(vendor['image_url']?.toString());
    final rating = (vendor['rating'] as num?)?.toDouble() ?? 0;
    final eta = vendor['eta_minutes'];
    final fee = (vendor['delivery_fee'] as num?)?.toDouble() ?? 0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MarketVendorScreen(vendor: vendor)),
      ),
      child: Opacity(
        opacity: isOpenNow ? 1 : 0.7,
        child: Container(
          margin: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppStyles.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(22)),
                    child: coverUrl == null
                        ? _coverPlaceholder()
                        : Image.network(
                            coverUrl,
                            height: 144,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (_, child, progress) =>
                                progress == null ? child : _coverPlaceholder(),
                            errorBuilder: (_, __, ___) => _coverPlaceholder(),
                          ),
                  ),
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(100),
                        boxShadow: AppStyles.shadowSm,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_offer_rounded,
                              color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'Discount Offer',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 12,
                    child: GestureDetector(
                      onTap: () {
                        context.read<MarketProvider>().toggleFavourite(vendor['id'] as int);
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: AppStyles.shadowSm,
                        ),
                        child: Icon(
                          context.watch<MarketProvider>().isFavourite(vendor['id'] as int)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 18, 
                          color: context.watch<MarketProvider>().isFavourite(vendor['id'] as int)
                              ? AppColors.error
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (!isOpenNow)
                    Positioned(
                      left: 12,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'CLOSED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor['name']?.toString() ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.thumb_up_rounded,
                            color: AppColors.success, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          rating > 0 ? rating.toStringAsFixed(1) : 'New',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.success,
                          ),
                        ),
                        _dot(),
                        const Icon(Icons.timer_rounded,
                            size: 13, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Text(
                          'Est ${eta ?? 40}mins',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        _dot(),
                        const Icon(Icons.delivery_dining_rounded,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            'Rs.${fee.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
}

// ====================================================================
//  Static data — extend / swap images in the next phase
// ====================================================================
class _MarketCategory {
  final String label;
  final IconData icon;
  final Color color;

  /// Optional asset path (e.g. 'assets/images/market/seafood.png').
  /// When set it replaces the icon. Add images here in the next phase.
  final String? image;
  const _MarketCategory(this.label, this.icon, this.color, {this.image});
}

// Order is column-major (PickMe-style): item 1 sits top-left, item 2 below it,
// item 3 top of the next column, and so on. Add more here in future phases.
const _kCategories = <_MarketCategory>[
  _MarketCategory('Groceries', Icons.shopping_basket_rounded, Color(0xFF16A34A),
      image: 'assets/images/marketplace/groceries.png'),
  _MarketCategory('Pharmaceutical', Icons.medical_services_rounded, Color(0xFFEF4444),
      image: 'assets/images/marketplace/pharmaceutical.png'),
  _MarketCategory('Fresh Produce', Icons.eco_rounded, Color(0xFF22C55E),
      image: 'assets/images/marketplace/freshproduce.png'),
  _MarketCategory('Household', Icons.cleaning_services_rounded, Color(0xFF3B82F6),
      image: 'assets/images/marketplace/household.png'),
  _MarketCategory('Dairy', Icons.egg_alt_rounded, Color(0xFFF59E0B),
      image: 'assets/images/marketplace/dairy.png'),
  _MarketCategory('Baby Care', Icons.child_friendly_rounded, Color(0xFFEC4899),
      image: 'assets/images/marketplace/babycare.png'),
  _MarketCategory('Poultry and Meat', Icons.set_meal_rounded, Color(0xFFE11D48),
      image: 'assets/images/marketplace/poultryandmeat.png'),
  _MarketCategory('Personal Care', Icons.spa_rounded, Color(0xFF8B5CF6),
      image: 'assets/images/marketplace/personalcare.png'),
  _MarketCategory('Seafood', Icons.phishing_rounded, Color(0xFF0EA5E9),
      image: 'assets/images/marketplace/seafood.png'),
  _MarketCategory('Pet Care', Icons.pets_rounded, Color(0xFFF59E0B),
      image: 'assets/images/marketplace/petcare.png'),
  _MarketCategory('Frozen Foods', Icons.ac_unit_rounded, Color(0xFF3B82F6),
      image: 'assets/images/marketplace/frozenfoods.png'),
  _MarketCategory('Cosmetics', Icons.face_retouching_natural_rounded, Color(0xFFE11D48),
      image: 'assets/images/marketplace/cosmetics.png'),
  _MarketCategory('Fresh Flowers', Icons.local_florist_rounded, Color(0xFFEC4899),
      image: 'assets/images/marketplace/freshflower.png'),
  _MarketCategory('Bakery', Icons.bakery_dining_rounded, Color(0xFFD97706),
      image: 'assets/images/marketplace/bakery-Photoroom.png'),
  _MarketCategory('Stationery', Icons.edit_note_rounded, Color(0xFF6366F1),
      image: 'assets/images/marketplace/stationery.png'),
  _MarketCategory('Electronics', Icons.devices_rounded, Color(0xFF6366F1),
      image: 'assets/images/marketplace/electronics.png'),
  _MarketCategory('Ayurvedic', Icons.local_pharmacy_rounded, Color(0xFF16A34A),
      image: 'assets/images/marketplace/ayurvedic.png'),
  _MarketCategory('21+', Icons.no_drinks_rounded, Color(0xFF64748B),
      image: 'assets/images/marketplace/21+.png'),
  _MarketCategory('Intimacy', Icons.favorite_rounded, Color(0xFFDB2777),
      image: 'assets/images/marketplace/intimacy.png'),
];

class _PickItem {
  final String label;
  final IconData icon;
  final Color color;
  final bool isNew;
  final String? image;
  const _PickItem(this.label, this.icon, this.color, {this.isNew = false, this.image});
}

const _kPicks = <_PickItem>[
  _PickItem('Popular', Icons.shield_rounded, AppColors.primary,
      image: 'assets/images/marketplace/popular.png'),
  _PickItem('Newly Joined', Icons.local_offer_rounded, AppColors.info,
      isNew: true, image: 'assets/images/marketplace/new_joined.png'),
  _PickItem('Featured Outlets', Icons.workspace_premium_rounded, AppColors.error,
      image: 'assets/images/marketplace/featured.png'),
  _PickItem('Trending', Icons.trending_up_rounded, AppColors.success,
      image: 'assets/images/marketplace/trending.png'),
];

class _Deal {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;

  /// Optional asset (e.g. 'assets/images/marketplace/deal_bag.png').
  /// When set it replaces the icon illustration. Add images here next phase.
  final String? image;
  const _Deal(this.title, this.subtitle, this.icon, this.gradient, {this.image});
}

const _kDeals = <_Deal>[
  _Deal(
    'Spend more\nSave more',
    'Deals from your favourite outlets!',
    Icons.storefront_rounded,
    [Color(0xFF16A34A), Color(0xFF84CC16)],
    image: 'assets/images/marketplace/deal_spend_save.png',
  ),
  _Deal(
    'Buy 1\nGet 1 Free!',
    'Double your delight!',
    Icons.shopping_bag_rounded,
    [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    image: 'assets/images/marketplace/deal_bag.png',
  ),
  _Deal(
    'Combo Deals!',
    'Best compliments for the day',
    Icons.fastfood_rounded,
    [Color(0xFF0D9488), Color(0xFF2DD4BF)],
    image: 'assets/images/marketplace/deal_combo.png',
  ),
  _Deal(
    'Discount Offers!',
    'Lowest price deals',
    Icons.percent_rounded,
    [Color(0xFF8B5CF6), Color(0xFF6366F1)],
    image: 'assets/images/marketplace/deal_discount.png',
  ),
  _Deal(
    'Bundle Offers!',
    'Get more Pay less',
    Icons.shopping_cart_rounded,
    [Color(0xFFF97316), Color(0xFFFBBF24)],
    image: 'assets/images/marketplace/deal_bundle.png',
  ),
];

class _Banner {
  final String tag;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;

  /// Optional full-bleed ad image (e.g. 'assets/images/marketplace/banner_jkoa.png').
  /// When set the whole banner shows the image instead of the gradient.
  /// Drop your ad banners in here next phase.
  final String? image;
  const _Banner(this.tag, this.title, this.subtitle, this.icon, this.gradient,
      {this.image});
}

const _kBanners = <_Banner>[
  _Banner('REGISTERED DEVICES', 'Now Available', 'Mobiles & accessories',
      Icons.phone_iphone_rounded, [Color(0xFF172554), Color(0xFF1E40AF)]),
  _Banner('FRESH DAILY', 'Groceries to your door', 'Delivered in minutes',
      Icons.shopping_basket_rounded, [Color(0xFF0E7A52), Color(0xFF16A34A)]),
  _Banner('SAVE BIG', 'Up to 50% off', 'On selected outlets today',
      Icons.percent_rounded, [Color(0xFF7C3AED), Color(0xFF5B21B6)]),
];
