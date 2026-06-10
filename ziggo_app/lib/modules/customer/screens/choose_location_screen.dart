import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/map/recent_places.dart';
import '../addresses_provider.dart';
import 'saved_addresses_screen.dart';

/// Full-screen delivery-location chooser. Pops a [Place] when the user picks
/// a location (current GPS, search, set-on-map, a saved address or a recent).
class ChooseLocationScreen extends StatefulWidget {
  const ChooseLocationScreen({super.key});

  @override
  State<ChooseLocationScreen> createState() => _ChooseLocationScreenState();
}

class _ChooseLocationScreenState extends State<ChooseLocationScreen> {
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AddressesProvider>().refresh();
    });
    RecentPlaces.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _return(Place place) {
    if (!mounted) return;
    RecentPlaces.add(place);
    Navigator.pop(context, place);
  }

  Future<void> _search() async {
    final p = await showPlaceSearch(context, title: 'Search location');
    if (p != null) _return(p);
  }

  Future<void> _useCurrent() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _locating = true);
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted) return;
    setState(() => _locating = false);
    if (here != null) {
      _return(here);
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not get your location'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addLabelled(String label) async {
    final provider = context.read<AddressesProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final p = await showPlaceSearch(context, title: 'Add $label');
    if (p == null) return;
    final ok = await provider.add(
      label: label,
      address: p.fullAddress,
      lat: p.location.latitude,
      lng: p.location.longitude,
    );
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? '$label saved' : 'Could not save $label'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<AddressesProvider>().items;
    final recents = RecentPlaces.items;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Location',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 19,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _searchField(),
          const SizedBox(height: 18),
          _actionCard(saved.length),
          const SizedBox(height: 20),
          _labelRow(
            icon: Icons.home_rounded,
            label: 'Add Home',
            onTap: () => _addLabelled('Home'),
          ),
          const SizedBox(height: 14),
          _labelRow(
            icon: Icons.work_rounded,
            label: 'Add Work',
            onTap: () => _addLabelled('Work'),
          ),
          if (recents.isNotEmpty) ...[
            const SizedBox(height: 22),
            _recentHeader(recents.length),
            const SizedBox(height: 6),
            ...recents.map(_recentTile),
          ],
        ],
      ),
    );
  }

  Widget _searchField() {
    return GestureDetector(
      onTap: _search,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(100),
        ),
        child: const Row(
          children: [
            Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 22),
            SizedBox(width: 12),
            Text(
              'Search location',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionCard(int savedCount) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        children: [
          _actionRow(
            icon: Icons.my_location_rounded,
            label: 'Your current location',
            trailing: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: AppColors.primary),
                  )
                : const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary),
            onTap: _locating ? null : _useCurrent,
          ),
          const Divider(height: 1, color: AppColors.divider, indent: 56),
          _actionRow(
            icon: Icons.pin_drop_rounded,
            label: 'Set on map',
            trailing: const Icon(Icons.chevron_right_rounded,
                color: AppColors.textTertiary),
            onTap: _search,
          ),
          const Divider(height: 1, color: AppColors.divider, indent: 56),
          _actionRow(
            icon: Icons.favorite_border_rounded,
            label: 'Saved Addresses',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$savedCount',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SavedAddressesScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String label,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _labelRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppStyles.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.add_rounded, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _recentHeader(int count) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppStyles.radiusXs),
      ),
      child: Text(
        'Recent locations ($count)',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _recentTile(Place p) {
    return InkWell(
      onTap: () => _return(p),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.history_rounded,
                  color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.area,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
