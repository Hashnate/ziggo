import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/animated_counter.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/widgets/pulse_dot.dart';
import '../../../core/network/api_client.dart';
import '../../auth/auth_provider.dart';
import '../booking_provider.dart';
import '../notifications_provider.dart';
import '../wallet_provider.dart';
import '../food_provider.dart';
import '../market_provider.dart';
import 'restaurant_detail_screen.dart';
import 'market_vendor_screen.dart';
import 'market_group_screen.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'fare_estimate_screen.dart';
import 'event_home_screen.dart';
import 'flash_home_screen.dart';
import 'flash_delivery_type_screen.dart';
import 'rental_type_screen.dart';
import 'food_home_screen.dart';
import 'market_home_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'location_search_screen.dart';
import 'promotions_screen.dart';
import 'ride_history_screen.dart';
import 'ride_tracking_screen.dart';
import 'saved_addresses_screen.dart';
import 'subscription_screen.dart';
import 'support_screen.dart';
import 'wallet_screen.dart';
import 'scan_and_go_screen.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onMenu;
  const HomeScreen({super.key, this.onMenu});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _autoRedirected = false;

  final PageController _foodBannerCtrl = PageController(viewportFraction: 0.93);
  final PageController _marketBannerCtrl = PageController(viewportFraction: 0.93);
  Timer? _foodBannerTimer;
  Timer? _marketBannerTimer;
  int _marketBannerPage = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  void _bootstrap() {
    context.read<WalletProvider>().refresh();
    context.read<BookingProvider>().loadActive();
    context.read<NotificationsProvider>().refresh();
    
    context.read<FoodProvider>().fetchHome();
    context.read<MarketProvider>().fetchAds();
    context.read<MarketProvider>().fetchCategories();

    _foodBannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_foodBannerCtrl.hasClients) {
        final p = context.read<FoodProvider>();
        if (p.banners.isEmpty) return;
        
        int nextPage = _foodBannerCtrl.page!.round() + 1;
        if (nextPage >= p.banners.length) {
          nextPage = 0;
        }
        _foodBannerCtrl.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });

    _marketBannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_marketBannerCtrl.hasClients) {
        final p = context.read<MarketProvider>();
        final itemsCount = p.ads.isNotEmpty ? p.ads.length : _kHomeMarketBanners.length;
        if (itemsCount == 0) return;
        
        int nextPage = _marketBannerPage - 1;
        if (nextPage < 0) {
          nextPage = itemsCount - 1;
        }
        _marketBannerCtrl.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _foodBannerTimer?.cancel();
    _marketBannerTimer?.cancel();
    _foodBannerCtrl.dispose();
    _marketBannerCtrl.dispose();
    super.dispose();
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  String? _resolveAsset(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${ApiConfig.baseHost}$path';
  }

  void _onFoodBannerTap(Map<String, dynamic> banner) {
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
        if (id != null) {
          food.setCategoryFilter(id);
          _open(const FoodHomeScreen());
        }
        break;
      case 'collection':
        final id = int.tryParse(value);
        if (id != null) {
          food.setCollectionFilter(id);
          _open(const FoodHomeScreen());
        }
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

  Future<void> _onMarketAdTap(Map<String, dynamic> ad) async {
    final type = ad['link_type']?.toString() ?? 'none';
    final value = ad['link_value']?.toString() ?? '';

    if (type == 'none' || type.isEmpty) {
      final vendorId = ad['vendor_id'] as int?;
      if (vendorId != null) {
        await _handleMarketRedirect('vendor', vendorId.toString());
      }
      return;
    }

    await _handleMarketRedirect(type, value);
  }

  Future<void> _handleMarketRedirect(String type, String value) async {
    switch (type) {
      case 'vendor':
        final vendorId = int.tryParse(value);
        if (vendorId == null) return;
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        );

        final vendor = await context.read<MarketProvider>().fetchVendorById(vendorId);
        
        if (mounted) {
          Navigator.pop(context);
          if (vendor != null) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MarketVendorScreen(vendor: vendor)),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not open store — please try again'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        break;

      case 'category':
        if (value.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MarketGroupScreen(groupName: value),
            ),
          );
        }
        break;

      case 'url':
        if (value.isNotEmpty) {
          final uri = Uri.tryParse(value);
          if (uri != null) {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        }
        break;

      default:
        break;
    }
  }

  Widget _buildFoodBanners() {
    final p = context.watch<FoodProvider>();
    final banners = p.banners;
    if (banners.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Food Offers',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _foodBannerCtrl,
            padEnds: true,
            itemCount: banners.length,
            itemBuilder: (context, index) {
              final banner = banners[index];
              final img = _resolveAsset(banner['image_url']?.toString());
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: GestureDetector(
                  onTap: () => _onFoodBannerTap(banner),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: img == null
                        ? Container(color: AppColors.surfaceMuted)
                        : Image.network(
                            img,
                            fit: BoxFit.fill,
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
              animation: _foodBannerCtrl,
              builder: (context, child) {
                double page = 0.0;
                if (_foodBannerCtrl.hasClients && _foodBannerCtrl.position.haveDimensions) {
                  page = _foodBannerCtrl.page ?? 0.0;
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
    );
  }

  Widget _buildFoodCategories() {
    final p = context.watch<FoodProvider>();
    final categories = p.categories;
    if (categories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Popular Categories',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final id = cat['id'] as int?;
              final img = _resolveAsset(cat['icon_url']?.toString());
              return GestureDetector(
                onTap: () {
                  if (id != null) {
                    p.setCategoryFilter(id);
                    _open(const FoodHomeScreen());
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, left: 4),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceMuted,
                          image: img != null
                              ? DecorationImage(image: NetworkImage(img), fit: BoxFit.cover)
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: img == null
                            ? const Icon(Icons.restaurant_rounded, color: AppColors.textTertiary, size: 28)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cat['name']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
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
    );
  }

  Widget _buildMarketBanners() {
    final p = context.watch<MarketProvider>();
    final ads = p.ads;
    final itemsCount = ads.isNotEmpty ? ads.length : _kHomeMarketBanners.length;
    if (itemsCount == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Market Offers',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _marketBannerCtrl,
            onPageChanged: (i) => setState(() => _marketBannerPage = i),
            itemCount: itemsCount,
            itemBuilder: (_, i) {
              if (ads.isNotEmpty) {
                final ad = ads[i];
                final imageUrl = _resolveAsset(ad['image_url']?.toString());
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: GestureDetector(
                    onTap: () => _onMarketAdTap(ad),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl,
                              fit: BoxFit.fill,
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
                return _marketBannerCard(_kHomeMarketBanners[i]);
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(itemsCount, (i) {
            final active = i == _marketBannerPage;
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
    );
  }

  Widget _marketBannerCard(_HomeMarketBanner b) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: b.image != null
            ? Image.asset(
                b.image!,
                fit: BoxFit.fill,
                width: double.infinity,
                errorBuilder: (_, __, ___) => _marketBannerGradient(b),
              )
            : _marketBannerGradient(b),
      ),
    );
  }

  Widget _marketBannerGradient(_HomeMarketBanner b) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: b.gradient,
        ),
        borderRadius: BorderRadius.circular(16),
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
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    b.tag,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  b.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  b.subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12.5,
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

  Widget _buildMarketCategories() {
    final p = context.watch<MarketProvider>();
    final categories = p.categories;
    if (categories.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Popular Categories',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final cat = categories[index];
              final name = cat['name']?.toString() ?? '';
              final rawImg = cat['image_url']?.toString() ?? '';
              
              Widget imageWidget;
              if (rawImg.startsWith('local:')) {
                final key = rawImg.replaceFirst('local:', '');
                String assetPath;
                switch (key) {
                  case 'groceries': assetPath = 'assets/images/marketplace/groceries.png'; break;
                  case 'pharmaceutical': assetPath = 'assets/images/marketplace/pharmaceutical.png'; break;
                  case 'freshproduce': assetPath = 'assets/images/marketplace/freshproduce.png'; break;
                  case 'household': assetPath = 'assets/images/marketplace/household.png'; break;
                  case 'dairy': assetPath = 'assets/images/marketplace/dairy.png'; break;
                  case 'babycare': assetPath = 'assets/images/marketplace/babycare.png'; break;
                  case 'poultryandmeat': assetPath = 'assets/images/marketplace/poultryandmeat.png'; break;
                  case 'personalcare': assetPath = 'assets/images/marketplace/personalcare.png'; break;
                  case 'seafood': assetPath = 'assets/images/marketplace/seafood.png'; break;
                  case 'petcare': assetPath = 'assets/images/marketplace/petcare.png'; break;
                  case 'frozenfoods': assetPath = 'assets/images/marketplace/frozenfoods.png'; break;
                  case 'cosmetics': assetPath = 'assets/images/marketplace/cosmetics.png'; break;
                  case 'freshflower': assetPath = 'assets/images/marketplace/freshflower.png'; break;
                  case 'bakery': assetPath = 'assets/images/marketplace/bakery-Photoroom.png'; break;
                  case 'stationery': assetPath = 'assets/images/marketplace/stationery.png'; break;
                  case 'electronics': assetPath = 'assets/images/marketplace/electronics.png'; break;
                  case 'ayurvedic': assetPath = 'assets/images/marketplace/ayurvedic.png'; break;
                  case '21+': assetPath = 'assets/images/marketplace/21+.png'; break;
                  case 'intimacy': assetPath = 'assets/images/marketplace/intimacy.png'; break;
                  default: assetPath = 'assets/images/marketplace/groceries.png';
                }
                imageWidget = Image.asset(assetPath, fit: BoxFit.contain);
              } else {
                final imageUrl = _resolveAsset(rawImg);
                imageWidget = imageUrl != null
                    ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.shopping_bag_rounded, color: AppColors.primary, size: 28))
                    : const Icon(Icons.shopping_bag_rounded, color: AppColors.primary, size: 28);
              }

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => MarketGroupScreen(groupName: name)),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 16, left: 4),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.surfaceMuted,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Center(
                            child: SizedBox(
                              width: 56,
                              height: 56,
                              child: imageWidget,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final wallet = context.watch<WalletProvider>();
    final booking = context.watch<BookingProvider>();
    final active = booking.activeBooking;

    final isRideActive = active != null &&
        (active['status'] == 'searching' ||
         active['status'] == 'accepted' ||
         active['status'] == 'arrived' ||
         active['status'] == 'started');

    final isCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (isRideActive && !_autoRedirected && isCurrent) {
      _autoRedirected = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _open(const RideTrackingScreen());
      });
    } else if (!isRideActive) {
      _autoRedirected = false;
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 140),
          children: staggered([
            _Header(
              auth: auth,
              onMenu: widget.onMenu ?? () {},
              onNotifications: () => _open(const NotificationsScreen()),
              onProfile: () => _open(const ProfileScreen()),
            ),
            const SizedBox(height: 20),
            if (isRideActive)
              _ActiveRideCard(
                active: active,
                onTap: () => _open(const RideTrackingScreen()),
              )
            else
              _HeroCard(onBook: () => _open(const FareEstimateScreen())),
            const SizedBox(height: 18),
            _SearchBar(onTap: () => _open(const FareEstimateScreen())),
            const SizedBox(height: 18),
            const _TrustBadges(),
            const SizedBox(height: 22),
            _WalletGoldRow(
              wallet: wallet,
              onWallet: () => _open(const WalletScreen()),
              onGold: () => _open(const SubscriptionScreen()),
            ),
            const SizedBox(height: 26),
            _SectionHeader(
              title: 'Our Services',
            ),
            const SizedBox(height: 16),
            _ServicesGrid(
              onRide: () => _open(const FareEstimateScreen()),
              onFood: () => _open(const FoodHomeScreen()),
              onFlash: () => _open(const FlashDeliveryTypeScreen()),
              onMarket: () => _open(const MarketHomeScreen()),
            ),
            const SizedBox(height: 26),
            _buildFoodBanners(),
            const SizedBox(height: 26),
            _buildFoodCategories(),
            const SizedBox(height: 26),
            _buildMarketBanners(),
            const SizedBox(height: 26),
            _buildMarketCategories(),
          ]),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final AuthProvider auth;
  final VoidCallback onMenu;
  final VoidCallback onNotifications;
  final VoidCallback onProfile;

  const _Header({
    required this.auth,
    required this.onMenu,
    required this.onNotifications,
    required this.onProfile,
  });

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final name = auth.fullName?.split(' ').first ?? 'there';
    final initial = (auth.fullName?.isNotEmpty ?? false)
        ? auth.fullName![0].toUpperCase()
        : 'Z';
    final hasUnread = context.watch<NotificationsProvider>().unreadCount > 0;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greeting()}, $name',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              const ZiggoWordmark(size: 38),
            ],
          ),
        ),
        if (auth.role == 'driver') ...[
          _IconBubble(
            icon: Icons.swap_horiz_rounded,
            onTap: () => auth.toggleCustomerMode(),
          ),
          const SizedBox(width: 10),
        ],
        _IconBubble(
          icon: Icons.notifications_none_rounded,
          onTap: onNotifications,
          badge: hasUnread,
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onProfile,
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppStyles.radiusSm),
              image: auth.profilePhoto != null && auth.profilePhoto!.isNotEmpty
                  ? DecorationImage(
                      image: auth.profilePhoto!.startsWith('http')
                          ? NetworkImage(auth.profilePhoto!)
                          : (auth.profilePhoto!.startsWith('/static')
                              ? NetworkImage('${ApiConfig.baseHost}${auth.profilePhoto!}')
                              : FileImage(File(auth.profilePhoto!)) as ImageProvider),
                      fit: BoxFit.cover,
                    )
                  : null,
              boxShadow: AppStyles.shadowSm,
            ),
            child: auth.profilePhoto == null || auth.profilePhoto!.isEmpty
                ? Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool badge;
  const _IconBubble({required this.icon, required this.onTap, this.badge = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppStyles.radiusSm),
              boxShadow: AppStyles.shadowSm,
            ),
            child: Icon(icon, color: AppColors.textPrimary, size: 22),
          ),
          if (badge)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.fromBorderSide(BorderSide(color: Colors.white, width: 2)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Premium gradient hero — the brand moment + primary call to action.
class _HeroCard extends StatelessWidget {
  final VoidCallback onBook;
  const _HeroCard({required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppStyles.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppStyles.radiusXl),
        child: Stack(
          children: [
            // Soft decorative circles
            Positioned(
              right: -30,
              top: -40,
              child: _circle(150, Colors.white.withOpacity(0.10)),
            ),
            Positioned(
              right: 30,
              bottom: -50,
              child: _circle(120, Colors.white.withOpacity(0.08)),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WELCOME TO',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const ZiggoWordmark(onDark: true, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    'Rides, food, market & parcels —\nall in one place.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
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

  Widget _circle(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

/// Shown in place of the hero when the customer has a ride in progress.
class _ActiveRideCard extends StatelessWidget {
  final Map<String, dynamic> active;
  final VoidCallback onTap;
  const _ActiveRideCard({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = (active['status'] as String? ?? '').toUpperCase();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.blackGradient,
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
          boxShadow: AppStyles.shadowMd,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppStyles.radiusSm),
              ),
              child: const Icon(Icons.directions_car_rounded,
                  color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const PulseDot(
                          color: AppColors.primaryLight, size: 7, pulseSize: 16),
                      const SizedBox(width: 6),
                      Text(
                        'ACTIVE RIDE • $status',
                        style: const TextStyle(
                          color: AppColors.primaryLight,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    active['booking_ref'] as String? ?? 'Your ride',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppStyles.radiusXs),
              ),
              child: const Icon(Icons.arrow_forward_rounded,
                  color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
          boxShadow: AppStyles.shadowMd,
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(AppStyles.radiusSm),
              ),
              child: const Icon(Icons.search_rounded,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Where are you going ?',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppStyles.radiusSm),
              ),
              child: const Icon(Icons.tune_rounded,
                  color: AppColors.textSecondary, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

/// Three reassurance badges, mirroring the premium "why choose us" strip.
class _TrustBadges extends StatelessWidget {
  const _TrustBadges();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Row(
        children: const [
          Expanded(
            child: _Badge(
              icon: Icons.bolt_rounded,
              tint: AppColors.primary,
              title: 'Fast Pickup',
              subtitle: 'In minutes',
            ),
          ),
          Expanded(
            child: _Badge(
              icon: Icons.verified_user_rounded,
              tint: AppColors.success,
              title: 'Safe & Secure',
              subtitle: 'Verified drivers',
            ),
          ),
          Expanded(
            child: _Badge(
              icon: Icons.my_location_rounded,
              tint: AppColors.flash,
              title: 'Live Tracking',
              subtitle: 'Real-time',
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
  const _Badge({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tint.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppStyles.radiusSm),
          ),
          child: Icon(icon, color: tint, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          subtitle,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _WalletGoldRow extends StatelessWidget {
  final WalletProvider wallet;
  final VoidCallback onWallet;
  final VoidCallback onGold;
  const _WalletGoldRow({
    required this.wallet,
    required this.onWallet,
    required this.onGold,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: onWallet,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(AppStyles.radiusXs),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wallet',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        AnimatedCounter(
                          value: wallet.balance,
                          prefix: 'Rs.',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onGold,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.blackGradient,
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
                boxShadow: AppStyles.shadowSm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppStyles.radiusXs),
                    ),
                    child: const Icon(Icons.stars_rounded,
                        color: Colors.black, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ziggo Gold',
                          style: TextStyle(
                            color: Colors.white60,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'Upgrade',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _SectionHeader({required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
        const Spacer(),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}

class _ServicesGrid extends StatelessWidget {
  final VoidCallback onRide;
  final VoidCallback onFood;
  final VoidCallback onFlash;
  final VoidCallback onMarket;
  const _ServicesGrid({
    required this.onRide,
    required this.onFood,
    required this.onFlash,
    required this.onMarket,
  });

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GradientServiceTile(
                icon: Icons.motorcycle_rounded,
                imageAsset: 'assets/icons/bike.png',
                label: 'Rides',
                onTap: onRide,
              ),
              GradientServiceTile(
                icon: Icons.restaurant_rounded,
                imageAsset: 'assets/icons/food.png',
                imagePadding: const EdgeInsets.all(14),
                label: 'Food',
                onTap: onFood,
              ),
              GradientServiceTile(
                icon: Icons.flash_on_rounded,
                imageAsset: 'assets/icons/flash.png',
                label: 'Delivery',
                badgeText: 'FLASH',
                onTap: onFlash,
              ),
              GradientServiceTile(
                icon: Icons.shopping_basket_rounded,
                imageAsset: 'assets/icons/basket.png',
                label: 'Market',
                onTap: onMarket,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GradientServiceTile(
                icon: Icons.local_shipping_rounded,
                imageAsset: 'assets/icons/truck.png',
                label: 'Trucks',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FareEstimateScreen(isTruckMode: true)),
                ),
              ),
              GradientServiceTile(
                icon: Icons.event_rounded,
                imageAsset: 'assets/icons/event.png',
                label: 'Event',
                isNew: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EventHomeScreen(),
                  ),
                ),
              ),
              GradientServiceTile(
                icon: Icons.key_rounded,
                imageAsset: 'assets/icons/rental.png',
                label: 'Rental',
                isNew: true,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RentalTypeScreen(),
                  ),
                ),
              ),
              GradientServiceTile(
                icon: Icons.qr_code_scanner_rounded,
                label: 'Scan & Go',
                gradientColors: const [Color(0xFFFBBF24), Color(0xFFFF7849)],
                iconColor: Colors.white,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ScanAndGoScreen(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Slim promo banner for the Gold tier.
class _GoldStrip extends StatelessWidget {
  final VoidCallback onTap;
  const _GoldStrip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: AppColors.goldTierGradient,
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(AppStyles.radiusSm),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: AppColors.accent, size: 24),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Go Ziggo Gold',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Priority rides, lower fees & perks',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11.5,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: Colors.black, size: 20),
          ],
        ),
      ),
    );
  }
}

class CustomerDrawer extends StatelessWidget {
  final VoidCallback onProfile;
  final VoidCallback onPlaces;
  final VoidCallback onTrips;
  final VoidCallback onPromos;
  final VoidCallback onWallet;
  final VoidCallback onNotifications;
  final VoidCallback onSupport;
  final VoidCallback onGold;

  const CustomerDrawer({
    required this.onProfile,
    required this.onPlaces,
    required this.onTrips,
    required this.onPromos,
    required this.onWallet,
    required this.onNotifications,
    required this.onSupport,
    required this.onGold,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final wallet = context.watch<WalletProvider>();
    final name = auth.fullName ?? 'Welcome';
    final phone = auth.phoneNumber ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'Z';
    final photo = auth.profilePhoto;
    final hasPhoto = photo != null && photo.isNotEmpty;
    final isNetwork = hasPhoto && photo.startsWith('http');
    final isLocalPath = hasPhoto && !isNetwork && photo.startsWith('/');

    final fallback = Center(
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 26,
        ),
      ),
    );

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppStyles.radiusLg),
                boxShadow: AppStyles.shadowSm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                      child: hasPhoto
                          ? (isNetwork || !isLocalPath
                              ? Image.network(
                                  isNetwork ? photo! : '${ApiConfig.baseHost}/$photo',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => fallback,
                                )
                              : Image.file(
                                  File(photo!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => fallback,
                                ))
                          : fallback,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          phone,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  _item(Icons.stars_rounded, 'Ziggo Gold', onGold, color: AppColors.warning),
                  _item(Icons.history_rounded, 'My Trips', () { Navigator.pop(context); onTrips(); }),
                  _item(Icons.bookmark_rounded, 'Saved Places', () { Navigator.pop(context); onPlaces(); }),
                  _item(Icons.local_offer_rounded, 'Promos & Offers', () { Navigator.pop(context); onPromos(); }),
                  _item(Icons.account_balance_wallet_rounded,
                      'Wallet (Rs.${wallet.balance.toStringAsFixed(0)})',
                      () { Navigator.pop(context); onWallet(); }),
                  _item(Icons.person_rounded, 'Profile', () { Navigator.pop(context); onProfile(); }),
                  _item(Icons.notifications_rounded, 'Notifications',
                      () { Navigator.pop(context); onNotifications(); }),
                  _item(Icons.support_agent_rounded, 'Support',
                      () { Navigator.pop(context); onSupport(); }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: () => context.read<AuthProvider>().logout(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Log out',
                        style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String title, VoidCallback onTap, {Color? color}) {
    return ListTile(
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppStyles.radiusXs)),
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: (color ?? AppColors.textPrimary).withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppStyles.radiusXs),
        ),
        child: Icon(icon, color: color ?? AppColors.textPrimary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
    );
  }
}

class _HomeMarketBanner {
  final String tag;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final String? image;
  const _HomeMarketBanner(this.tag, this.title, this.subtitle, this.icon, this.gradient,
      {this.image});
}

const _kHomeMarketBanners = <_HomeMarketBanner>[
  _HomeMarketBanner('REGISTERED DEVICES', 'Now Available', 'Mobiles & accessories',
      Icons.phone_iphone_rounded, [Color(0xFF172554), Color(0xFF1E40AF)]),
  _HomeMarketBanner('FRESH DAILY', 'Groceries to your door', 'Delivered in minutes',
      Icons.shopping_basket_rounded, [Color(0xFF0E7A52), Color(0xFF16A34A)]),
  _HomeMarketBanner('SAVE BIG', 'Up to 50% off', 'On selected outlets today',
      Icons.percent_rounded, [Color(0xFF7C3AED), Color(0xFF5B21B6)]),
];

