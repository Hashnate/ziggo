import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/widgets/motion.dart';
import '../restaurant_provider.dart';
import '../widgets/image_picker_tile.dart';

class RestaurantProfileEditScreen extends StatefulWidget {
  const RestaurantProfileEditScreen({super.key});

  @override
  State<RestaurantProfileEditScreen> createState() =>
      _RestaurantProfileEditScreenState();
}

class _RestaurantProfileEditScreenState
    extends State<RestaurantProfileEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _phone;
  late final TextEditingController _cuisine;
  late final TextEditingController _opening;
  late final TextEditingController _closing;
  late final TextEditingController _fee;
  late final TextEditingController _eta;

  Place? _newPlace;
  File? _pickedCover;
  bool _savingCover = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p =
        context.read<RestaurantProvider>().profile ?? const <String, dynamic>{};
    _name = TextEditingController(text: p['name']?.toString() ?? '');
    _description =
        TextEditingController(text: p['description']?.toString() ?? '');
    _phone = TextEditingController(text: p['phone_number']?.toString() ?? '');
    _cuisine = TextEditingController(text: p['cuisine']?.toString() ?? '');
    _opening = TextEditingController(text: p['opening_time']?.toString() ?? '');
    _closing = TextEditingController(text: p['closing_time']?.toString() ?? '');
    _fee = TextEditingController(
        text: ((p['delivery_fee'] as num?) ?? 0).toStringAsFixed(0));
    _eta = TextEditingController(text: (p['eta_minutes'] ?? 30).toString());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _phone.dispose();
    _cuisine.dispose();
    _opening.dispose();
    _closing.dispose();
    _fee.dispose();
    _eta.dispose();
    super.dispose();
  }

  Future<void> _pickPlace() async {
    final p = await showPlaceSearch(
      context,
      title: 'Update location',
      allowCurrentLocation: true,
    );
    if (p != null && mounted) setState(() => _newPlace = p);
  }

  Future<void> _uploadCover(File f) async {
    setState(() {
      _pickedCover = f;
      _savingCover = true;
    });
    final err = await context.read<RestaurantProvider>().uploadCover(f);
    if (!mounted) return;
    setState(() => _savingCover = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(err),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Cover image updated'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final fee = double.tryParse(_fee.text.trim());
    if (fee == null || fee < 0) {
      setState(() => _error = 'Delivery fee must be a positive number');
      return;
    }
    final eta = int.tryParse(_eta.text.trim());
    if (eta == null || eta < 5) {
      setState(() => _error = 'ETA must be at least 5 minutes');
      return;
    }

    setState(() => _busy = true);
    final err = await context.read<RestaurantProvider>().updateProfile(
          name: _name.text.trim(),
          description: _description.text.trim(),
          phoneNumber: _phone.text.trim(),
          cuisine: _cuisine.text.trim(),
          openingTime: _opening.text.trim(),
          closingTime: _closing.text.trim(),
          deliveryFee: fee,
          etaMinutes: eta,
          address: _newPlace?.fullAddress,
          lat: _newPlace?.location.latitude,
          lng: _newPlace?.location.longitude,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Saved'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<RestaurantProvider>();
    final profile = r.profile ?? const <String, dynamic>{};
    final address = _newPlace?.fullAddress ?? profile['address']?.toString();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Edit restaurant',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: staggered([
          const _Label(text: 'COVER PHOTO'),
          ImagePickerTile(
            existingUrl: profile['image_url']?.toString(),
            pickedFile: _pickedCover,
            busy: _savingCover,
            emptyHint: 'Tap to set a cover photo',
            onPicked: _uploadCover,
          ),
          const SizedBox(height: 18),
          _field(label: 'NAME', controller: _name, icon: Icons.restaurant_rounded),
          _field(
              label: 'CUISINE',
              controller: _cuisine,
              icon: Icons.local_dining_rounded),
          _field(
              label: 'CONTACT NUMBER',
              controller: _phone,
              icon: Icons.phone_iphone_rounded,
              keyboardType: TextInputType.phone),
          _field(
              label: 'SHORT DESCRIPTION',
              controller: _description,
              icon: Icons.notes_rounded,
              maxLines: 2),
          const _Label(text: 'LOCATION'),
          GestureDetector(
            onTap: _pickPlace,
            child: Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: _newPlace != null
                    ? AppColors.primary.withOpacity(0.06)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppStyles.shadowSm,
                border: _newPlace != null
                    ? Border.all(color: AppColors.primary, width: 1.4)
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.map_rounded,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          address ?? 'Tap to pick a new location',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _newPlace != null
                              ? 'New address (will be saved)'
                              : 'Tap to change',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.textTertiary),
                ],
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _field(
                    label: 'OPENS AT',
                    controller: _opening,
                    icon: Icons.wb_sunny_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                    label: 'CLOSES AT',
                    controller: _closing,
                    icon: Icons.nightlight_round),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _field(
                    label: 'DELIVERY FEE (Rs.)',
                    controller: _fee,
                    icon: Icons.delivery_dining_rounded,
                    keyboardType: TextInputType.number),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                    label: 'PREP + DELIVERY (min)',
                    controller: _eta,
                    icon: Icons.timer_rounded,
                    keyboardType: TextInputType.number),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.error,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ]),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: PrimaryButton(
            label: 'SAVE CHANGES',
            icon: Icons.check_rounded,
            gold: true,
            busy: _busy,
            onPressed: _save,
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppStyles.shadowSm,
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.textSecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: keyboardType,
                    maxLines: maxLines,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    decoration: const InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
        ),
      ),
    );
  }
}
