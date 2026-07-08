import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../restaurant/widgets/image_picker_tile.dart';
import '../market_vendor_provider.dart';

class MarketVendorAdsScreen extends StatefulWidget {
  const MarketVendorAdsScreen({super.key});

  @override
  State<MarketVendorAdsScreen> createState() => _MarketVendorAdsScreenState();
}

class _MarketVendorAdsScreenState extends State<MarketVendorAdsScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MarketVendorProvider>().fetchMyAds();
    });
  }

  Future<void> _uploadAd() async {
    File? pickedFile;
    final radiusCtrl = TextEditingController(text: '5.0');

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppStyles.radiusLg)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'New Advertisement',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                ImagePickerTile(
                  pickedFile: pickedFile,
                  emptyHint: 'Select ad banner image',
                  height: 150,
                  onPicked: (f) => setLocal(() => pickedFile = f),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: radiusCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Target Radius (km)',
                    hintText: 'e.g. 5.0',
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.grey[700],
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                          ),
                          side: BorderSide(color: Colors.grey[300]!),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppStyles.radiusSm),
                          ),
                        ),
                        onPressed: () {
                          if (pickedFile == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Please select an image'), backgroundColor: AppColors.error),
                            );
                            return;
                          }
                          final radius = double.tryParse(radiusCtrl.text) ?? 5.0;
                          Navigator.pop(ctx, {'file': pickedFile, 'radius': radius});
                        },
                        child: const Text(
                          'Upload',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _busy = true);
    final err = await context.read<MarketVendorProvider>().uploadAd(
          result['file'] as File,
          result['radius'] as double,
        );
    setState(() => _busy = false);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad uploaded successfully!'), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _deleteAd(int adId) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Advertisement?'),
        content: const Text('This will immediately stop showing the ad to customers.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    final err = await context.read<MarketVendorProvider>().deleteAd(adId);
    setState(() => _busy = false);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<MarketVendorProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('My Advertisements', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _uploadAd,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Upload Ad', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => r.fetchMyAds(),
              child: r.ads.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(30),
                            ),
                            child: const Icon(Icons.ad_units_rounded, size: 48, color: AppColors.textTertiary),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Ads Uploaded Yet',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Promote your shop to nearby customers.\nUpload banner ads with specific targeting radius.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                        ),
                      ],
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 0.9,
                      ),
                      itemCount: r.ads.length,
                      itemBuilder: (ctx, i) {
                        final ad = r.ads[i];
                        final url = resolveImageUrl(ad['image_url']?.toString());
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppStyles.shadowSm,
                            border: Border.all(color: AppColors.cardBorder),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (url != null)
                                      Image.network(url, fit: BoxFit.cover)
                                    else
                                      Container(color: AppColors.surfaceMuted),
                                    Positioned(
                                      right: 8,
                                      top: 8,
                                      child: GestureDetector(
                                        onTap: () => _deleteAd(ad['id'] as int),
                                        child: Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 18),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.gps_fixed_rounded, size: 14, color: AppColors.primary),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Radius: ${ad['radius_km']} km',
                                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Active: ${ad['is_active'] ? "Yes" : "No"}',
                                      style: TextStyle(
                                        color: ad['is_active'] ? AppColors.success : AppColors.textTertiary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
