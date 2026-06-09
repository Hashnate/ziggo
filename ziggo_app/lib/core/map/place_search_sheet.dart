import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:provider/provider.dart';

import '../../app/app_colors.dart';
import '../../app/app_styles.dart';
import '../../modules/customer/addresses_provider.dart';
import 'maps_service.dart';
import 'places.dart';

/// Opens a Google Places-backed search sheet and returns the chosen [Place]
/// (with resolved coordinates), or null if dismissed.
Future<Place?> showPlaceSearch(
  BuildContext context, {
  String title = 'Search location',
  LatLng? near,
  bool allowCurrentLocation = false,
  bool allowSetOnMap = false,
}) {
  return showModalBottomSheet<Place>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppStyles.radiusXl)),
    ),
    builder: (_) => _PlaceSearchSheet(
      title: title,
      near: near,
      allowCurrentLocation: allowCurrentLocation,
      allowSetOnMap: allowSetOnMap,
    ),
  );
}

class _PlaceSearchSheet extends StatefulWidget {
  final String title;
  final LatLng? near;
  final bool allowCurrentLocation;
  final bool allowSetOnMap;
  const _PlaceSearchSheet({
    required this.title,
    this.near,
    this.allowCurrentLocation = false,
    this.allowSetOnMap = false,
  });

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _controller = TextEditingController();
  List<PlacePrediction> _results = const [];
  bool _loading = false;
  bool _resolving = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AddressesProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() {
        _results = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final r = await MapsService.instance.autocomplete(q, near: widget.near);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    });
  }

  Future<void> _select(PlacePrediction p) async {
    setState(() => _resolving = true);
    final coords = await MapsService.instance.placeLatLng(p.placeId);
    if (!mounted) return;
    setState(() => _resolving = false);
    if (coords == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not resolve that location')),
      );
      return;
    }
    Navigator.pop(context, Place(p.mainText, p.secondaryText, coords));
  }

  Future<void> _selectCurrentLocation() async {
    setState(() => _resolving = true);
    final here = await MapsService.instance.currentLocationAsPlace();
    if (!mounted) return;
    setState(() => _resolving = false);
    if (here == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not get current location — check GPS / permission'),
        ),
      );
      return;
    }
    Navigator.pop(context, here);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  if (_resolving)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search for a place or address',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: AppColors.textSecondary),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            _onChanged('');
                          },
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      );
    }
    if (_controller.text.trim().length < 2) {
      final addrProvider = context.watch<AddressesProvider>();
      final saved = addrProvider.items;
      return Column(
        children: [
          if (widget.allowCurrentLocation) _currentLocationTile(),
          if (widget.allowSetOnMap) _setOnMapTile(),
          if (saved.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'SAVED PLACES',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: saved.length,
                itemBuilder: (_, i) {
                  final a = saved[i];
                  final label = a['label']?.toString() ?? 'Saved Place';
                  IconData icon = Icons.place_rounded;
                  Color color = AppColors.market;
                  final l = label.toLowerCase();
                  if (l.contains('home')) {
                    icon = Icons.home_rounded;
                    color = AppColors.primary;
                  } else if (l.contains('work') || l.contains('office')) {
                    icon = Icons.work_rounded;
                    color = AppColors.flash;
                  } else if (l.contains('gym')) {
                    icon = Icons.fitness_center_rounded;
                    color = AppColors.bike;
                  }
                  
                  return ListTile(
                    onTap: _resolving ? null : () {
                      final lat = (a['lat'] as num).toDouble();
                      final lng = (a['lng'] as num).toDouble();
                      final address = a['address'].toString();
                      Navigator.pop(context, Place(label, address, LatLng(lat, lng)));
                    },
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: AppColors.serviceGradient(color),
                        borderRadius: BorderRadius.circular(AppStyles.radiusXs),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    subtitle: Text(
                      a['address']?.toString() ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else
            const Expanded(
              child: _Hint(
                icon: Icons.travel_explore_rounded,
                text: 'Start typing to search anywhere in Sri Lanka',
              ),
            ),
        ],
      );
    }
    if (_results.isEmpty) {
      return const _Hint(
        icon: Icons.search_off_rounded,
        text: 'No places found — try a different search',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 2),
      itemBuilder: (_, i) {
        final p = _results[i];
        return ListTile(
          onTap: _resolving ? null : () => _select(p),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusSm),
          ),
          leading: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(AppStyles.radiusXs),
            ),
            child: const Icon(Icons.location_on_rounded,
                color: AppColors.primary, size: 20),
          ),
          title: Text(
            p.mainText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          subtitle: p.secondaryText.isEmpty
              ? null
              : Text(
                  p.secondaryText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
        );
      },
    );
  }

  Widget _setOnMapTile() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ListTile(
        onTap: () {
          Navigator.pop(context, Place('__SET_ON_MAP__', '', widget.near ?? const LatLng(6.9271, 79.8612)));
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusSm),
        ),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(AppStyles.radiusXs),
          ),
          child: const Icon(Icons.pin_drop_outlined, color: AppColors.primary, size: 20),
        ),
        title: const Text(
          'Set on map',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
      ),
    );
  }

  Widget _currentLocationTile() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ListTile(
        onTap: _resolving ? null : _selectCurrentLocation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusSm),
        ),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.10),
            borderRadius: BorderRadius.circular(AppStyles.radiusXs),
          ),
          child: _resolving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: AppColors.primary,
                  ),
                )
              : const Icon(Icons.my_location_rounded,
                  color: AppColors.primary, size: 20),
        ),
        title: Text(
          _resolving ? 'Getting your location…' : 'Use current location',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        subtitle: Text(
          _resolving ? 'Hang on a moment' : 'Pin to your live GPS',
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
