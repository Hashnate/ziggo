import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../driver_provider.dart';

class DriverVehiclesScreen extends StatefulWidget {
  const DriverVehiclesScreen({super.key});

  @override
  State<DriverVehiclesScreen> createState() => _DriverVehiclesScreenState();
}

class _DriverVehiclesScreenState extends State<DriverVehiclesScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadVehicles();
  }

  Future<void> _loadVehicles() async {
    setState(() => _loading = true);
    await context.read<DriverProvider>().loadVehicles();
    if (mounted) setState(() => _loading = false);
  }

  void _showAddVehicleModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => const _AddVehicleSheet(),
    ).then((added) {
      if (added == true) {
        _loadVehicles();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final driver = context.watch<DriverProvider>();
    final vehicles = driver.vehicles;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'My Vehicles',
          style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
            onPressed: _showAddVehicleModal,
            tooltip: 'Add Vehicle',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : vehicles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text(
                        'No vehicles registered yet',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Add your bike, tuk-tuk, or car to get started.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _showAddVehicleModal,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Vehicle', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadVehicles,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFF2563EB), size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'You can register multiple vehicles (e.g. Bike + Tuk-Tuk). Switch your active vehicle anytime before going online.',
                                style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF), height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ...vehicles.map((v) => _VehicleCard(vehicle: v, onRefresh: _loadVehicles)),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _showAddVehicleModal,
                        icon: const Icon(Icons.add_circle_outline),
                        label: const Text(
                          '+ Add Another Vehicle',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _VehicleCard extends StatelessWidget {
  final Map<String, dynamic> vehicle;
  final VoidCallback onRefresh;

  const _VehicleCard({required this.vehicle, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final driver = context.read<DriverProvider>();
    final int id = vehicle['id'] ?? 0;
    final String vType = (vehicle['vehicle_type'] ?? 'car').toString().toUpperCase();
    final String vNum = (vehicle['vehicle_number'] ?? '').toString().toUpperCase();
    final String vModel = vehicle['vehicle_model'] ?? '';
    final String vColor = vehicle['vehicle_color'] ?? '';
    final bool isActive = vehicle['is_active'] == true;
    final bool isApproved = vehicle['is_approved'] == true;
    final String? rejectionReason = vehicle['rejection_reason'];

    IconData iconData = Icons.directions_car_filled;
    if (vType.contains('BIKE')) iconData = Icons.two_wheeler;
    if (vType.contains('TUK')) iconData = Icons.electric_rickshaw;
    if (vType.contains('VAN')) iconData = Icons.airport_shuttle;
    if (vType.contains('TRUCK')) iconData = Icons.local_shipping;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive ? AppColors.accent : AppColors.divider,
          width: isActive ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(iconData, color: isActive ? const Color(0xFFD97706) : Colors.grey[700]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          vNum,
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            vType,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [vModel, vColor].where((s) => s.isNotEmpty).join(' • '),
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (!isActive && !isApproved)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete Vehicle'),
                        content: Text('Are you sure you want to remove $vNum?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await driver.deleteVehicle(id);
                      onRefresh();
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 14),
                          SizedBox(width: 4),
                          Text(
                            'ACTIVE NOW',
                            style: TextStyle(
                              color: Color(0xFF16A34A),
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (isApproved)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'APPROVED',
                        style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w900, fontSize: 11),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'PENDING APPROVAL',
                        style: TextStyle(
                          color: Color(0xFFD97706),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
              if (isApproved && !isActive)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    try {
                      await driver.selectActiveVehicle(id);
                      onRefresh();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Switched to $vType ($vNum)')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(e.toString())),
                        );
                      }
                    }
                  },
                  child: const Text('Switch to this', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
            ],
          ),
          if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Rejection note: $rejectionReason',
              style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddVehicleSheet extends StatefulWidget {
  const _AddVehicleSheet();

  @override
  State<_AddVehicleSheet> createState() => _AddVehicleSheetState();
}

class _AddVehicleSheetState extends State<_AddVehicleSheet> {
  final _formKey = GlobalKey<FormState>();
  String _vehicleType = 'bike';
  final _plateCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();

  String? _crBookUrl;
  String? _insuranceUrl;
  bool _uploadingCr = false;
  bool _uploadingIns = false;
  bool _submitting = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAndUploadDoc(String kind) async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return;

    setState(() {
      if (kind == 'cr') _uploadingCr = true;
      if (kind == 'ins') _uploadingIns = true;
    });

    try {
      final form = FormData.fromMap({
        'document_type': kind == 'cr' ? 'vehicle_reg' : 'insurance',
        'document': await MultipartFile.fromFile(file.path),
      });
      final res = await ApiClient.instance.dio.post('/driver/documents', data: form);
      final url = res.data?['document_url'] ?? res.data?['url'];
      setState(() {
        if (kind == 'cr') _crBookUrl = url?.toString();
        if (kind == 'ins') _insuranceUrl = url?.toString();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to upload document.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (kind == 'cr') _uploadingCr = false;
          if (kind == 'ins') _uploadingIns = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);

    try {
      final ok = await context.read<DriverProvider>().addVehicle(
            vehicleType: _vehicleType,
            vehicleNumber: _plateCtrl.text.trim().toUpperCase(),
            vehicleModel: _modelCtrl.text.trim().isNotEmpty ? _modelCtrl.text.trim() : null,
            vehicleColor: _colorCtrl.text.trim().isNotEmpty ? _colorCtrl.text.trim() : null,
            vehicleYear: int.tryParse(_yearCtrl.text.trim()),
            registrationDocUrl: _crBookUrl,
            insuranceDocUrl: _insuranceUrl,
          );

      if (mounted) {
        if (ok) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vehicle submitted for admin approval!'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to add vehicle.'), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add New Vehicle',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Add another vehicle you own to receive trips in that category.',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 18),
              const Text('Vehicle Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _vehicleType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: const [
                  DropdownMenuItem(value: 'bike', child: Text('🛵 Motorbike')),
                  DropdownMenuItem(value: 'tuk', child: Text('🛺 Three-Wheeler (Tuk-Tuk)')),
                  DropdownMenuItem(value: 'car', child: Text('🚗 Car')),
                  DropdownMenuItem(value: 'van', child: Text('🚐 Van')),
                  DropdownMenuItem(value: 'truck', child: Text('🚚 Light Truck')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _vehicleType = val);
                },
              ),
              const SizedBox(height: 14),
              const Text('Plate Number (e.g. WP BXX-1234)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _plateCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'WP BXX-1234',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Enter vehicle plate number' : null,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Model (e.g. Bajaj RE)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _modelCtrl,
                          decoration: InputDecoration(
                            hintText: 'Bajaj RE',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _colorCtrl,
                          decoration: InputDecoration(
                            hintText: 'Red',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Vehicle Documents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(
                          color: _crBookUrl != null ? Colors.green : Colors.grey[300]!,
                        ),
                      ),
                      onPressed: _uploadingCr ? null : () => _pickAndUploadDoc('cr'),
                      icon: _uploadingCr
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(
                              _crBookUrl != null ? Icons.check_circle : Icons.upload_file,
                              color: _crBookUrl != null ? Colors.green : Colors.grey[700],
                            ),
                      label: Text(
                        _crBookUrl != null ? 'CR Book Added' : 'Upload CR',
                        style: TextStyle(
                          color: _crBookUrl != null ? Colors.green : Colors.grey[800],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(
                          color: _insuranceUrl != null ? Colors.green : Colors.grey[300]!,
                        ),
                      ),
                      onPressed: _uploadingIns ? null : () => _pickAndUploadDoc('ins'),
                      icon: _uploadingIns
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(
                              _insuranceUrl != null ? Icons.check_circle : Icons.upload_file,
                              color: _insuranceUrl != null ? Colors.green : Colors.grey[700],
                            ),
                      label: Text(
                        _insuranceUrl != null ? 'Insurance Added' : 'Upload Insurance',
                        style: TextStyle(
                          color: _insuranceUrl != null ? Colors.green : Colors.grey[800],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submit Vehicle for Approval', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
