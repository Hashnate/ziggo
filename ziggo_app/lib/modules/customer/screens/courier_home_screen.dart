import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/map/places.dart';
import 'choose_location_screen.dart';
import 'flash_drop_details_screen.dart';
import 'flash_checkout_screen.dart';

/// PickMe-style Courier step 1: pick up + drop locations only. Item type,
/// weight, payment and receiver-pays are collected on the later steps
/// (drop details + checkout), so this screen stays clean — matching the
/// reference design (3-step progress bar, two location rows, package note).
class CourierHomeScreen extends StatefulWidget {
  const CourierHomeScreen({super.key});

  @override
  State<CourierHomeScreen> createState() => _CourierHomeScreenState();
}

class _CourierHomeScreenState extends State<CourierHomeScreen> {
  Place? _pickup;
  Place? _drop;
  String _receiverName = '';
  String _receiverPhone = '';
  String _notes = '';

  Future<void> _selectPickup() async {
    final Place? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChooseLocationScreen()),
    );
    if (result != null) setState(() => _pickup = result);
  }

  Future<void> _selectDrop() async {
    final dynamic result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FlashDropDetailsScreen(initialDrop: _drop)),
    );
    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _drop = result['place'];
        _receiverName = result['name'] ?? '';
        _receiverPhone = result['phone'] ?? '';
        _notes = result['notes'] ?? '';
      });
    }
  }

  void _onNext() {
    if (_pickup == null || _drop == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FlashCheckoutScreen(
          pickup: _pickup!,
          drop: _drop!,
          itemType: 'Parcel',
          whoPays: 'Sender',
          receiverName: _receiverName,
          receiverPhone: _receiverPhone,
          notes: _notes,
          isCourier: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _pickup != null && _drop != null;

    return Scaffold(
      backgroundColor: const Color(0xFFEDEDED),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Courier',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 3-step progress bar (step 1 active)
          const _StepProgress(activeStep: 0, totalSteps: 3),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                const Text(
                  'Where to pick up and drop\nyour parcel?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 20),

                // Pickup + Drop card
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      _locationRow(
                        isPickup: true,
                        title: 'Pick up:',
                        location: _pickup,
                        accent: AppColors.primary,
                        onTap: _selectPickup,
                      ),
                      const SizedBox(height: 6),
                      _locationRow(
                        isPickup: false,
                        title: 'Drop:',
                        location: _drop,
                        accent: AppColors.warning,
                        onTap: _selectDrop,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Package-box note
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7E7E7),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.edit_note_rounded, color: AppColors.textPrimary, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Note: Make sure to write the drop address and contact details on the package box',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Next button
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isReady ? _onNext : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: const Color(0xFFD4D4D4),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Next',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationRow({
    required bool isPickup,
    required String title,
    required Place? location,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final hasLocation = location != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasLocation ? Colors.transparent : accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(
                isPickup ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (hasLocation) ...[
                    const SizedBox(height: 4),
                    Text(
                      location.name.isNotEmpty ? location.name : location.fullAddress,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (!hasLocation)
              Text(
                'Set location',
                style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: accent),
          ],
        ),
      ),
    );
  }
}

class _StepProgress extends StatelessWidget {
  final int activeStep;
  final int totalSteps;
  const _StepProgress({required this.activeStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(bottom: 0),
      child: Row(
        children: List.generate(totalSteps, (i) {
          final done = i <= activeStep;
          return Expanded(
            child: Container(
              height: 5,
              margin: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 3),
              decoration: BoxDecoration(
                color: done ? AppColors.warning : const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }
}
