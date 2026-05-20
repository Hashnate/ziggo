import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../restaurant_provider.dart';
import '../widgets/image_picker_tile.dart';

class RestaurantMenuScreen extends StatefulWidget {
  const RestaurantMenuScreen({super.key});

  @override
  State<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends State<RestaurantMenuScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RestaurantProvider>().loadMenu();
    });
  }

  Future<void> _addCategory() async {
    final result = await _showCategoryDialog();
    if (result == null || !mounted) return;
    final err = await context.read<RestaurantProvider>().createCategory(
          name: result['name']!,
          description: result['description'],
        );
    if (!mounted) return;
    if (err != null) _toast(err, error: true);
  }

  Future<void> _editCategory(Map<String, dynamic> c) async {
    final result = await _showCategoryDialog(initial: c);
    if (result == null || !mounted) return;
    final err = await context.read<RestaurantProvider>().updateCategory(
          c['id'] as int,
          name: result['name'],
          description: result['description'],
        );
    if (!mounted) return;
    if (err != null) _toast(err, error: true);
  }

  Future<void> _deleteCategory(Map<String, dynamic> c) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${c['name']}"?'),
        content: const Text(
          'Items in this category will become uncategorized. You can re-bucket them later.',
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
        .read<RestaurantProvider>()
        .deleteCategory(c['id'] as int);
    if (!mounted) return;
    if (err != null) _toast(err, error: true);
  }

  Future<void> _addItem() async {
    final result = await _showItemDialog();
    if (result == null || !mounted) return;
    final p = context.read<RestaurantProvider>();
    final err = await p.createItem(
      name: result['name'] as String,
      price: result['price'] as double,
      categoryId: result['category_id'] as int?,
      description: result['description'] as String?,
      isVeg: result['is_veg'] as bool,
      isAvailable: result['is_available'] as bool,
      prepTimeMin: result['prep_time_min'] as int?,
    );
    if (!mounted) return;
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    // Upload an image if one was picked. We resolve the new item id by name
    // since the create endpoint doesn't return the row.
    final pickedFile = result['picked_file'] as File?;
    if (pickedFile != null) {
      final created = p.items.firstWhere(
        (x) => x['name'] == result['name'],
        orElse: () => const {},
      );
      final id = created['id'] as int?;
      if (id != null) {
        final uerr = await p.uploadItemImage(id, pickedFile);
        if (uerr != null && mounted) _toast(uerr, error: true);
      }
    }
  }

  Future<void> _editItem(Map<String, dynamic> it) async {
    final result = await _showItemDialog(initial: it);
    if (result == null || !mounted) return;
    final p = context.read<RestaurantProvider>();
    final err = await p.updateItem(
      it['id'] as int,
      name: result['name'] as String?,
      price: result['price'] as double?,
      categoryId: result['category_id'] as int?,
      description: result['description'] as String?,
      isVeg: result['is_veg'] as bool?,
      isAvailable: result['is_available'] as bool?,
      prepTimeMin: result['prep_time_min'] as int?,
    );
    if (!mounted) return;
    if (err != null) {
      _toast(err, error: true);
      return;
    }
    final pickedFile = result['picked_file'] as File?;
    if (pickedFile != null) {
      final uerr = await p.uploadItemImage(it['id'] as int, pickedFile);
      if (uerr != null && mounted) _toast(uerr, error: true);
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> it) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete "${it['name']}"?'),
        content: const Text(
          'Customers will no longer see this item. Existing orders are unaffected.',
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
        .read<RestaurantProvider>()
        .deleteItem(it['id'] as int);
    if (!mounted) return;
    if (err != null) _toast(err, error: true);
  }

  Future<Map<String, String?>?> _showCategoryDialog({
    Map<String, dynamic>? initial,
  }) async {
    final name = TextEditingController(text: initial?['name']?.toString() ?? '');
    final desc =
        TextEditingController(text: initial?['description']?.toString() ?? '');
    return showDialog<Map<String, String?>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(initial == null ? 'New category' : 'Edit category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Rice & Curry',
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
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (name.text.trim().isEmpty) return;
              Navigator.pop(ctx, {
                'name': name.text.trim(),
                'description': desc.text.trim(),
              });
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _showItemDialog({
    Map<String, dynamic>? initial,
  }) async {
    final name = TextEditingController(text: initial?['name']?.toString() ?? '');
    final desc =
        TextEditingController(text: initial?['description']?.toString() ?? '');
    final price = TextEditingController(
        text: initial == null
            ? ''
            : ((initial['price'] as num?) ?? 0).toStringAsFixed(0));
    final prep = TextEditingController(
        text: initial?['prep_time_min']?.toString() ?? '');
    int? categoryId = initial?['category_id'] as int?;
    bool isVeg = initial?['is_veg'] == true;
    bool isAvailable = initial?['is_available'] != false;
    File? pickedFile;

    final cats =
        List<Map<String, dynamic>>.from(context.read<RestaurantProvider>().categories);

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(initial == null ? 'New menu item' : 'Edit menu item'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ImagePickerTile(
                    existingUrl: initial?['image_url']?.toString(),
                    pickedFile: pickedFile,
                    emptyHint: 'Add a photo for this item',
                    height: 130,
                    onPicked: (f) => setLocal(() => pickedFile = f),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Item name',
                      hintText: 'e.g. Chicken Kottu',
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
                          controller: prep,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Prep (min)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: desc,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: categoryId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Uncategorized'),
                      ),
                      for (final c in cats)
                        DropdownMenuItem<int?>(
                          value: c['id'] as int,
                          child: Text(c['name']?.toString() ?? ''),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => categoryId = v),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: const Text('Vegetarian'),
                          value: isVeg,
                          onChanged: (v) => setLocal(() => isVeg = v),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Available for ordering'),
                    value: isAvailable,
                    onChanged: (v) => setLocal(() => isAvailable = v),
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
                    'category_id': categoryId,
                    'description': desc.text.trim(),
                    'is_veg': isVeg,
                    'is_available': isAvailable,
                    'prep_time_min': int.tryParse(prep.text.trim()),
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
    final r = context.watch<RestaurantProvider>();

    final byCat = <int?, List<Map<String, dynamic>>>{};
    for (final it in r.items) {
      final cid = it['category_id'] as int?;
      byCat.putIfAbsent(cid, () => []).add(it);
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Menu',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded),
            tooltip: 'Add category',
            onPressed: _addCategory,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _addItem,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add item',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: r.loadingMenu && r.categories.isEmpty && r.items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => r.loadMenu(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  if (r.categories.isEmpty && r.items.isEmpty)
                    _empty()
                  else ...staggered([
                    for (final c in r.categories) ...[
                      _CategoryHeader(
                        category: c,
                        onEdit: () => _editCategory(c),
                        onDelete: () => _deleteCategory(c),
                      ),
                      ...((byCat[c['id'] as int] ?? []).map(
                        (it) => _ItemRow(
                          item: it,
                          onTap: () => _editItem(it),
                          onToggleAvailability: (v) async {
                            final err = await context
                                .read<RestaurantProvider>()
                                .toggleItemAvailability(it['id'] as int, v);
                            if (!context.mounted) return;
                            if (err != null) _toast(err, error: true);
                          },
                          onDelete: () => _deleteItem(it),
                        ),
                      )),
                      if ((byCat[c['id'] as int] ?? []).isEmpty)
                        const _EmptyCategoryHint(),
                    ],
                    if ((byCat[null] ?? []).isNotEmpty) ...[
                      const _CategoryHeader.uncategorized(),
                      ...((byCat[null] ?? []).map(
                        (it) => _ItemRow(
                          item: it,
                          onTap: () => _editItem(it),
                          onToggleAvailability: (v) async {
                            final err = await context
                                .read<RestaurantProvider>()
                                .toggleItemAvailability(it['id'] as int, v);
                            if (!context.mounted) return;
                            if (err != null) _toast(err, error: true);
                          },
                          onDelete: () => _deleteItem(it),
                        ),
                      )),
                    ],
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
            child: const Icon(Icons.menu_book_rounded,
                size: 44, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 18),
          const Text(
            'No menu yet',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Add a category first (e.g. "Mains"), then add items under it. Customers see only available items.',
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
            onPressed: _addCategory,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Add first category',
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

class _CategoryHeader extends StatelessWidget {
  final Map<String, dynamic>? category;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _CategoryHeader({
    required Map<String, dynamic> this.category,
    required this.onEdit,
    required this.onDelete,
  });

  const _CategoryHeader.uncategorized()
      : category = null,
        onEdit = null,
        onDelete = null;

  @override
  Widget build(BuildContext context) {
    final name = category?['name']?.toString() ?? 'Uncategorized';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (category != null)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded,
                  color: AppColors.textSecondary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              onSelected: (v) {
                if (v == 'edit') onEdit?.call();
                if (v == 'delete') onDelete?.call();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Rename')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyCategoryHint extends StatelessWidget {
  const _EmptyCategoryHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded,
              color: AppColors.textTertiary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No items in this category yet. Tap "Add item" below.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemThumb extends StatelessWidget {
  final String? url;
  const _ItemThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    final resolved = resolveImageUrl(url);
    return Container(
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: resolved == null
          ? const Icon(Icons.restaurant_menu_rounded,
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

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleAvailability;
  final VoidCallback onDelete;

  const _ItemRow({
    required this.item,
    required this.onTap,
    required this.onToggleAvailability,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final available = item['is_available'] != false;
    final isVeg = item['is_veg'] == true;
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
              _ItemThumb(url: item['image_url']?.toString()),
              const SizedBox(width: 12),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isVeg ? AppColors.success : AppColors.error,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Center(
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isVeg ? AppColors.success : AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
                    if ((item['description']?.toString() ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item['description'].toString(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Rs.${(item['price'] as num? ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: AppColors.primary,
                      ),
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
