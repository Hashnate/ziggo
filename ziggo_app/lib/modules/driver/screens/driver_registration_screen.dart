import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/network/api_client.dart';
import '../driver_provider.dart';

class DriverRegistrationScreen extends StatefulWidget {
  const DriverRegistrationScreen({super.key});

  @override
  State<DriverRegistrationScreen> createState() => _DriverRegistrationScreenState();
}

class _DriverRegistrationScreenState extends State<DriverRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _nic = TextEditingController();
  final _license = TextEditingController();
  final _vehicleNumber = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleColor = TextEditingController();

  String _vehicleType = 'car';
  bool _busy = false;
  String? _error;

  File? _profilePhoto;
  File? _nicDoc;
  File? _licenseDoc;
  File? _vehicleRegDoc;
  File? _insuranceDoc;

  static const _typeLabels = {
    'nic': 'NIC (front)',
    'license': 'Driving License',
    'vehicle_reg': 'Vehicle Registration',
    'insurance': 'Insurance',
  };

  Future<File?> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primary),
              title: const Text('Take a photo',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Pick from gallery',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return null;
    return File(picked.path);
  }

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _nic.dispose();
    _license.dispose();
    _vehicleNumber.dispose();
    _vehicleModel.dispose();
    _vehicleColor.dispose();
    super.dispose();
  }

  String? _uploadStatus;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_profilePhoto == null) {
      setState(() => _error = 'Please select a Profile Photo');
      return;
    }
    if (_nicDoc == null || _licenseDoc == null || _vehicleRegDoc == null || _insuranceDoc == null) {
      setState(() => _error = 'Please upload all 4 required KYC documents');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _uploadStatus = 'Saving details...';
    });

    final err = await context.read<DriverProvider>().register(
          fullName: _fullName.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          nicNumber: _nic.text.trim(),
          licenseNumber: _license.text.trim(),
          vehicleType: _vehicleType,
          vehicleNumber: _vehicleNumber.text.trim(),
          vehicleModel: _vehicleModel.text.trim(),
          vehicleColor: _vehicleColor.text.trim(),
        );

    if (err != null) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = err;
          _uploadStatus = null;
        });
      }
      return;
    }

    try {
      // 1. Upload Profile Photo
      if (mounted) setState(() => _uploadStatus = 'Uploading profile photo...');
      final photoForm = FormData.fromMap({
        'photo': await MultipartFile.fromFile(_profilePhoto!.path),
      });
      await ApiClient.instance.dio.post('/driver/profile-photo', data: photoForm);

      // 2. Upload KYC Documents
      final docs = {
        'nic': _nicDoc,
        'license': _licenseDoc,
        'vehicle_reg': _vehicleRegDoc,
        'insurance': _insuranceDoc,
      };

      for (final entry in docs.entries) {
        if (mounted) {
          setState(() => _uploadStatus = 'Uploading ${_typeLabels[entry.key]}...');
        }
        final docForm = FormData.fromMap({
          'document_type': entry.key,
          'document': await MultipartFile.fromFile(entry.value!.path),
        });
        await ApiClient.instance.dio.post('/driver/documents', data: docForm);
      }

      // Load profile to trigger the pending screen status check
      await context.read<DriverProvider>().loadProfile();

      if (mounted) {
        setState(() {
          _busy = false;
          _uploadStatus = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Registration submitted successfully!'),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Documents upload failed: $e';
          _uploadStatus = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            children: staggered([
              // Hero header
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppColors.goldGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppStyles.shadowMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.directions_car_filled_rounded,
                              color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Text(
                            'DRIVER SIGNUP',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Tell us about you\n& your vehicle',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Admin will review and approve your account.',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // Profile Photo Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _card(
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          final file = await _pickImage();
                          if (file != null) {
                            setState(() => _profilePhoto = file);
                          }
                        },
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: AppColors.surfaceMuted,
                          backgroundImage: _profilePhoto != null ? FileImage(_profilePhoto!) : null,
                          child: _profilePhoto == null
                              ? const Icon(Icons.add_a_photo_rounded, color: AppColors.textTertiary, size: 24)
                              : null,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Profile Photo',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _profilePhoto == null
                                  ? 'Upload a clear profile photo'
                                  : 'Photo selected successfully',
                              style: TextStyle(
                                color: _profilePhoto == null ? AppColors.textSecondary : AppColors.success,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader('PERSONAL DETAILS'),
                    const SizedBox(height: 10),
                    _card(
                      Column(
                        children: [
                          _field(_fullName, 'Full Name', Icons.person_rounded),
                          const SizedBox(height: 10),
                          _field(_email, 'Email (optional)', Icons.email_rounded,
                              keyboard: TextInputType.emailAddress, required: false),
                          const SizedBox(height: 10),
                          _field(_nic, 'NIC Number', Icons.badge_rounded,
                              hint: '199012345678'),
                          const SizedBox(height: 10),
                          _field(_license, 'Driving License Number', Icons.credit_card_rounded),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionHeader('VEHICLE DETAILS'),
                    const SizedBox(height: 10),
                    _card(
                      Column(
                        children: [
                          _vehicleTypeRow(),
                          const SizedBox(height: 12),
                          _field(_vehicleNumber, 'Vehicle Number',
                              Icons.confirmation_number_rounded, hint: 'WP-1234'),
                          const SizedBox(height: 10),
                          _field(_vehicleModel, 'Vehicle Model',
                              Icons.directions_car_rounded, hint: 'Toyota Aqua'),
                          const SizedBox(height: 10),
                          _field(_vehicleColor, 'Vehicle Color', Icons.palette_rounded,
                              hint: 'White'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionHeader('KYC DOCUMENTS'),
                    const SizedBox(height: 10),
                    _card(
                      Column(
                        children: [
                          _docUploadRow('nic', 'NIC (front)', _nicDoc, (file) => setState(() => _nicDoc = file)),
                          const Divider(height: 20),
                          _docUploadRow('license', 'Driving License', _licenseDoc, (file) => setState(() => _licenseDoc = file)),
                          const Divider(height: 20),
                          _docUploadRow('vehicle_reg', 'Vehicle Registration Book', _vehicleRegDoc, (file) => setState(() => _vehicleRegDoc = file)),
                          const Divider(height: 20),
                          _docUploadRow('insurance', 'Insurance Document', _insuranceDoc, (file) => setState(() => _insuranceDoc = file)),
                        ],
                      ),
                    ),
                    if (_uploadStatus != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _uploadStatus!,
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 14),
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
                    const SizedBox(height: 22),
                    PrimaryButton(
                      label: 'SUBMIT FOR REVIEW',
                      icon: Icons.send_rounded,
                      busy: _busy,
                      onPressed: _submit,
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => context.read<DriverProvider>().loadProfile(),
                        icon: const Icon(Icons.refresh_rounded,
                            size: 16, color: AppColors.textSecondary),
                        label: const Text(
                          'Already submitted? Refresh status',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        color: AppColors.textTertiary,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _card(Widget child) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: child,
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    String? hint,
    TextInputType? keyboard,
    bool required = true,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
      ),
      validator: required
          ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
          : null,
    );
  }

  Widget _vehicleTypeRow() {
    const types = [
      ('bike', Icons.motorcycle_rounded, 'Bike'),
      ('tuk', Icons.electric_rickshaw_rounded, 'Tuk'),
      ('car', Icons.directions_car_filled_rounded, 'Car'),
      ('van', Icons.airport_shuttle_rounded, 'Van'),
      ('truck', Icons.local_shipping_rounded, 'Truck'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'VEHICLE TYPE',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: types.map((t) {
            final sel = _vehicleType == t.$1;
            return GestureDetector(
              onTap: () => setState(() => _vehicleType = t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? Colors.black : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      t.$2,
                      color: sel ? AppColors.primary : AppColors.textPrimary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      t.$3,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: sel ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _docUploadRow(String type, String label, File? file, ValueChanged<File> onFileSelected) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            image: file != null
                ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
                : null,
          ),
          child: file == null
              ? const Icon(Icons.description_rounded, color: AppColors.textTertiary, size: 20)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                file == null ? 'Not uploaded yet' : 'Selected',
                style: TextStyle(
                  color: file == null ? AppColors.textSecondary : AppColors.success,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: () async {
            final picked = await _pickImage();
            if (picked != null) {
              onFileSelected(picked);
            }
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
          child: Text(file == null ? 'Upload' : 'Replace',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11,
                color: AppColors.textPrimary,
              )),
        ),
      ],
    );
  }
}
