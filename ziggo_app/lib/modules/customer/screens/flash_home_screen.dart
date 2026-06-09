import 'package:flutter/material.dart';
import '../../../app/app_colors.dart';
import '../../../core/map/places.dart';
import 'choose_location_screen.dart';
import 'flash_drop_details_screen.dart';
import 'flash_checkout_screen.dart';

class FlashHomeScreen extends StatefulWidget {
  final bool isSend;
  final bool isCourier;

  const FlashHomeScreen({super.key, this.isSend = true, this.isCourier = false});

  @override
  State<FlashHomeScreen> createState() => _FlashHomeScreenState();
}

class _FlashHomeScreenState extends State<FlashHomeScreen> {
  Place? _pickup;
  Place? _drop;
  String _itemType = 'Select an item type';
  String _whoPays = 'Enter drop details to select a payer.';
  
  // Data from drop details
  String _receiverName = '';
  String _receiverPhone = '';
  String _notes = '';

  Future<void> _selectPickup() async {
    final Place? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChooseLocationScreen()),
    );
    if (result != null) {
      setState(() {
        _pickup = result;
      });
    }
  }

  Future<void> _selectDrop() async {
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FlashDropDetailsScreen(initialDrop: _drop),
      ),
    );
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _drop = result['place'];
        _receiverName = result['name'] ?? '';
        _receiverPhone = result['phone'] ?? '';
        _notes = result['notes'] ?? '';
        if (_whoPays == 'Enter drop details to select a payer.') {
           _whoPays = 'Sender'; // Default after selection
        }
      });
    }
  }

  void _showItemTypeSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Select Item Type',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            _buildSheetOption('Document', Icons.description_outlined),
            _buildSheetOption('Food', Icons.restaurant_outlined),
            _buildSheetOption('Clothes', Icons.checkroom_outlined),
            _buildSheetOption('Other', Icons.inventory_2_outlined),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showWhoPaysSheet() {
    if (_drop == null) return; // Prevent selection before drop is set
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Who pays for the flash?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.person_rounded, color: AppColors.primary),
              title: const Text('Sender', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: _whoPays == 'Sender' ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
              onTap: () {
                setState(() => _whoPays = 'Sender');
                Navigator.pop(context);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded, color: AppColors.warning),
              title: const Text('Receiver', style: TextStyle(fontWeight: FontWeight.bold)),
              trailing: _whoPays == 'Receiver' ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
              onTap: () {
                setState(() => _whoPays = 'Receiver');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetOption(String title, IconData icon) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: _itemType == title ? const Icon(Icons.check_circle_rounded, color: AppColors.primary) : null,
      onTap: () {
        setState(() => _itemType = title);
        Navigator.pop(context);
      },
    );
  }

  void _onNext() {
    if (_pickup == null || _drop == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FlashCheckoutScreen(
          pickup: _pickup!,
          drop: _drop!,
          itemType: _itemType,
          whoPays: _whoPays,
          receiverName: _receiverName,
          receiverPhone: _receiverPhone,
          notes: _notes,
          isCourier: widget.isCourier,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.isCourier ? 'Courier' : 'Flash';
    final title = widget.isSend ? service : '$service (Receive)';
    final isReady = _pickup != null && _drop != null && _itemType != 'Select an item type';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text(
                'Where to pick up and drop\nyour parcel?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      children: [
                        _buildTimelineRow(
                          isPickup: true,
                          title: 'Pick up:',
                          location: _pickup,
                          onTap: _selectPickup,
                        ),
                        Row(
                          children: [
                            const SizedBox(width: 31),
                            Column(
                              children: [
                                Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFFD1D5DB), shape: BoxShape.circle)),
                                const SizedBox(height: 4),
                                Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFFD1D5DB), shape: BoxShape.circle)),
                                const SizedBox(height: 4),
                                Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFFD1D5DB), shape: BoxShape.circle)),
                              ],
                            ),
                          ],
                        ),
                        _buildTimelineRow(
                          isPickup: false,
                          title: 'Drop:',
                          location: _drop,
                          onTap: _selectDrop,
                        ),
                      ],
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Maximum of 3 drop points per order',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {},
                          child: const Text(
                            'Add drop',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 8),

                  GestureDetector(
                    onTap: _showItemTypeSheet,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_bag_outlined, color: AppColors.textSecondary),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Item type',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _itemType,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _itemType.startsWith('Select') ? AppColors.error : AppColors.textSecondary,
                                    fontWeight: _itemType.startsWith('Select') ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),

                  GestureDetector(
                    onTap: _showWhoPaysSheet,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              'Who pays for the ${service.toLowerCase()}?',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _whoPays,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isReady ? _onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primarySoft,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: AppColors.textTertiary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Next',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 18,
                        color: isReady ? Colors.white : Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineRow({
    required bool isPickup,
    required String title,
    Place? location,
    required VoidCallback onTap,
  }) {
    final hasLocation = location != null;
    final iconColor = isPickup ? AppColors.primary : AppColors.primaryLight;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (!isPickup && !hasLocation) ? AppColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: iconColor,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPickup ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                color: Colors.white,
                size: 14,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (isPickup && hasLocation) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.edit_rounded, size: 14, color: AppColors.textSecondary),
                      ],
                    ],
                  ),
                  if (hasLocation) ...[
                    const SizedBox(height: 4),
                    Text(
                      location.name.isNotEmpty ? location.name : location.fullAddress,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (location.name.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        location.fullAddress,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ]
                ],
              ),
            ),
            if (!hasLocation && !isPickup) ...[
              const Text(
                'Set location',
                style: TextStyle(
                  color: AppColors.primaryLight,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 4),
            ],
            const Icon(Icons.chevron_right_rounded, color: AppColors.primaryLight),
          ],
        ),
      ),
    );
  }
}
