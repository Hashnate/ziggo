import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/map/recent_places.dart';
import '../../../core/map/ziggo_map.dart';
import '../../customer/addresses_provider.dart';
import 'vehicle_selection_screen.dart';
import 'confirm_pickup_screen.dart';
import 'saved_addresses_screen.dart';
import 'map_location_selection_screen.dart';
import 'add_stops_screen.dart';

class LocationSearchScreen extends StatefulWidget {
  final Place? initialPickup;
  final Place? initialDrop;
  final String initialTripType;
  final bool isTruckMode;
  final List<Place> initialStops;
  final DateTime? initialScheduledTime;

  const LocationSearchScreen({
    super.key,
    this.initialPickup,
    this.initialDrop,
    this.initialTripType = 'one_way',
    this.isTruckMode = false,
    this.initialStops = const [],
    this.initialScheduledTime,
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
  List<Place> _stops = [];

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
    _stops = List.from(widget.initialStops);

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
  
  Future<void> _setPlace(Place place) async {
    if (place.name == '__SET_ON_MAP__') {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapLocationSelectionScreen(
            initialPickup: _pickup,
            initialDrop: _drop,
            initialTripType: _tripType,
            isTruckMode: widget.isTruckMode,
            startWithPickup: _isPickupFocused,
          ),
        ),
      );
      return;
    }
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
    
    // Prefetch estimates to load them instantly
    final booking = context.read<BookingProvider>();
    final serviceTypes = widget.isTruckMode ? <String>[] : ['tuk', 'bike', 'car', 'mini', 'van', 'truck'];
    booking.prefetchEstimates(
      serviceTypes: serviceTypes,
      pickup: _pickup!.location,
      drop: _drop!.location,
      tripType: _tripType,
      stops: _stops.map((s) => {
        'lat': s.location.latitude,
        'lng': s.location.longitude,
        'address': s.name,
      }).toList(),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VehicleSelectionScreen(
          pickup: _pickup!,
          drop: _drop!,
          tripType: _tripType,
          friend: _friend,
          isTruckMode: widget.isTruckMode,
          stops: _stops,
          scheduledTime: widget.initialScheduledTime,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Plan your ride',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () => _showBookForFriendSheet(context),
            icon: Icon(
              _friend != null ? Icons.how_to_reg_rounded : Icons.person_add_alt_1_rounded,
              color: AppColors.primary,
            ),
            tooltip: 'Book for a friend',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _tripTypeToggle(),
                const SizedBox(height: 24),
                _locationInputs(),
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
    return Row(
      children: [
        GestureDetector(
          onTap: () => setState(() => _tripType = 'one_way'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: _tripType == 'one_way' ? AppColors.primary : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'One way',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: _tripType == 'one_way' ? AppColors.surface : AppColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () => setState(() => _tripType = 'return'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: _tripType == 'return' ? AppColors.primary : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Return trip*',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: _tripType == 'return' ? AppColors.surface : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _locationInputs() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.divider,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 18),
            child: Column(
              children: [
                const Icon(Icons.my_location_rounded, size: 20, color: AppColors.primary),
                Container(
                  height: 36,
                  width: 2,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  color: AppColors.textTertiary.withOpacity(0.3),
                ),
                Icon(
                  _tripType == 'return' ? Icons.stop_circle_rounded : Icons.location_on_rounded,
                  size: 20,
                  color: AppColors.error,
                ),
                if (_tripType == 'return') ...[
                  Container(
                    height: 36,
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: AppColors.textTertiary.withOpacity(0.3),
                  ),
                  const Icon(Icons.location_on_rounded, size: 20, color: AppColors.error),
                ]
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _pickupController,
                  focusNode: _pickupFocus,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Pickup Location',
                    hintStyle: const TextStyle(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    suffixIcon: _pickupController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20, color: AppColors.textSecondary),
                            onPressed: () {
                              _pickupController.clear();
                              setState(() => _pickup = null);
                              _onSearchChanged('');
                            },
                          )
                        : null,
                  ),
                ),
                Divider(height: 1, thickness: 1, color: AppColors.divider.withOpacity(0.5)),
                TextField(
                  controller: _dropController,
                  focusNode: _dropFocus,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: _tripType == 'return' ? 'Stop Location' : 'Where to?',
                    hintStyle: const TextStyle(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 22, color: AppColors.textPrimary),
                      onPressed: () async {
                        if (_pickup == null) return;
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddStopsScreen(
                              pickup: _pickup!,
                              initialStops: _stops,
                              initialDrop: _drop,
                            ),
                          ),
                        );
                        if (result != null && result is Map && mounted) {
                          setState(() {
                            _stops = List<Place>.from(result['stops']);
                            _drop = result['drop'] as Place;
                            _dropController.text = _drop!.name;
                          });
                          _proceedToVehicleSelection();
                        }
                      },
                    ),
                  ),
                ),
                if (_tripType == 'return') ...[
                  Divider(height: 1, thickness: 1, color: AppColors.divider.withOpacity(0.5)),
                  Container(
                    height: 52,
                    alignment: Alignment.centerLeft,
                    child: const Text(
                      'Same as pickup',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2.6));
    }

    if (_results.isNotEmpty) {
      return Container(
        color: AppColors.surface,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: _results.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final p = _results[i];
            return ListTile(
              onTap: _resolving ? null : () => _selectPrediction(p),
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: const Icon(Icons.location_on_rounded, color: AppColors.textSecondary),
              title: Text(p.mainText, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              subtitle: p.secondaryText.isEmpty ? null : Text(p.secondaryText, style: const TextStyle(fontSize: 12.5)),
            );
          },
        ),
      );
    }

    final addrProvider = context.watch<AddressesProvider>();
    final saved = addrProvider.items;
    final recents = RecentPlaces.items;

    return Container(
      color: AppColors.surface,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          if (_isPickupFocused)
            ListTile(
              onTap: _selectCurrentLocation,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: const Icon(Icons.my_location_rounded, color: AppColors.primary),
              title: const Text('Your current location', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            ),
          if (recents.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Text(
                    'RECENT',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textTertiary,
                      letterSpacing: 0.5,
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
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (final p in recents) ...[
              ListTile(
                onTap: _resolving ? null : () => _setPlace(p),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: const Padding(
                  padding: EdgeInsets.only(top: 4.0),
                  child: Icon(
                    Icons.access_time_rounded,
                    color: AppColors.textTertiary,
                    size: 24,
                  ),
                ),
                title: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: p.area.isEmpty
                    ? null
                    : Text(
                        p.area,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
              const Divider(height: 1, color: AppColors.divider),
            ],
          ],
          ListTile(
            onTap: () async {
              final p = await Navigator.push<Place?>(
                context,
                MaterialPageRoute(
                  builder: (_) => const SavedAddressesScreen(selectMode: true),
                ),
              );
              if (p != null && mounted) _setPlace(p);
            },
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: const Icon(
              Icons.favorite_border_rounded,
              color: AppColors.textPrimary,
              size: 24,
            ),
            title: const Text(
              'Saved Addresses',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textPrimary,
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          ListTile(
            onTap: () async {
              if (!mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MapLocationSelectionScreen(
                    initialPickup: _pickup,
                    initialDrop: _drop,
                    initialTripType: _tripType,
                    isTruckMode: widget.isTruckMode,
                    startWithPickup: _isPickupFocused,
                  ),
                ),
              );
            },
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: const Icon(
              Icons.location_on_outlined,
              color: AppColors.textPrimary,
              size: 24,
            ),
            title: const Text(
              'Set location on map',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
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
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.home_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            title: const Text(
              'Add Home',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            trailing: const Icon(
              Icons.add_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
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
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            leading: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.work_outline_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            title: const Text(
              'Add Work',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            trailing: const Icon(
              Icons.add_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          if (saved.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.divider),
            for (final a in saved) ...[
              ListTile(
                onTap: _resolving
                    ? null
                    : () {
                        final lat = (a['lat'] as num).toDouble();
                        final lng = (a['lng'] as num).toDouble();
                        final address = a['address'].toString();
                        _setPlace(
                          Place(
                            a['label']?.toString() ?? 'Saved Place',
                            address,
                            LatLng(lat, lng),
                          ),
                        );
                      },
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                leading: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceMuted,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  a['label']?.toString() ?? 'Saved Place',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: AppColors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  a['address']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
            ],
          ],
        ],
      ),
    );
  }

  void _showBookForFriendSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
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
                      onTap: () async {
                        if (await FlutterContacts.permissions.request(PermissionType.read) == PermissionStatus.granted) {
                          final contact = await FlutterContacts.native.showPicker(properties: {ContactProperty.phone});
                          if (contact != null && contact.phones.isNotEmpty) {
                            setState(() => _friend = (name: contact.displayName ?? 'Unknown', phone: contact.phones.first.number));
                          }
                        }
                        if (context.mounted) Navigator.pop(ctx);
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
