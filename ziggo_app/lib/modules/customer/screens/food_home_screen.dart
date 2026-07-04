import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import '../addresses_provider.dart';
import '../food_provider.dart';
import '../food_ui.dart';
import 'category_restaurants_screen.dart';
import 'food_favourites_screen.dart';
import 'food_orders_screen.dart';
import 'restaurant_detail_screen.dart';

/// Resolve an image path that may be remote (http) or a backend-relative
/// /static path into a fully-qualified URL.
String? _resolveAsset(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  return '${ApiConfig.baseHost}$path';
}

Color _colorFromToken(String? token) {
  switch (token) {
    case 'orange':
      return const Color(0xFFFF7849);
    case 'purple':
      return Colors.purple;
    case 'green':
      return Colors.green;
    case 'red':
      return Colors.red;
    case 'indigo':
      return Colors.indigo;
    case 'cyan':
      return Colors.cyan;
    case 'blue':
      return AppColors.primaryLight;
    case 'primary':
    default:
      return AppColors.primary;
  }
}

class FoodHomeScreen extends StatefulWidget {
  const FoodHomeScreen({super.key});

  @override
  State<FoodHomeScreen> createState() => _FoodHomeScreenState();
}

class _FoodHomeScreenState extends State<FoodHomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final PageController _bannerController = PageController(viewportFraction: 0.93);
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final food = context.read<FoodProvider>();
    final addresses = context.read<AddressesProvider>();
    food.fetchHome();
    food.fetchFavorites();
    await addresses.refresh();
    if (!mounted) return;
    if (food.deliveryLat == null && addresses.items.isNotEmpty) {
      final def = addresses.items.firstWhere(
        (a) => a['is_default'] == true,
        orElse: () => addresses.items.first,
      );
      // setDeliveryLocation triggers the restaurant refetch (nearest-first).
      food.setDeliveryLocation(
        label: def['label']?.toString() ?? 'Delivery',
        subtitle: def['address']?.toString(),
        lat: (def['lat'] as num).toDouble(),
        lng: (def['lng'] as num).toDouble(),
      );
    } else {
      food.fetchRestaurants();
    }

    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_bannerController.hasClients) {
        final p = context.read<FoodProvider>();
        if (p.banners.isEmpty) return;
        
        int nextPage = _bannerController.page!.round() + 1;
        if (nextPage >= p.banners.length) {
          nextPage = 0;
        }
        _bannerController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<FoodProvider>();
    final filtered = p.restaurants;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            p.fetchHome(),
            p.fetchRestaurants(),
            p.fetchFavorites(),
          ]);
        },
        child: CustomScrollView(
          slivers: [
            _buildAppBar(p),
            _buildSearchBar(),
            if (p.banners.isNotEmpty) _buildBanners(p.banners),
            if (p.categories.isNotEmpty) _buildCategories(p.categories, p.selectedCategoryId),
            if (p.deals.isNotEmpty) _buildDeals(p.deals),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                child: Text(
                  'Outlets near you',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: p.loading && filtered.isEmpty
                  ? SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, __) => const RestaurantCardSkeleton(),
                        childCount: 3,
                      ),
                    )
                  : filtered.isEmpty
                      ? SliverToBoxAdapter(child: _empty())
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => EntranceSlide(
                              delay: Duration(milliseconds: 55 * i),
                              child: RestaurantCard(restaurant: filtered[i]),
                            ),
                            childCount: filtered.length,
                          ),
                        ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(FoodProvider p) {
    return SliverAppBar(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'Food',
        style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
      ),
      centerTitle: false,
      actions: [
        IconButton(
          icon: const Icon(Icons.favorite_border_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FoodFavouritesScreen()),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.receipt_long_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FoodOrdersScreen()),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: InkWell(
            onTap: _pickDeliveryLocation,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.food.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.location_on_rounded, color: AppColors.food, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.deliveryLabel ?? 'Set delivery location',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        p.deliverySubtitle ?? 'Tap to choose where to deliver',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.expand_more_rounded, color: AppColors.textPrimary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDeliveryLocation() async {
    final addresses = context.read<AddressesProvider>().items;
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Deliver to', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              ),
            ),
            ...addresses.map(
              (a) => ListTile(
                leading: const Icon(Icons.location_on_rounded, color: AppColors.food),
                title: Text(a['label']?.toString() ?? 'Address',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(a['address']?.toString() ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(context, a),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.my_location_rounded, color: AppColors.primary),
              title: const Text('Use current location',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(context, {'__current__': true}),
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded, color: AppColors.primary),
              title: const Text('Search a new address',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(context, {'__search__': true}),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final food = context.read<FoodProvider>();
    if (selected['__search__'] == true) {
      final place = await showPlaceSearch(context, title: 'Delivery location', allowCurrentLocation: true);
      if (place != null && mounted) {
        food.setDeliveryLocation(
          label: place.name,
          subtitle: place.fullAddress,
          lat: place.location.latitude,
          lng: place.location.longitude,
        );
      }
    } else if (selected['__current__'] == true) {
      final place = await MapsService.instance.currentLocationAsPlace();
      if (place != null && mounted) {
        food.setDeliveryLocation(
          label: place.name,
          subtitle: place.fullAddress,
          lat: place.location.latitude,
          lng: place.location.longitude,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location — check GPS / permission')),
        );
      }
    } else {
      food.setDeliveryLocation(
        label: selected['label']?.toString() ?? 'Delivery',
        subtitle: selected['address']?.toString(),
        lat: (selected['lat'] as num).toDouble(),
        lng: (selected['lng'] as num).toDouble(),
      );
    }
  }

  Widget _buildSearchBar() {
    final food = context.read<FoodProvider>();
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppStyles.radiusSm),
            boxShadow: AppStyles.shadowSm,
          ),
          child: Row(
            children: [
              const Icon(Icons.search_rounded, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => food.setSearchQuery(v),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'Search Pizza 🍕, Rice & Curry 🍛, Doughnut 🍩',
                    hintStyle: TextStyle(fontWeight: FontWeight.w500, color: AppColors.textTertiary, fontSize: 13),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
              if (_searchCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    food.setSearchQuery('');
                    FocusScope.of(context).unfocus();
                  },
                  child: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanners(List<Map<String, dynamic>> banners) {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          SizedBox(
            height: 160,
            child: PageView.builder(
              controller: _bannerController,
              padEnds: true,
              itemCount: banners.length,
              itemBuilder: (context, index) {
                final banner = banners[index];
                final img = _resolveAsset(banner['image_url']?.toString());
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () => _onBannerTap(banner),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: img == null
                          ? Container(color: AppColors.surfaceMuted)
                          : Image.network(
                              img,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              errorBuilder: (_, __, ___) => Container(color: AppColors.surfaceMuted),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(banners.length, (index) {
              return AnimatedBuilder(
                animation: _bannerController,
                builder: (context, child) {
                  double page = 0.0;
                  if (_bannerController.hasClients && _bannerController.position.haveDimensions) {
                    page = _bannerController.page ?? 0.0;
                  }
                  final isSelected = (page.round() == index);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 6,
                    width: isSelected ? 20 : 6,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.food : AppColors.divider,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                },
              );
            }),
          ),
        ],
      ),
    );
  }

  void _onBannerTap(Map<String, dynamic> banner) {
    final type = banner['link_type']?.toString() ?? 'none';
    final value = banner['link_value']?.toString() ?? '';
    final food = context.read<FoodProvider>();
    switch (type) {
      case 'restaurant':
        final id = int.tryParse(value);
        if (id != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: id)),
          );
        }
        break;
      case 'category':
        final id = int.tryParse(value);
        if (id != null) food.setCategoryFilter(id);
        break;
      case 'collection':
        final id = int.tryParse(value);
        if (id != null) food.setCollectionFilter(id);
        break;
      case 'promo':
        if (value.isNotEmpty) _showPromoSheet(value);
        break;
      case 'url':
        if (value.isNotEmpty) {
          final uri = Uri.tryParse(value);
          if (uri != null) {
            canLaunchUrl(uri).then((can) {
              if (can) launchUrl(uri, mode: LaunchMode.externalApplication);
            });
          }
        }
        break;
      default:
        break;
    }
  }

  void _onDealTap(Map<String, dynamic> deal) {
    final type = deal['link_type']?.toString() ?? 'none';
    final value = deal['link_value']?.toString() ?? '';
    final code = deal['promo_code']?.toString() ?? '';

    if (type == 'none' || type.isEmpty) {
      if (code.isNotEmpty) {
        _showPromoSheet(code);
      }
      return;
    }

    final food = context.read<FoodProvider>();
    switch (type) {
      case 'restaurant':
        final id = int.tryParse(value);
        if (id != null) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: id)),
          );
        }
        break;
      case 'category':
        final id = int.tryParse(value);
        if (id != null) food.setCategoryFilter(id);
        break;
      case 'collection':
        final id = int.tryParse(value);
        if (id != null) food.setCollectionFilter(id);
        break;
      case 'promo':
        if (value.isNotEmpty) _showPromoSheet(value);
        break;
      case 'url':
        if (value.isNotEmpty) {
          final uri = Uri.tryParse(value);
          if (uri != null) {
            canLaunchUrl(uri).then((can) {
              if (can) launchUrl(uri, mode: LaunchMode.externalApplication);
            });
          }
        }
        break;
      default:
        break;
    }
  }

  Widget _buildCategories(List<Map<String, dynamic>> categories, int? selectedId) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Popular Categories',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 110,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final cat = categories[index];
                  final id = cat['id'] as int?;
                  final isSel = id != null && id == selectedId;
                  final img = _resolveAsset(cat['icon_url']?.toString());
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CategoryRestaurantsScreen(category: cat),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.surfaceMuted,
                              border: isSel ? Border.all(color: AppColors.food, width: 3) : null,
                              image: img != null
                                  ? DecorationImage(image: NetworkImage(img), fit: BoxFit.cover)
                                  : null,
                            ),
                            child: img == null
                                ? const Icon(Icons.restaurant_rounded, color: AppColors.textTertiary)
                                : null,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            cat['name']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSel ? AppColors.food : AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeals(List<Map<String, dynamic>> deals) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Deals and Offers',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 140,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                scrollDirection: Axis.horizontal,
                itemCount: deals.length,
                itemBuilder: (context, index) {
                  final deal = deals[index];
                  final bgColor = _colorFromToken(deal['color']?.toString());
                  final img = _resolveAsset(deal['image_url']?.toString());
                  final code = deal['promo_code']?.toString();
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onTap: () => _onDealTap(deal),
                      child: Container(
                        width: 240,
                        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(16)),
                        child: Stack(
                          children: [
                            if (img != null)
                              Positioned(
                                right: -20,
                                bottom: -20,
                                child: Opacity(
                                  opacity: 0.8,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(100),
                                    child: Image.network(
                                      img,
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                                    ),
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    deal['title']?.toString() ?? '',
                                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    deal['subtitle']?.toString() ?? '',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  const Spacer(),
                                  Text(
                                    code != null && code.isNotEmpty ? 'Code: $code' : '*T&C Apply',
                                    style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700),
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
          ],
        ),
      ),
    );
  }

  void _showPromoSheet(String code) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Promo code', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(code,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied $code — apply at checkout'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Apply this code at checkout to get the discount.',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
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
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(Icons.restaurant_menu_rounded, size: 44, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 18),
            Text(
              'No restaurants available',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class RestaurantCard extends StatelessWidget {
  final Map<String, dynamic> restaurant;
  const RestaurantCard({super.key, required this.restaurant});

  @override
  Widget build(BuildContext context) {
    final isOpenNow = restaurant['is_open_now'] != false;
    final id = restaurant['id'] as int;
    final isFav = context.select<FoodProvider, bool>((f) => f.isFavorite(id));
    final dist = restaurant['distance_km'] as num?;

    return Pressable(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RestaurantDetailScreen(restaurantId: id)),
      ),
      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
      child: Opacity(
        opacity: isOpenNow ? 1 : 0.6,
        child: Container(
          margin: const EdgeInsets.only(bottom: 22),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppStyles.radiusMd),
            boxShadow: AppStyles.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppStyles.radiusMd),
                      topRight: Radius.circular(AppStyles.radiusMd),
                    ),
                    child: FoodImage(
                      url: restaurant['image_url']?.toString(),
                      height: 160,
                      width: double.infinity,
                      radius: 0,
                    ),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => context.read<FoodProvider>().toggleFavorite(id),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: AppStyles.shadowSm,
                        ),
                        child: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          size: 18,
                          color: isFav ? AppColors.food : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (!isOpenNow)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Text(
                          'CLOSED',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.timer_rounded, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${restaurant['eta_minutes'] ?? 30} min',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.delivery_dining_rounded, size: 13, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            formatRs(restaurant['delivery_fee'] as num?),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            restaurant['name']?.toString() ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((restaurant['cuisine']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              restaurant['cuisine'].toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    RatingPill(rating: restaurant['rating'] as num?, distanceKm: dist),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
