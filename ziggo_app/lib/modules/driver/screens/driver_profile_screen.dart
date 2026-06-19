import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../auth/auth_provider.dart';
import '../../customer/screens/support_screen.dart';
import '../driver_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../app/app_styles.dart';
import 'driver_documents_screen.dart';
import 'driver_history_screen.dart';

// Local light tokens — mirror the customer/user light theme.
const Color _kBg = AppColors.background;
const Color _kCard = AppColors.surface;
const Color _kCardLight = AppColors.surfaceMuted;

/// PickMe-style driver profile — blue gradient hero + dark body with the
/// driver's stats, bio basics, and account actions.
class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  Future<void> _pickAndUploadPhoto(BuildContext context) async {
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
              title: const Text('Take a photo', style: TextStyle(fontWeight: FontWeight.w900)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('Pick from gallery', style: TextStyle(fontWeight: FontWeight.w900)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Uploading profile photo...'),
          ],
        ),
        duration: Duration(days: 1),
      ),
    );

    final ok = await context.read<DriverProvider>().updateProfilePhoto(picked.path);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated successfully!'), backgroundColor: AppColors.success),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to upload profile photo.'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _editPhone(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ctrl = TextEditingController(text: auth.phoneNumber);
    final newPhone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Update Phone Number', style: TextStyle(fontWeight: FontWeight.w900)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone Number', hintText: 'e.g. 0755960594'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newPhone != null && newPhone.trim().isNotEmpty && context.mounted) {
      try {
        await auth.updateProfile(phoneNumber: newPhone.trim());
        if (context.mounted) {
          await context.read<DriverProvider>().loadProfile();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Phone number updated successfully!'), backgroundColor: AppColors.success),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update phone: $e'), backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final driver = context.watch<DriverProvider>();
    final profile = driver.profile ?? const <String, dynamic>{};

    final name = auth.fullName ?? profile['full_name']?.toString() ?? 'Driver';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'D';
    final driverId = (profile['id'] ?? '—').toString();
    final phone = auth.phoneNumber ?? profile['phone_number']?.toString() ?? '';
    final photoPath = profile['profile_photo']?.toString();
    final photoUrl = (photoPath != null && photoPath.isNotEmpty)
        ? (photoPath.startsWith('http')
            ? photoPath
            : '${ApiConfig.baseHost}$photoPath')
        : null;

    final rating = (profile['rating'] as num?)?.toDouble() ?? 0;
    final trips = (profile['today_rides'] as num?)?.toInt() ?? 0;
    final acceptance = (profile['acceptance_rate'] as num?)?.toDouble() ?? 100;
    final isApproved = profile['is_approved'] == true;
    final vehicleType = (profile['vehicle_type'] ?? '').toString();
    final vehicleNumber = (profile['vehicle_number'] ?? '').toString();

    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _Header(
              name: name,
              initial: initial,
              driverId: driverId,
              photoUrl: photoUrl,
              vehicleType: vehicleType,
              onBack: () => Navigator.pop(context),
              onEditPhoto: () => _pickAndUploadPhoto(context),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _statsRow(rating, trips, acceptance),
            ),
          ),
          if (!isApproved)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: _banner(
                  'Your account is pending approval. You can\'t go online yet.',
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  _infoRow(Icons.phone_rounded, 'Phone',
                      phone.isEmpty ? '—' : phone,
                      onTap: () => _editPhone(context)),
                  _infoRow(Icons.language_rounded, 'Knows', 'English'),
                  _infoRow(Icons.directions_car_rounded, 'Vehicle',
                      vehicleNumber.isEmpty ? '—' : vehicleNumber),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: _kCard,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    _listTile(
                      icon: Icons.directions_car_filled_rounded,
                      title: 'Vehicle details',
                      trailing: vehicleNumber.isEmpty ? null : '($vehicleNumber)',
                      onTap: () => _detailsSheet(
                        context,
                        title: 'Vehicle details',
                        rows: {
                          'Type': vehicleType.toUpperCase(),
                          'Model': (profile['vehicle_model'] ?? '—').toString(),
                          'Number': vehicleNumber.isEmpty ? '—' : vehicleNumber,
                          'Color': (profile['vehicle_color'] ?? '—').toString(),
                        },
                      ),
                    ),
                    _divider(),
                    _listTile(
                      icon: Icons.person_rounded,
                      title: 'My details',
                      onTap: () => _detailsSheet(
                        context,
                        title: 'My details',
                        rows: {
                          'Name': name,
                          'Driver ID': driverId,
                          'Phone': phone.isEmpty ? '—' : phone,
                          'NIC': (profile['nic_number'] ?? '—').toString(),
                          'License': (profile['license_number'] ?? '—').toString(),
                        },
                      ),
                    ),

                    _listTile(
                      icon: Icons.qr_code_rounded,
                      title: 'Show Scan & Go QR',
                      onTap: () => _showQrSheet(context, driverId, name, vehicleNumber, vehicleType),
                    ),
                    _divider(),
                    _listTile(
                      icon: Icons.group_add_rounded,
                      title: 'Refer & Earn',
                      onTap: () {
                        final code = profile['referral_code']?.toString() ?? 'D-$driverId';
                        _showReferralSheet(context, code);
                      },
                    ),
                    _divider(),
                    _listTile(
                      icon: Icons.badge_rounded,
                      title: 'KYC documents',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DriverDocumentsScreen()),
                      ),
                    ),
                    _divider(),
                    _listTile(
                      icon: Icons.receipt_long_rounded,
                      title: 'My rides & statements',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const DriverHistoryScreen()),
                      ),
                    ),
                    _divider(),
                    _listTile(
                      icon: Icons.emergency_share_rounded,
                      title: 'Emergency contacts',
                      onTap: () => _detailsSheet(
                        context,
                        title: 'Emergency contact',
                        rows: {
                          'Name': (profile['relative_name'] ?? '—').toString(),
                          'Relationship':
                              (profile['relative_relationship'] ?? '—').toString(),
                          'Contact':
                              (profile['relative_contact'] ?? '—').toString(),
                        },
                      ),
                    ),
                    _divider(),
                    _listTile(
                      icon: Icons.support_agent_rounded,
                      title: 'Help & support',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SupportScreen(isDriver: true)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: GestureDetector(
                onTap: () => _confirmLogout(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Logout',
                        style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(double rating, int trips, double acceptance) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _stat(
              rating > 0 ? rating.toStringAsFixed(1) : '0',
              'Rating',
              icon: Icons.star_rounded,
              iconColor: _kGold,
            ),
          ),
          _statDivider(),
          Expanded(child: _stat(trips.toString(), 'Trips')),
          _statDivider(),
          Expanded(child: _stat('${acceptance.toStringAsFixed(0)}%', 'Accept')),
        ],
      ),
    );
  }

  Widget _stat(String value, String label, {IconData? icon, Color? iconColor}) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 3),
              Icon(icon, color: iconColor, size: 16),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _statDivider() =>
      Container(width: 1, height: 30, color: AppColors.divider);

  Widget _banner(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textTertiary, size: 20),
            const SizedBox(width: 12),
            Text(
              '$label  ',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.edit_rounded, color: AppColors.primary, size: 14),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outlinedAction({
    required IconData icon,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _kCardLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: AppColors.primary, size: 19),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _listTile({
    required IconData icon,
    required String title,
    String? trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: AppColors.textSecondary, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    text: title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                    children: trailing == null
                        ? null
                        : [
                            TextSpan(
                              text: '  $trailing',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => const Divider(
        height: 1,
        thickness: 1,
        color: AppColors.divider,
        indent: 16,
        endIndent: 16,
      );

  static void _comingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature is coming soon.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static void _detailsSheet(
    BuildContext context, {
    required String title,
    required Map<String, String> rows,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              for (final e in rows.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          e.key.toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e.value,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
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
    );
  }

  static void _showQrSheet(
    BuildContext context,
    String driverId,
    String name,
    String vehicleNumber,
    String vehicleType,
  ) {
    final qrData = 'ziggo://scan-and-go?driver_id=$driverId&name=${Uri.encodeComponent(name)}&vehicle=${Uri.encodeComponent(vehicleNumber)}&vehicle_type=${Uri.encodeComponent(vehicleType)}';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Your Scan & Go QR',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Let passengers scan this to start a ride instantly',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: AppStyles.shadowSm,
                ),
                child: QrImageView(
                  data: qrData,
                  version: QrVersions.auto,
                  size: 200.0,
                  gapless: false,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.circle,
                    color: AppColors.primary,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.circle,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Driver ID: $driverId',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${vehicleType.toUpperCase()} • $vehicleNumber',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showReferralSheet(BuildContext context, String referralCode) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Icon(Icons.volunteer_activism_rounded, color: AppColors.primary, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Refer & Earn',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Share your referral code with friends.\nWhen they join and drive, you both earn a bonus!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      referralCode,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Referral code $referralCode copied!'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share Code'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _confirmLogout(BuildContext context) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 36),
        title: const Text('Log out?',
            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'You will go offline and stop receiving requests until you log back in.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                    foregroundColor: AppColors.primary,
                  ),
                  child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Log out', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (yes != true) return;
    if (!context.mounted) return;
    final driver = context.read<DriverProvider>();
    if (driver.isOnline) {
      await driver.toggleOnline(false);
    }
    if (!context.mounted) return;
    await context.read<AuthProvider>().logout();
    if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }
}

const Color _kGold = AppColors.accent;

class _Header extends StatelessWidget {
  final String name;
  final String initial;
  final String driverId;
  final String? photoUrl;
  final String vehicleType;
  final VoidCallback onBack;
  final VoidCallback onEditPhoto;

  const _Header({
    required this.name,
    required this.initial,
    required this.driverId,
    required this.photoUrl,
    required this.vehicleType,
    required this.onBack,
    required this.onEditPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 26),
      decoration: const BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: onBack,
              child: const Icon(Icons.arrow_back_rounded,
                  color: Colors.white, size: 26),
            ),
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: photoUrl != null
                    ? Image.network(
                        photoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallback(),
                      )
                    : _fallback(),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  onTap: onEditPhoto,
                  child: Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: const Icon(Icons.edit_rounded,
                        color: AppColors.primary, size: 16),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 19,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Driver ID : $driverId',
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_vehicleIcon(vehicleType),
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  vehicleType.isEmpty ? 'Driver' : _vehicleLabel(vehicleType),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() => Container(
        color: AppColors.primaryLight,
        alignment: Alignment.center,
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 40,
          ),
        ),
      );

  static IconData _vehicleIcon(String type) {
    switch (type.toLowerCase()) {
      case 'bike':
        return Icons.two_wheeler_rounded;
      case 'tuk':
        return Icons.electric_rickshaw_rounded;
      case 'van':
        return Icons.airport_shuttle_rounded;
      case 'truck':
        return Icons.local_shipping_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  static String _vehicleLabel(String type) {
    final t = type.toLowerCase();
    if (t == 'car') return 'Cabbie';
    return type.toUpperCase();
  }
}
