import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../driver_theme.dart';

/// BRD: Driver KYC document upload UI.
///
/// Shows the four required document types (NIC, License, Vehicle Reg,
/// Insurance) — each with an upload tile, status pill (Pending / Verified)
/// and a tap-to-replace flow.
class DriverDocumentsScreen extends StatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  List<Map<String, dynamic>> _docs = const [];
  String? _busyKind;
  bool _loading = true;

  static const _typeLabels = {
    'nic_front': 'NIC (front)',
    'nic_back': 'NIC (back)',
    'license_front': 'Driving License (front)',
    'license_back': 'Driving License (back)',
    'vehicle_reg': 'Vehicle Registration',
    'insurance': 'Insurance',
    'year_license': 'Year License',
    'eco_test': 'Eco Test Report',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ApiClient.instance.dio.get('/driver/documents');
      if (!mounted) return;
      setState(() {
        _docs = List<Map<String, dynamic>>.from(r.data as List);
        _loading = false;
      });
    } on DioException {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _uploadFor(String kind) async {
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
    if (source == null) return;

    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() => _busyKind = kind);
    try {
      final form = FormData.fromMap({
        'document_type': kind,
        'document': await MultipartFile.fromFile(picked.path),
      });
      await ApiClient.instance.dio.post('/driver/documents', data: form);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.success,
          content: Text('${_typeLabels[kind]} uploaded — pending review'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.error,
          content: Text(e.response?.data?['detail']?.toString() ?? 'Upload failed'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busyKind = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missingCount = _docs.where((d) => d['document_url'] == null).length;
    final pendingCount =
        _docs.where((d) => d['document_url'] != null && d['is_verified'] != true).length;
    final verifiedCount = _docs.where((d) => d['is_verified'] == true).length;

    return Theme(
      data: driverTheme(context),
      child: _buildScaffold(missingCount, pendingCount, verifiedCount),
    );
  }

  Widget _buildScaffold(int missingCount, int pendingCount, int verifiedCount) {
    return Scaffold(
      backgroundColor: kDriverBg,
      appBar: AppBar(
        backgroundColor: kDriverBg,
        elevation: 0,
        title: const Text('KYC Documents'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Status summary
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_rounded, color: AppColors.primary, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Upload your documents to go online',
                                  style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  )),
                              const SizedBox(height: 4),
                              Text(
                                'Verified $verifiedCount · Pending $pendingCount · Missing $missingCount',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (final doc in _docs) _docTile(doc),
                ],
              ),
            ),
    );
  }

  Widget _docTile(Map<String, dynamic> doc) {
    final kind = doc['document_type'] as String;
    final url = doc['document_url']?.toString();
    final verified = doc['is_verified'] == true;
    final busy = _busyKind == kind;
    final label = _typeLabels[kind] ?? kind;

    final pill = verified
        ? ('Verified', AppColors.success)
        : (url == null ? ('Not uploaded', AppColors.error) : ('Pending review', AppColors.warning));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kDriverCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kDriverCardLight,
              borderRadius: BorderRadius.circular(14),
              image: (url != null && !url.endsWith('.pdf'))
                  ? DecorationImage(
                      image: NetworkImage(_absoluteUrl(url)),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: url == null
                ? const Icon(Icons.add_a_photo_outlined, color: AppColors.textTertiary)
                : (url.endsWith('.pdf')
                    ? const Icon(Icons.picture_as_pdf, color: AppColors.error)
                    : null),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: pill.$2.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    pill.$1,
                    style: TextStyle(
                      color: pill.$2,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (verified)
            const Icon(Icons.lock_rounded, color: AppColors.textTertiary, size: 18)
          else
            OutlinedButton(
              onPressed: busy ? null : () => _uploadFor(kind),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                side: const BorderSide(color: AppColors.divider),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(url == null ? 'Upload' : 'Replace',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                        color: AppColors.primary,
                      )),
            ),
        ],
      ),
    );
  }

  String _absoluteUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    final base = ApiClient.instance.dio.options.baseUrl;
    // baseUrl is like "http://host/api/v1" — we need just the origin for /static/*
    final origin = base.replaceAll(RegExp(r'/api/v1/?$'), '');
    return origin + pathOrUrl;
  }
}
