import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../../../core/network/api_client.dart';
import '../../../core/services/referral_tracker.dart';
import '../../auth/auth_provider.dart';
import '../driver_provider.dart';
import '../driver_theme.dart';

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
  final _relativeName = TextEditingController();
  final _relativeContact = TextEditingController();
  final _relativeRelationship = TextEditingController();
  final _referralCode = TextEditingController();

  String _vehicleType = 'car';
  String _driverType = 'ride';
  bool _busy = false;
  String? _error;
  String? _uploadStatus;

  File? _profilePhoto;
  String? _profilePhotoUrl;
  bool _profilePhotoUploading = false;

  final Map<String, File?> _localDocs = {};
  final Map<String, String?> _remoteDocs = {};
  final Map<String, bool> _uploadingDocs = {};
  final Map<String, String?> _docErrors = {};

  static const _requiredDocKeys = [
    'nic_front',
    'nic_back',
    'license_front',
    'license_back',
    'vehicle_reg',
    'insurance',
    'year_license',
    'eco_test',
    'vehicle_front',
    'vehicle_back',
    'vehicle_side',
  ];

  static const _typeLabels = {
    'nic_front': 'NIC (front)',
    'nic_back': 'NIC (back)',
    'license_front': 'Driving License (front)',
    'license_back': 'Driving License (back)',
    'vehicle_reg': 'Vehicle Registration Book',
    'insurance': 'Insurance Document',
    'year_license': 'Year License',
    'eco_test': 'Eco Test Report',
    'vehicle_front': 'Vehicle Photo (front)',
    'vehicle_back': 'Vehicle Photo (back)',
    'vehicle_side': 'Vehicle Photo (side)',
  };

  @override
  void initState() {
    super.initState();
    _initData();
    _setupAutoSave();
  }

  void _setupAutoSave() {
    for (final ctrl in [
      _fullName,
      _email,
      _nic,
      _license,
      _vehicleNumber,
      _vehicleModel,
      _vehicleColor,
      _relativeName,
      _relativeContact,
      _relativeRelationship,
      _referralCode,
    ]) {
      ctrl.addListener(_saveDraft);
    }
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('driver_reg_name', _fullName.text);
      await prefs.setString('driver_reg_email', _email.text);
      await prefs.setString('driver_reg_nic', _nic.text);
      await prefs.setString('driver_reg_license', _license.text);
      await prefs.setString('driver_reg_vnum', _vehicleNumber.text);
      await prefs.setString('driver_reg_vmodel', _vehicleModel.text);
      await prefs.setString('driver_reg_vcolor', _vehicleColor.text);
      await prefs.setString('driver_reg_relname', _relativeName.text);
      await prefs.setString('driver_reg_relcontact', _relativeContact.text);
      await prefs.setString('driver_reg_relrel', _relativeRelationship.text);
      await prefs.setString('driver_reg_ref', _referralCode.text);
      await prefs.setString('driver_reg_vtype', _vehicleType);
      await prefs.setString('driver_reg_dtype', _driverType);
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('driver_reg_name');
      await prefs.remove('driver_reg_email');
      await prefs.remove('driver_reg_nic');
      await prefs.remove('driver_reg_license');
      await prefs.remove('driver_reg_vnum');
      await prefs.remove('driver_reg_vmodel');
      await prefs.remove('driver_reg_vcolor');
      await prefs.remove('driver_reg_relname');
      await prefs.remove('driver_reg_relcontact');
      await prefs.remove('driver_reg_relrel');
      await prefs.remove('driver_reg_ref');
      await prefs.remove('driver_reg_vtype');
      await prefs.remove('driver_reg_dtype');
    } catch (_) {}
  }

  Future<void> _initData() async {
    // 1. Referral code
    final pending = await ReferralTracker.getPendingReferralCode();
    if (pending != null && pending.isNotEmpty && mounted) {
      setState(() {
        _referralCode.text = pending;
      });
    }

    // 2. Draft / prefill restore
    try {
      final prefs = await SharedPreferences.getInstance();
      final auth = context.read<AuthProvider>();
      final driver = context.read<DriverProvider>();
      final prof = driver.profile ?? {};

      final draftName = prefs.getString('driver_reg_name') ?? (auth.fullName ?? (prof['full_name']?.toString() ?? ''));
      if (draftName.isNotEmpty && _fullName.text.isEmpty) _fullName.text = draftName;

      final draftEmail = prefs.getString('driver_reg_email') ?? (auth.email ?? (prof['email']?.toString() ?? ''));
      if (draftEmail.isNotEmpty && _email.text.isEmpty) _email.text = draftEmail;

      final draftNic = prefs.getString('driver_reg_nic') ?? (prof['nic_number']?.toString() ?? '');
      if (draftNic.isNotEmpty && _nic.text.isEmpty) _nic.text = draftNic;

      final draftLicense = prefs.getString('driver_reg_license') ?? (prof['license_number']?.toString() ?? '');
      if (draftLicense.isNotEmpty && _license.text.isEmpty) _license.text = draftLicense;

      final draftVnum = prefs.getString('driver_reg_vnum') ?? (prof['vehicle_number']?.toString() ?? '');
      if (draftVnum.isNotEmpty && _vehicleNumber.text.isEmpty) _vehicleNumber.text = draftVnum;

      final draftVmodel = prefs.getString('driver_reg_vmodel') ?? (prof['vehicle_model']?.toString() ?? '');
      if (draftVmodel.isNotEmpty && _vehicleModel.text.isEmpty) _vehicleModel.text = draftVmodel;

      final draftVcolor = prefs.getString('driver_reg_vcolor') ?? (prof['vehicle_color']?.toString() ?? '');
      if (draftVcolor.isNotEmpty && _vehicleColor.text.isEmpty) _vehicleColor.text = draftVcolor;

      final draftRelname = prefs.getString('driver_reg_relname') ?? (prof['relative_name']?.toString() ?? '');
      if (draftRelname.isNotEmpty && _relativeName.text.isEmpty) _relativeName.text = draftRelname;

      final draftRelcontact = prefs.getString('driver_reg_relcontact') ?? (prof['relative_contact']?.toString() ?? '');
      if (draftRelcontact.isNotEmpty && _relativeContact.text.isEmpty) _relativeContact.text = draftRelcontact;

      final draftRelrel = prefs.getString('driver_reg_relrel') ?? (prof['relative_relationship']?.toString() ?? '');
      if (draftRelrel.isNotEmpty && _relativeRelationship.text.isEmpty) _relativeRelationship.text = draftRelrel;

      final draftVtype = prefs.getString('driver_reg_vtype') ?? (prof['vehicle_type']?.toString() ?? 'car');
      _vehicleType = draftVtype;

      final draftDtype = prefs.getString('driver_reg_dtype') ?? (prof['driver_type']?.toString() ?? 'ride');
      _driverType = draftDtype;

      final existingPhoto = auth.profilePhoto ?? prof['profile_photo']?.toString();
      if (existingPhoto != null && existingPhoto.isNotEmpty) {
        _profilePhotoUrl = existingPhoto;
      }
    } catch (_) {}

    // 3. Restore uploaded KYC documents from server
    try {
      final r = await ApiClient.instance.dio.get('/driver/documents');
      if (r.data is List && mounted) {
        setState(() {
          for (final item in r.data as List) {
            if (item is Map && item['document_type'] != null && item['document_url'] != null) {
              final type = item['document_type'].toString();
              final url = item['document_url'].toString();
              if (url.isNotEmpty) {
                _remoteDocs[type] = url;
              }
            }
          }
        });
      }
    } catch (_) {}
    if (mounted) setState(() {});
  }

  String _absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    return '${ApiConfig.baseHost}$path';
  }

  Future<File?> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
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

  Future<void> _pickAndUploadProfilePhoto() async {
    final file = await _pickImage();
    if (file == null) return;

    setState(() {
      _profilePhoto = file;
      _profilePhotoUploading = true;
      _error = null;
    });

    try {
      final photoForm = FormData.fromMap({
        'photo': await MultipartFile.fromFile(file.path),
      });
      final res = await ApiClient.instance.dio.post('/driver/profile-photo', data: photoForm);
      final url = res.data?['profile_photo']?.toString();
      if (mounted) {
        setState(() {
          _profilePhotoUrl = url;
          _profilePhotoUploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _profilePhotoUploading = false;
        });
      }
    }
  }

  Future<void> _pickAndUploadDoc(String kind) async {
    final file = await _pickImage();
    if (file == null) return;

    setState(() {
      _localDocs[kind] = file;
      _uploadingDocs[kind] = true;
      _docErrors[kind] = null;
      _error = null;
    });

    try {
      final docForm = FormData.fromMap({
        'document_type': kind,
        'document': await MultipartFile.fromFile(file.path),
      });
      final res = await ApiClient.instance.dio.post('/driver/documents', data: docForm);
      final url = res.data?['document_url']?.toString();
      if (mounted) {
        setState(() {
          _remoteDocs[kind] = url ?? 'uploaded';
          _uploadingDocs[kind] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Upload failed';
        if (e is DioException) {
          msg = e.response?.data?['detail']?.toString() ?? e.message ?? msg;
        }
        setState(() {
          _uploadingDocs[kind] = false;
          _docErrors[kind] = msg;
        });
      }
    }
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
    _relativeName.dispose();
    _relativeContact.dispose();
    _relativeRelationship.dispose();
    _referralCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final hasPhoto = _profilePhoto != null || (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty);
    if (!hasPhoto) {
      setState(() => _error = 'Please select and upload a Profile Photo');
      return;
    }

    for (final kind in _requiredDocKeys) {
      final hasDoc = (_remoteDocs[kind] != null && _remoteDocs[kind]!.isNotEmpty) || _localDocs[kind] != null;
      if (!hasDoc) {
        final label = _typeLabels[kind] ?? kind;
        setState(() => _error = 'Please upload $label');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
      _uploadStatus = 'Saving details...';
    });

    try {
      // 1. Ensure profile photo is uploaded
      if (_profilePhoto != null && (_profilePhotoUrl == null || _profilePhotoUrl!.isEmpty)) {
        if (mounted) setState(() => _uploadStatus = 'Uploading profile photo...');
        final photoForm = FormData.fromMap({
          'photo': await MultipartFile.fromFile(_profilePhoto!.path),
        });
        final res = await ApiClient.instance.dio.post('/driver/profile-photo', data: photoForm);
        _profilePhotoUrl = res.data?['profile_photo']?.toString();
      }

      // 2. Ensure all locally selected docs are uploaded
      int idx = 0;
      for (final kind in _requiredDocKeys) {
        idx++;
        final isRemote = _remoteDocs[kind] != null && _remoteDocs[kind]!.isNotEmpty;
        final localFile = _localDocs[kind];
        if (!isRemote && localFile != null) {
          final label = _typeLabels[kind] ?? kind;
          if (mounted) {
            setState(() => _uploadStatus = 'Uploading $label ($idx/${_requiredDocKeys.length})...');
          }
          final docForm = FormData.fromMap({
            'document_type': kind,
            'document': await MultipartFile.fromFile(localFile.path),
          });
          final res = await ApiClient.instance.dio.post('/driver/documents', data: docForm);
          _remoteDocs[kind] = res.data?['document_url']?.toString() ?? 'uploaded';
        }
      }

      // 3. Submit registration details
      if (mounted) setState(() => _uploadStatus = 'Submitting registration...');
      final err = await context.read<DriverProvider>().register(
            fullName: _fullName.text.trim(),
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            nicNumber: _nic.text.trim(),
            licenseNumber: _license.text.trim(),
            vehicleType: _vehicleType,
            driverType: _driverType,
            vehicleNumber: _vehicleNumber.text.trim(),
            vehicleModel: _vehicleModel.text.trim(),
            vehicleColor: _vehicleColor.text.trim(),
            relativeName: _relativeName.text.trim(),
            relativeContact: _relativeContact.text.trim(),
            relativeRelationship: _relativeRelationship.text.trim(),
            referralCode: _referralCode.text.trim(),
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

      await ReferralTracker.markAttributed();
      await _clearDraft();

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
        String msg = e.toString();
        if (e is DioException) {
          msg = e.response?.data?['detail']?.toString() ?? e.message ?? e.toString();
        }
        setState(() {
          _busy = false;
          _error = 'Submission failed: $msg';
          _uploadStatus = null;
        });
      }
    }
  }

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 36),
        title: const Text('Exit Registration?', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Your uploaded documents and entered details are saved. Are you sure you want to exit?',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
                  child: const Text(
                    'Exit',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (yes != true) return;
    if (!mounted) return;
    await context.read<AuthProvider>().logout();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: driverTheme(context),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _logout();
        },
        child: _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: kDriverBg,
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.directions_car_filled_rounded,
                              color: AppColors.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Text(
                            'DRIVER SIGNUP',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: _logout,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.logout_rounded, color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'Exit',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Tell us about you\n& your vehicle',
                      style: TextStyle(
                        color: Colors.white,
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
                        color: Colors.white70,
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
                        onTap: _pickAndUploadProfilePhoto,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: kDriverCardLight,
                              backgroundImage: _profilePhoto != null
                                  ? FileImage(_profilePhoto!) as ImageProvider
                                  : (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty
                                      ? NetworkImage(_absoluteUrl(_profilePhotoUrl!))
                                      : null),
                              child: (_profilePhoto == null && (_profilePhotoUrl == null || _profilePhotoUrl!.isEmpty))
                                  ? const Icon(Icons.add_a_photo_rounded, color: AppColors.textTertiary, size: 24)
                                  : null,
                            ),
                            if (_profilePhotoUploading)
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.4),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  ),
                                ),
                              ),
                          ],
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
                              _profilePhotoUploading
                                  ? 'Uploading...'
                                  : (_profilePhoto != null || (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty)
                                      ? '✓ Photo uploaded successfully'
                                      : 'Upload a clear profile photo'),
                              style: TextStyle(
                                color: (_profilePhoto != null || (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty))
                                    ? AppColors.success
                                    : AppColors.textSecondary,
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
                          const SizedBox(height: 10),
                          _field(_referralCode, 'Referral Code (Optional)', Icons.group_add_rounded, required: false, hint: 'E.g. D-1234'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionHeader('EMERGENCY CONTACT (CLOSE RELATIVE)'),
                    const SizedBox(height: 10),
                    _card(
                      Column(
                        children: [
                          _field(_relativeName, 'Close Relative Name', Icons.person_outline_rounded,
                              hint: 'John Doe'),
                          const SizedBox(height: 10),
                          _field(_relativeContact, 'Contact Number', Icons.phone_android_rounded,
                              hint: '0771234567', keyboard: TextInputType.phone),
                          const SizedBox(height: 10),
                          _field(_relativeRelationship, 'Relationship', Icons.family_restroom_rounded,
                              hint: 'Father, Spouse, etc.'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    _sectionHeader('VEHICLE DETAILS'),
                    const SizedBox(height: 10),
                    _card(
                      Column(
                        children: [
                          _driverTypeRow(),
                          const SizedBox(height: 16),
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
                          _docUploadRow('nic_front', 'NIC (front)'),
                          const Divider(height: 20),
                          _docUploadRow('nic_back', 'NIC (back)'),
                          const Divider(height: 20),
                          _docUploadRow('license_front', 'Driving License (front)'),
                          const Divider(height: 20),
                          _docUploadRow('license_back', 'Driving License (back)'),
                          const Divider(height: 20),
                          _docUploadRow('vehicle_reg', 'Vehicle Registration Book'),
                          const Divider(height: 20),
                          _docUploadRow('insurance', 'Insurance Document'),
                          const Divider(height: 20),
                          _docUploadRow('year_license', 'Year License'),
                          const Divider(height: 20),
                          _docUploadRow('eco_test', 'Eco Test Report'),
                          const Divider(height: 20),
                          _docUploadRow('vehicle_front', 'Vehicle Photo (front)'),
                          const Divider(height: 20),
                          _docUploadRow('vehicle_back', 'Vehicle Photo (back)'),
                          const Divider(height: 20),
                          _docUploadRow('vehicle_side', 'Vehicle Photo (side)'),
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _uploadStatus!,
                                style: const TextStyle(
                                  color: AppColors.primaryLight,
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
        color: kDriverCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
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
              onTap: () {
                setState(() => _vehicleType = t.$1);
                _saveDraft();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      t.$2,
                      color: sel ? Colors.white : AppColors.textSecondary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      t.$3,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: sel ? Colors.white : AppColors.textSecondary,
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

  Widget _docUploadRow(String kind, String label) {
    final localFile = _localDocs[kind];
    final remoteUrl = _remoteDocs[kind];
    final isUploading = _uploadingDocs[kind] == true;
    final docError = _docErrors[kind];
    final isUploaded = (remoteUrl != null && remoteUrl.isNotEmpty) || localFile != null;

    ImageProvider? imageProvider;
    if (localFile != null) {
      imageProvider = FileImage(localFile);
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      imageProvider = NetworkImage(_absoluteUrl(remoteUrl));
    }

    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: kDriverCardLight,
            borderRadius: BorderRadius.circular(12),
            image: imageProvider != null
                ? DecorationImage(image: imageProvider, fit: BoxFit.cover)
                : null,
          ),
          child: imageProvider == null
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
              if (isUploading)
                const Text(
                  'Uploading to server...',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else if (docError != null)
                Text(
                  docError,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Text(
                  isUploaded ? '✓ Uploaded & Ready' : 'Not uploaded yet',
                  style: TextStyle(
                    color: isUploaded ? AppColors.success : AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        if (isUploading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
            ),
          )
        else
          OutlinedButton(
            onPressed: () => _pickAndUploadDoc(kind),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(color: isUploaded ? AppColors.success.withOpacity(0.5) : AppColors.divider),
              backgroundColor: isUploaded ? AppColors.success.withOpacity(0.05) : null,
            ),
            child: Text(isUploaded ? 'Replace' : 'Upload',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: isUploaded ? AppColors.success : AppColors.primary,
                )),
          ),
      ],
    );
  }

  Widget _driverTypeRow() {
    const dtypes = [
      ('ride', Icons.directions_car_rounded, 'Ride Driver'),
      ('delivery', Icons.local_shipping_rounded, 'Delivery Driver'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DRIVER TYPE',
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
          children: dtypes.map((t) {
            final sel = _driverType == t.$1;
            return GestureDetector(
              onTap: () {
                setState(() => _driverType = t.$1);
                _saveDraft();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.primary : AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      t.$2,
                      color: sel ? Colors.white : AppColors.textSecondary,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      t.$3,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: sel ? Colors.white : AppColors.textSecondary,
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
}
