import 'package:flutter/material.dart';
import '../../../app/app_colors.dart';
import '../../../core/map/places.dart';
import 'choose_location_screen.dart';

class CourierLocationDetailsScreen extends StatefulWidget {
  final bool isPickup;
  final Place? initialLocation;
  final String? initialName;
  final String? initialPhone;

  const CourierLocationDetailsScreen({
    super.key,
    required this.isPickup,
    this.initialLocation,
    this.initialName,
    this.initialPhone,
  });

  @override
  State<CourierLocationDetailsScreen> createState() => _CourierLocationDetailsScreenState();
}

class _CourierLocationDetailsScreenState extends State<CourierLocationDetailsScreen> {
  Place? _location;
  String _name = '';
  String _phone = '';

  @override
  void initState() {
    super.initState();
    _location = widget.initialLocation;
    _name = widget.initialName ?? '';
    _phone = widget.initialPhone ?? '';
  }

  Future<void> _selectLocation() async {
    final Place? result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChooseLocationScreen()),
    );
    if (result != null) {
      setState(() {
        _location = result;
      });
    }
  }

  void _showContactSheet() {
    final nameController = TextEditingController(text: _name);
    final phoneController = TextEditingController(text: _phone);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Contact Details',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: widget.isPickup ? 'Sender Name' : 'Receiver Name',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: widget.isPickup ? 'Sender Phone' : 'Receiver Phone',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _name = nameController.text.trim();
                      _phone = phoneController.text.trim();
                    });
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  void _done() {
    Navigator.pop(context, {
      'place': _location,
      'name': _name,
      'phone': _phone,
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isPickup ? 'Pick up details' : 'Drop details';
    final isReady = _location != null && _name.isNotEmpty && _phone.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
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
                            color: const Color(0xFFFDE68A), // Ziggo light yellow blob for illustration
                            borderRadius: BorderRadius.circular(40),
                          ),
                        ),
                        Column(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.isPickup ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Icon(Icons.inventory_2_rounded, size: 60, color: Color(0xFF8B5A2B)), // Brown box
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  Center(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Location, City, Contact
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
                          subtitle: _location?.fullAddress ?? 'Location',
                          onTap: _selectLocation,
                        ),
                        const Divider(height: 1),
                        _buildRow(
                          icon: Icons.location_city_rounded,
                          title: 'City',
                          subtitle: _location?.area.isNotEmpty == true ? _location!.area : 'City',
                          onTap: () {}, // Auto-populated
                        ),
                        const Divider(height: 1),
                        _buildRow(
                          icon: Icons.person_outline_rounded,
                          title: 'Set Contact',
                          subtitle: _name.isNotEmpty ? '$_name • $_phone' : null,
                          onTap: _showContactSheet,
                        ),
                      ],
                    ),
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
                  onPressed: isReady ? _done : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCFD5DF), // Based on screenshot disabled color
                    disabledBackgroundColor: const Color(0xFFCFD5DF),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 0,
                  ).copyWith(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.disabled)) {
                        return const Color(0xFFCFD5DF);
                      }
                      return AppColors.primary;
                    }),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: AppColors.textPrimary, // the screenshot text color is dark grey
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
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textPrimary, size: 24),
            const SizedBox(width: 16),
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
