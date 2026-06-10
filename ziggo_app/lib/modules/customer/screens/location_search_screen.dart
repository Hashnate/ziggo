import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/map/recent_places.dart';
import '../../../core/map/ziggo_map.dart';
import '../../customer/addresses_provider.dart';
import 'vehicle_selection_screen.dart';

class LocationSearchScreen extends StatefulWidget {
  final Place? initialPickup;
  final Place? initialDrop;
  final String initialTripType;
  final bool isTruckMode;

  const LocationSearchScreen({
    super.key,
    this.initialPickup,
    this.initialDrop,
    this.initialTripType = 'one_way',
    this.isTruckMode = false,
  });

  @override
  State<LocationSearchScreen> createState() => _LocationSearchScreenState();
}

class _LocationSearchScreenState extends State<LocationSearchScreen> {
  final _pickupController = TextEditingController();
  final _dropController = TextEditingController();
  
  // Focus nodes to know which field the user is currently typing in
  final _pickupFocus = FocusNode();
  final _dropFocus = FocusNode();

  Place? _pickup;
  Place? _drop;
  String _tripType = 'one_way';
  ({String name, String phone})? _friend;

  List<PlacePrediction> _results = const [];
  bool _loading = false;
  bool _resolving = false;
  Timer? _debounce;
  
  bool get _isPickupFocused => _pickupFocus.hasFocus;

  @override
  void initState() {
    super.initState();
    _pickup = widget.initialPickup;
    _drop = widget.initialDrop;
    _tripType = widget.initialTripType;

    if (_pickup != null) {
      _pickupController.text = _pickup!.name;
    }
    if (_drop != null) {
      _dropController.text = _drop!.name;
    }

    _pickupFocus.addListener(_onFocusChange);
    _dropFocus.addListener(_onFocusChange);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AddressesProvider>().refresh();
      // Auto focus drop if it's empty
      if (_drop == null) {
        _dropFocus.requestFocus();
      }
    });
    RecentPlaces.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _onFocusChange() {
    setState(() {
      _results = const [];
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _pickupController.dispose();
    _dropController.dispose();
    _pickupFocus.dispose();
    _dropFocus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String q) {
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
      final near = _pickup?.location ?? kColomboCenter;
      final r = await MapsService.instance.autocomplete(q, near: near);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    });
  }

  Future<void> _selectPrediction(PlacePrediction p) async {
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
    
    _setPlace(Place(p.mainText, p.secondaryText, coords));
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
    
    _setPlace(here);
  }
  
  void _setPlace(Place place) {
    RecentPlaces.add(place);
    if (_isPickupFocused) {
      setState(() {
        _pickup = place;
        _pickupController.text = place.name;
        _results = const [];
      });
      if (_drop == null) {
        _dropFocus.requestFocus();
      } else {
        _proceedToVehicleSelection();
      }
    } else {
      setState(() {
        _drop = place;
        _dropController.text = place.name;
        _results = const [];
      });
      if (_pickup == null) {
        _pickupFocus.requestFocus();
      } else {
        _proceedToVehicleSelection();
      }
    }
  }

  void _proceedToVehicleSelection() {
    if (_pickup == null || _drop == null) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleSelectionScreen(
          pickup: _pickup!,
          drop: _drop!,
          tripType: _tripType,
          friend: _friend,
          isTruckMode: widget.isTruckMode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () => _showBookForFriendSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_outline_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  _friend != null ? 'Booking for ${_friend!.name}' : 'Book for a friend',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text(
              'Skip',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                _tripTypeToggle(),
                const SizedBox(height: 16),
                _locationInputs(),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Container(height: 8, color: AppColors.background),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _tripTypeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppStyles.radiusSm),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tripType = 'one_way'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _tripType == 'one_way' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                  boxShadow: _tripType == 'one_way' ? AppStyles.shadowSm : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _tripType == 'one_way' ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: _tripType == 'one_way' ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'One way',
                      style: TextStyle(
                        fontWeight: _tripType == 'one_way' ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 13,
                        color: _tripType == 'one_way' ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tripType = 'return'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _tripType == 'return' ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                  boxShadow: _tripType == 'return' ? AppStyles.shadowSm : null,
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _tripType == 'return' ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: _tripType == 'return' ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Return trip*',
                      style: TextStyle(
                        fontWeight: _tripType == 'return' ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 13,
                        color: _tripType == 'return' ? AppColors.textPrimary : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationInputs() {
    return Row(
      children: [
        Column(
          children: [
            const Text('PICKUP', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w900)),
            Container(height: 20, width: 2, color: AppColors.divider),
            const Text('DROP', style: TextStyle(color: AppColors.primaryDark, fontSize: 10, fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              TextField(
                controller: _pickupController,
                focusNode: _pickupFocus,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Your Location',
                  hintStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  border: InputBorder.none,
                  suffixIcon: _pickupController.text.isNotEmpty ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _pickupController.clear();
                      setState(() => _pickup = null);
                      _onSearchChanged('');
                    },
                  ) : null,
                ),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const Divider(height: 1),
              TextField(
                controller: _dropController,
                focusNode: _dropFocus,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Where are you going?',
                  hintStyle: const TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w600),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add_rounded, size: 24, color: AppColors.textPrimary),
                    onPressed: () {}, // Add intermediate stop (omitted for now to match UI)
                  ),
                ),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.6));
    }

    if (_results.isNotEmpty) {
      return Container(
        color: Colors.white,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _results.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 40),
          itemBuilder: (_, i) {
            final p = _results[i];
            return ListTile(
              onTap: _resolving ? null : () => _selectPrediction(p),
              leading: const Icon(Icons.location_on_rounded, color: AppColors.textSecondary),
              title: Text(p.mainText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: p.secondaryText.isEmpty ? null : Text(p.secondaryText, style: const TextStyle(fontSize: 12)),
            );
          },
        ),
      );
    }

    // Default view: saved addresses, set location on map, etc.
    final addrProvider = context.watch<AddressesProvider>();
    final saved = addrProvider.items;
    final recents = RecentPlaces.items;

    return Container(
      color: Colors.white,
      child: ListView(
        children: [
          if (_isPickupFocused)
            ListTile(
              onTap: _selectCurrentLocation,
              leading: const Icon(Icons.my_location_rounded, color: AppColors.primary),
              title: const Text('Your current location', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (recents.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
              child: Row(
                children: [
                  const Text(
                    'RECENT',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textTertiary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      await RecentPlaces.clear();
                      if (mounted) setState(() {});
                    },
                    child: const Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final p in recents)
              ListTile(
                onTap: _resolving ? null : () => _setPlace(p),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.history_rounded,
                      color: AppColors.textSecondary, size: 20),
                ),
                title: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: p.area.isEmpty
                    ? null
                    : Text(
                        p.area,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
              ),
            const Divider(height: 1, indent: 56),
          ],
          ListTile(
            onTap: () {
              // TODO: Implement saved addresses screen logic or expand
            },
            leading: const Icon(Icons.favorite_border_rounded, color: AppColors.textPrimary),
            title: const Text('Saved Addresses', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            trailing: const Icon(Icons.chevron_right_rounded),
          ),
          const Divider(height: 1, indent: 56),
          ListTile(
            onTap: () async {
              final p = await showPlaceSearch(context, title: 'Set location');
              if (p != null && mounted) _setPlace(p);
            },
            leading: const Icon(Icons.pin_drop_outlined, color: AppColors.textPrimary),
            title: const Text('Set location on map', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          const SizedBox(height: 16),
          ListTile(
            onTap: () async {
              final p = await showPlaceSearch(context, title: 'Add Home Address');
              if (p != null && mounted) {
                await context.read<AddressesProvider>().add(
                  label: 'Home',
                  address: p.fullAddress,
                  lat: p.location.latitude,
                  lng: p.location.longitude,
                  isDefault: false,
                );
                _setPlace(p);
              }
            },
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.home_outlined, color: AppColors.primary, size: 20),
            ),
            title: const Text('Add Home', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            trailing: const Icon(Icons.add_rounded, color: AppColors.textSecondary),
          ),
          ListTile(
            onTap: () async {
              final p = await showPlaceSearch(context, title: 'Add Work Address');
              if (p != null && mounted) {
                await context.read<AddressesProvider>().add(
                  label: 'Work',
                  address: p.fullAddress,
                  lat: p.location.latitude,
                  lng: p.location.longitude,
                  isDefault: false,
                );
                _setPlace(p);
              }
            },
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.work_outline_rounded, color: AppColors.primary, size: 20),
            ),
            title: const Text('Add Work', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            trailing: const Icon(Icons.add_rounded, color: AppColors.textSecondary),
          ),
          if (saved.isNotEmpty) ...[
            for (final a in saved)
              ListTile(
                onTap: _resolving ? null : () {
                  final lat = (a['lat'] as num).toDouble();
                  final lng = (a['lng'] as num).toDouble();
                  final address = a['address'].toString();
                  _setPlace(Place(a['label']?.toString() ?? 'Saved Place', address, LatLng(lat, lng)));
                },
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.history_rounded, color: AppColors.primary, size: 20),
                ),
                title: Text(a['label']?.toString() ?? 'Saved Place', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(
                  a['address']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
              ),
          ],
        ],
      ),
    );
  }

  void _showBookForFriendSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Who are you booking for?',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    ListTile(
                      onTap: () {
                        // TODO: Implement phone book
                        Navigator.pop(ctx);
                      },
                      leading: const Icon(Icons.contact_phone_outlined, color: AppColors.textPrimary),
                      title: const Text('Phone book', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      onTap: () {
                        setState(() => _friend = null);
                        Navigator.pop(ctx);
                      },
                      leading: const Icon(Icons.person_outline_rounded, color: AppColors.textPrimary),
                      title: const Text('Set as you', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      trailing: _friend == null ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      onTap: () {
                        // Mock recent contact
                        setState(() => _friend = (name: 'John Doe', phone: '+94771234567'));
                        Navigator.pop(ctx);
                      },
                      leading: const Icon(Icons.history_rounded, color: AppColors.textPrimary),
                      title: const Text('Recent contacts (1)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  onTap: () {
                    Navigator.pop(ctx);
                    _showNewContactDialog();
                  },
                  title: const Text('Create new contact', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  trailing: const Icon(Icons.add_rounded, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewContactDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. John'), textCapitalization: TextCapitalization.words),
            const SizedBox(height: 10),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number', hintText: 'e.g. 0771234567'), keyboardType: TextInputType.phone),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty && phoneCtrl.text.trim().isNotEmpty) {
                setState(() => _friend = (name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim()));
                Navigator.pop(ctx);
              }
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }
}
