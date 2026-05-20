import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/widgets/motion.dart';
import '../../restaurant/widgets/image_picker_tile.dart';
import '../market_vendor_provider.dart';

/// Self-registration form for the market stall — mirrors
/// RestaurantRegistrationScreen. After submit the vendor sits in
/// `is_active=False` (pending admin approval) and the parent screen flips
/// over to the dashboard once `onRegistered` callback runs.
class MarketVendorRegistrationScreen extends StatefulWidget {
  final VoidCallback onRegistered;
  final VoidCallback? onCancel;
  const MarketVendorRegistrationScreen({
    super.key,
    required this.onRegistered,
    this.onCancel,
  });

  @override
  State<MarketVendorRegistrationScreen> createState() =>
      _MarketVendorRegistrationScreenState();
}

class _MarketVendorRegistrationScreenState
    extends State<MarketVendorRegistrationScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _phone = TextEditingController();
  final _category = TextEditingController();
  final _opening = TextEditingController(text: '08:00');
  final _closing = TextEditingController(text: '22:00');
  final _fee = TextEditingController(text: '250');
  final _eta = TextEditingController(text: '40');

  Place? _place;
  File? _coverFile;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _phone.dispose();
    _category.dispose();
    _opening.dispose();
    _closing.dispose();
    _fee.dispose();
    _eta.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final p = await showPlaceSearch(
      context,
      title: 'Pick your stall',
      allowCurrentLocation: true,
    );
    if (p != null && mounted) setState(() => _place = p);
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Enter a valid stall name');
      return;
    }
    if (_place == null) {
      setState(() => _error = 'Pick your stall location on the map');
      return;
    }
    final fee = double.tryParse(_fee.text.trim());
    if (fee == null || fee < 0) {
      setState(() => _error = 'Delivery fee must be a number');
      return;
    }
    final eta = int.tryParse(_eta.text.trim());
    if (eta == null || eta < 5) {
      setState(() => _error = 'ETA must be at least 5 minutes');
      return;
    }

    setState(() => _busy = true);
    final r = context.read<MarketVendorProvider>();
    final err = await r.register(
      name: _name.text.trim(),
      description: _description.text.trim(),
      category: _category.text.trim(),
      address: _place!.fullAddress,
      lat: _place!.location.latitude,
      lng: _place!.location.longitude,
      phoneNumber: _phone.text.trim(),
      openingTime: _opening.text.trim(),
      closingTime: _closing.text.trim(),
      deliveryFee: fee,
      etaMinutes: eta,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    if (_coverFile != null) {
      await r.uploadCover(_coverFile!);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onRegistered();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: widget.onCancel == null
          ? null
          : AppBar(
              backgroundColor: AppColors.background,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: widget.onCancel,
              ),
              title: const Text(
                'Register your market stall',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  fontSize: 16,
                ),
              ),
            ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
          children: staggered([
            if (widget.onCancel == null)
              const Text(
                'Register your\nmarket stall',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                  letterSpacing: -0.6,
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'A few details before customers can find you on Ziggo Mart. Admin will review and approve.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel(label: 'COVER PHOTO'),
            ImagePickerTile(
              pickedFile: _coverFile,
              emptyHint: 'Add a cover photo (optional)',
              height: 150,
              onPicked: (f) => setState(() => _coverFile = f),
            ),
            const SizedBox(height: 14),
            _field(
              label: 'STALL NAME',
              controller: _name,
              hint: 'e.g. Galle Face Mart',
              icon: Icons.storefront_rounded,
            ),
            _field(
              label: 'CATEGORY',
              controller: _category,
              hint: 'Grocery, Pharmacy, Bakery, ...',
              icon: Icons.label_rounded,
            ),
            _field(
              label: 'CONTACT NUMBER',
              controller: _phone,
              hint: 'Customers/admin can reach you here',
              icon: Icons.phone_iphone_rounded,
              keyboardType: TextInputType.phone,
            ),
            _field(
              label: 'SHORT DESCRIPTION',
              controller: _description,
              hint: 'Tell customers what you sell',
              icon: Icons.notes_rounded,
              maxLines: 2,
            ),
            const _SectionLabel(label: 'LOCATION'),
            _LocationPicker(place: _place, onTap: _pickLocation),
            Row(
              children: [
                Expanded(
                  child: _field(
                    label: 'OPENS AT',
                    controller: _opening,
                    hint: '08:00',
                    icon: Icons.wb_sunny_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    label: 'CLOSES AT',
                    controller: _closing,
                    hint: '22:00',
                    icon: Icons.nightlight_round,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _field(
                    label: 'DELIVERY FEE (Rs.)',
                    controller: _fee,
                    hint: '250',
                    icon: Icons.delivery_dining_rounded,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    label: 'ETA (min)',
                    controller: _eta,
                    hint: '40',
                    icon: Icons.timer_rounded,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
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
            const SizedBox(height: 24),
            PrimaryButton(
              label: 'SUBMIT FOR APPROVAL',
              icon: Icons.arrow_forward_rounded,
              gold: true,
              busy: _busy,
              onPressed: _submit,
            ),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'An admin will review and approve your stall.\nOrders only start flowing once approved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
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
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textTertiary,
                      ),
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(
        label,
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

class _LocationPicker extends StatelessWidget {
  final Place? place;
  final VoidCallback onTap;
  const _LocationPicker({required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final picked = place != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: picked ? AppColors.success.withOpacity(0.06) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: picked ? AppColors.success : AppColors.cardBorder,
              width: picked ? 1.4 : 1,
            ),
            boxShadow: AppStyles.shadowSm,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.map_rounded,
                    color: AppColors.success, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      picked ? place!.name : 'Tap to pick on the map',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      picked
                          ? place!.area
                          : 'Customers see this address on the listing',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
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
    );
  }
}
