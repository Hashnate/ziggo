import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../../restaurant/widgets/image_picker_tile.dart';
import '../market_vendor_provider.dart';

class MarketVendorProductsScreen extends StatefulWidget {
  const MarketVendorProductsScreen({super.key});

  @override
  State<MarketVendorProductsScreen> createState() =>
      _MarketVendorProductsScreenState();
}

class _MarketVendorProductsScreenState
    extends State<MarketVendorProductsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MarketVendorProvider>().loadProducts();
    });
  }

  Future<void> _addProduct() async {
    final result = await _showProductDialog();
    if (result == null || !mounted) return;
    final p = context.read<MarketVendorProvider>();
    final err = await p.createProduct(
      name: result['name'] as String,
      price: result['price'] as double,
      stockQuantity: result['stock_quantity'] as int? ?? 0,
      description: result['description'] as String?,
      unit: result['unit'] as String?,
      isAvailable: result['is_available'] as bool? ?? true,
      category: result['category'] as String?,
      originalPrice: result['original_price'] as double?,
      isPopular: result['is_popular'] as bool? ?? false,
      weightKg: result['weight_kg'] as double?,
    );
    if (!mounted) return;
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    final pickedFile = result['picked_file'] as File?;
    if (pickedFile != null) {
      final created = p.products.firstWhere(
        (x) => x['name'] == result['name'],
        orElse: () => const {},
      );
      final id = created['id'] as int?;
      if (id != null) {
        final uerr = await p.uploadProductImage(id, pickedFile);
        if (uerr != null && mounted) _toast(uerr, error: true);
      }
    }
  }

  Future<void> _editProduct(Map<String, dynamic> it) async {
    final result = await _showProductDialog(initial: it);
    if (result == null || !mounted) return;
    final p = context.read<MarketVendorProvider>();
    final err = await p.updateProduct(
      it['id'] as int,
      name: result['name'] as String?,
      price: result['price'] as double?,
      stockQuantity: result['stock_quantity'] as int?,
      description: result['description'] as String?,
      unit: result['unit'] as String?,
      isAvailable: result['is_available'] as bool?,
      category: result['category'] as String?,
      originalPrice: result['original_price'] as double?,
      isPopular: result['is_popular'] as bool?,
      weightKg: result['weight_kg'] as double?,
    );
    if (!mounted) return;
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    final pickedFile = result['picked_file'] as File?;
    if (pickedFile != null) {
      final uerr = await p.uploadProductImage(it['id'] as int, pickedFile);
      if (uerr != null && mounted) _toast(uerr, error: true);
    }
  }

  Future<void> _deleteProduct(Map<String, dynamic> it) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${it['name']}"?'),
        content: const Text(
          'Customers will no longer see this product. Existing orders are unaffected.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final err = await context
        .read<MarketVendorProvider>()
        .deleteProduct(it['id'] as int);
    if (!mounted) return;
    if (err != null) _toast(err, error: true);
  }

  Future<Map<String, dynamic>?> _showProductDialog({
    Map<String, dynamic>? initial,
  }) async {
    final name = TextEditingController(text: initial?['name']?.toString() ?? '');
    final desc =
        TextEditingController(text: initial?['description']?.toString() ?? '');
    final price = TextEditingController(
        text: initial == null
            ? ''
            : ((initial['price'] as num?) ?? 0).toStringAsFixed(0));
    final originalPrice = TextEditingController(
        text: initial?['original_price'] != null
            ? ((initial?['original_price'] as num?) ?? 0).toStringAsFixed(0)
            : '');
    final category = TextEditingController(text: initial?['category']?.toString() ?? '');
    final stock = TextEditingController(
        text: (initial?['stock_quantity'] ?? 0).toString());
    final unit =
        TextEditingController(text: initial?['unit']?.toString() ?? '');
    final weight = TextEditingController(
        text: initial?['weight_kg'] != null
            ? (initial!['weight_kg'] as num).toString()
            : '');
    bool isAvailable = initial?['is_available'] != false;
    bool isPopular = initial?['is_popular'] == true;
    File? pickedFile;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(initial == null ? 'New product' : 'Edit product'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ImagePickerTile(
                    existingUrl: initial?['image_url']?.toString(),
                    pickedFile: pickedFile,
                    emptyHint: 'Add a photo for this product',
                    height: 130,
                    onPicked: (f) => setLocal(() => pickedFile = f),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Product name',
                      hintText: 'e.g. Anchor Milk Powder',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: category,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      hintText: 'e.g. Fresh Produce, Skin Care',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Price (Rs.)',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: originalPrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Original Price (Rs.)',
                            hintText: 'For discounts',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: stock,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Stock on hand',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: unit,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            hintText: '400g, 1L, pack',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: weight,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Weight (kg)',
                      hintText: 'Used to calculate delivery fee — e.g. 1.5',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: desc,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Available for ordering'),
                    value: isAvailable,
                    onChanged: (v) => setLocal(() => isAvailable = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Mark as Popular Pick'),
                    value: isPopular,
                    onChanged: (v) => setLocal(() => isPopular = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  if (name.text.trim().isEmpty) return;
                  final p = double.tryParse(price.text.trim());
                  if (p == null || p < 0) return;
                  Navigator.pop(ctx, {
                    'name': name.text.trim(),
                    'price': p,
                    'original_price': double.tryParse(originalPrice.text.trim()),
                    'category': category.text.trim(),
                    'stock_quantity':
                        int.tryParse(stock.text.trim()) ?? 0,
                    'unit': unit.text.trim(),
                    'weight_kg': double.tryParse(weight.text.trim()),
                    'description': desc.text.trim(),
                    'is_available': isAvailable,
                    'is_popular': isPopular,
                    'picked_file': pickedFile,
                  });
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<MarketVendorProvider>();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Products',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _addProduct,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add product',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: r.loadingProducts && r.products.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => r.loadProducts(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  if (r.products.isEmpty)
                    _empty()
                  else
                    ...staggered([
                      for (final it in r.products)
                        _ProductRow(
                          item: it,
                          onTap: () => _editProduct(it),
                          onToggleAvailability: (v) async {
                            final err = await context
                                .read<MarketVendorProvider>()
                                .toggleProductAvailability(it['id'] as int, v);
                            if (!context.mounted) return;
                            if (err != null) _toast(err, error: true);
                          },
                          onDelete: () => _deleteProduct(it),
                        ),
                    ]),
                ],
              ),
            ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
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
            child: const Icon(Icons.inventory_2_rounded,
                size: 44, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 18),
          const Text(
            'No products yet',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Tap "Add product" to start listing items. Customers see only available items with stock left.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _addProduct,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add first product',
                style: TextStyle(fontWeight: FontWeight.w900)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleAvailability;
  final VoidCallback onDelete;

  const _ProductRow({
    required this.item,
    required this.onTap,
    required this.onToggleAvailability,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final available = item['is_available'] != false;
    final stock = (item['stock_quantity'] as num? ?? 0).toInt();
    final unit = item['unit']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Thumb(url: item['image_url']?.toString()),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['name']?.toString() ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: available
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                        decoration: available
                            ? TextDecoration.none
                            : TextDecoration.lineThrough,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (unit.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          unit,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Rs.${(item['price'] as num? ?? 0).toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: AppColors.success,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: stock <= 0
                                ? AppColors.error.withOpacity(0.12)
                                : AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            stock <= 0 ? 'OUT OF STOCK' : 'Stock: $stock',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              letterSpacing: 0.6,
                              color: stock <= 0
                                  ? AppColors.error
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Switch.adaptive(
                    value: available,
                    onChanged: onToggleAvailability,
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded,
                        color: AppColors.textTertiary, size: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    onSelected: (v) {
                      if (v == 'edit') onTap();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  final String? url;
  const _Thumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final resolved = resolveImageUrl(url);
    return Container(
      width: 60,
      height: 60,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: resolved == null
          ? const Icon(Icons.inventory_2_rounded,
              color: AppColors.textTertiary, size: 22)
          : Image.network(
              resolved,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_rounded,
                color: AppColors.textTertiary,
                size: 22,
              ),
            ),
    );
  }
}
