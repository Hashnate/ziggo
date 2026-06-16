import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/places.dart';
import '../../../core/widgets/motion.dart';
import '../addresses_provider.dart';

class SavedAddressesScreen extends StatefulWidget {
  final bool selectMode;
  const SavedAddressesScreen({super.key, this.selectMode = false});

  @override
  State<SavedAddressesScreen> createState() => _SavedAddressesScreenState();
}

class _SavedAddressesScreenState extends State<SavedAddressesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AddressesProvider>().refresh();
    });
  }

  ({IconData icon, Color color}) _labelStyle(String label) {
    final l = label.toLowerCase();
    if (l.contains('home')) return (icon: Icons.home_rounded, color: AppColors.primary);
    if (l.contains('work') || l.contains('office')) {
      return (icon: Icons.work_rounded, color: AppColors.flash);
    }
    if (l.contains('gym')) return (icon: Icons.fitness_center_rounded, color: AppColors.bike);
    return (icon: Icons.place_rounded, color: AppColors.market);
  }

  Future<void> _addDialog() async {
    final labelCtrl = TextEditingController();
    Place? picked;
    bool makeDefault = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (_, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Add a place',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, letterSpacing: -0.3),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Save your favorite spots for faster booking',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    for (final preset in const ['Home', 'Work', 'Gym'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: GestureDetector(
                          onTap: () => labelCtrl.text = preset,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              preset,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: labelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Label',
                    prefixIcon: Icon(Icons.label_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () async {
                    final p = await showPlaceSearch(sheetCtx,
                        title: 'Search address');
                    if (p != null) setSheetState(() => picked = p);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: const Icon(Icons.location_on_rounded,
                              color: AppColors.error, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            picked?.fullAddress ?? 'Tap to pick a location',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: picked == null
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: makeDefault,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setSheetState(() => makeDefault = v),
                  title: const Text(
                    'Set as default',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 8),
                PrimaryButton(
                  label: 'SAVE PLACE',
                  icon: Icons.check_rounded,
                  onPressed: (labelCtrl.text.trim().isEmpty || picked == null)
                      ? null
                      : () async {
                          final ok = await context.read<AddressesProvider>().add(
                                label: labelCtrl.text.trim(),
                                address: picked!.fullAddress,
                                lat: picked!.location.latitude,
                                lng: picked!.location.longitude,
                                isDefault: makeDefault,
                              );
                          if (!sheetCtx.mounted) return;
                          Navigator.pop(sheetCtx);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ok ? 'Place saved' : 'Failed to save'),
                              backgroundColor: ok ? AppColors.success : AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<AddressesProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Saved Places'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDialog,
        backgroundColor: Colors.black,
        foregroundColor: AppColors.primary,
        icon: const Icon(Icons.add_rounded),
        label: const Text('ADD PLACE', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: RefreshIndicator(
        onRefresh: () => p.refresh(),
        child: p.items.isEmpty
            ? _empty()
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: p.items.length,
                itemBuilder: (_, i) {
                  final a = p.items[i];
                  final style = _labelStyle(a['label']?.toString() ?? '');
                  return EntranceSlide(
                    delay: Duration(milliseconds: 45 * i),
                    child: GestureDetector(
                      onTap: widget.selectMode
                          ? () {
                              final lat = (a['lat'] as num).toDouble();
                              final lng = (a['lng'] as num).toDouble();
                              final address = a['address'].toString();
                              Navigator.pop(
                                context,
                                Place(
                                  a['label']?.toString() ?? 'Saved Place',
                                  address,
                                  LatLng(lat, lng),
                                ),
                              );
                            }
                          : null,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: AppColors.serviceGradient(style.color),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(style.icon, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        a['label']?.toString() ?? '',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 15,
                                        ),
                                      ),
                                      if (a['is_default'] == true) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'DEFAULT',
                                            style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.6,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    a['address']?.toString() ?? '',
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
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AppColors.error),
                              onPressed: () => p.remove(a['id'] as int),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 140),
        Center(
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
                child: const Icon(Icons.bookmark_border_rounded,
                    size: 44, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 18),
              const Text('No saved places yet',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              const Text("Tap '+ ADD PLACE' to save your favorites",
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
