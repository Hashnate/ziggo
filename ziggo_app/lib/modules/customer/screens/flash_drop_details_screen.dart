import 'package:flutter/material.dart';
import '../../../app/app_colors.dart';
import '../../../core/map/places.dart';
import 'choose_location_screen.dart';

class FlashDropDetailsScreen extends StatefulWidget {
  final Place? initialDrop;

  const FlashDropDetailsScreen({super.key, this.initialDrop});

  @override
  State<FlashDropDetailsScreen> createState() => _FlashDropDetailsScreenState();
}

class _FlashDropDetailsScreenState extends State<FlashDropDetailsScreen> {
  Place? _drop;
  bool _proofOfDelivery = false;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _drop = widget.initialDrop;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectLocation() async {
    final Place? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChooseLocationScreen()),
    );
    if (result != null) {
      setState(() {
        _drop = result;
      });
    }
  }

  void _done() {
    if (_drop == null) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, {
      'place': _drop,
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'notes': _notesController.text.trim(),
      'proofOfDelivery': _proofOfDelivery,
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isReady = _drop != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: _done,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  const SizedBox(height: 20),
                  // Illustration
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 200,
                          height: 80,
                          decoration: BoxDecoration(
                            color: const Color(0xFFBFDBFE), // Ziggo light blue blob
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                        Column(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.arrow_downward_rounded, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            const Icon(Icons.inventory_2_rounded, size: 60, color: AppColors.primary),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  const Center(
                    child: Text(
                      'Drop 1 details',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Location & Contact
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        _buildRow(
                          icon: Icons.location_on_outlined,
                          title: 'Set location',
                          subtitle: _drop?.fullAddress ?? 'Location',
                          onTap: _selectLocation,
                        ),
                        const Divider(height: 1),
                        // Receiver Name
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              icon: Icon(Icons.person_outline_rounded, color: AppColors.textPrimary),
                              hintText: 'Receiver name',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w600),
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                        const Divider(height: 1),
                        // Receiver Phone
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              icon: Icon(Icons.phone_outlined, color: AppColors.textPrimary),
                              hintText: 'Receiver phone',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w600),
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Notes & Proof of delivery
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.black.withOpacity(0.1)),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: TextField(
                            controller: _notesController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              icon: Icon(Icons.note_outlined, color: AppColors.textPrimary),
                              hintText: 'Notes / instructions',
                              border: InputBorder.none,
                              hintStyle: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w600),
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Proof of delivery',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: Checkbox(
                                  value: _proofOfDelivery,
                                  onChanged: (val) {
                                    setState(() {
                                      _proofOfDelivery = val ?? false;
                                    });
                                  },
                                  activeColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_rounded, color: AppColors.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              height: 1.4,
                            ),
                            children: [
                              TextSpan(
                                text: 'Note: ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text: "If your payment method is cash, you'll be charged at the Pick up point ",
                              ),
                              TextSpan(
                                text: 'View terms & conditions',
                                style: TextStyle(color: AppColors.primary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Done Button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _done,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isReady ? AppColors.primary : AppColors.primarySoft,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow({
    IconData? icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: AppColors.textPrimary, size: 24),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
