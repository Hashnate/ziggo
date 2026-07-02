import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/auth_provider.dart';
import 'additional_settings_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  Future<void> _confirmLogout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.logout_rounded, color: AppColors.error, size: 36),
        title: const Text('Log out?', textAlign: TextAlign.center),
        content: const Text(
          'You will need to sign in again with your phone number.',
          textAlign: TextAlign.center,
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
                    'Log out',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }



  Future<void> _editName() async {
    final auth = context.read<AuthProvider>();
    final ctrl = TextEditingController(text: auth.fullName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Name'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Full Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName != null && newName.trim().isNotEmpty && mounted) {
      await auth.updateProfile(fullName: newName.trim());
    }
  }

  Future<void> _editEmail() async {
    final auth = context.read<AuthProvider>();
    final ctrl = TextEditingController(text: auth.email);
    final newEmail = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Email'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email Address'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newEmail != null && mounted) {
      await auth.updateProfile(email: newEmail.trim());
    }
  }

  Future<void> _editBirthday() async {
    final auth = context.read<AuthProvider>();
    final current = auth.birthday != null ? DateTime.tryParse(auth.birthday!) : null;
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now().subtract(const Duration(days: 365 * 20)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (date != null && mounted) {
      final formatted = DateFormat('yyyy-MM-dd').format(date);
      await auth.updateProfile(birthday: formatted);
    }
  }

  Future<void> _editGender() async {
    final auth = context.read<AuthProvider>();
    final gender = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Gender'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'Male'),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Male', style: TextStyle(fontSize: 16))),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'Female'),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Female', style: TextStyle(fontSize: 16))),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'Other'),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Other', style: TextStyle(fontSize: 16))),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'Prefer not to say'),
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('Prefer not to say', style: TextStyle(fontSize: 16))),
          ),
        ],
      ),
    );
    if (gender != null && mounted) {
      await auth.updateProfile(gender: gender);
    }
  }

  Future<void> _editEmergencyContact() async {
    final auth = context.read<AuthProvider>();
    final ctrl = TextEditingController(text: auth.emergencyContact);
    final contact = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emergency Contact'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Name & Phone number', hintText: 'e.g. John Doe 077...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (contact != null && mounted) {
      await auth.updateProfile(emergencyContact: contact.trim());
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Select Profile Picture',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: source);
      if (image != null && mounted) {
         final auth = context.read<AuthProvider>();
         await auth.updateProfile(profilePhoto: image.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not pick photo: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final completeness = auth.completeness;
    final percent = ((completeness?['percent'] as num?)?.toInt() ?? 100).clamp(0, 100);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Your profile',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: staggered([
          if (percent < 100) ...[
            Container(
              color: AppColors.surfaceMuted,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: percent / 100,
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${completeness?['completed_count'] ?? 8} of ${completeness?['total_count'] ?? 10} complete',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Row(
                        children: [
                          Text(
                            'Your information is secure',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 14),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          _sectionLabel('Your information'),
          _listTile(
            icon: Icons.person_outline_rounded,
            title: 'Add profile picture',
            trailing: CircleAvatar(
              radius: 14,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: auth.profilePhoto != null && auth.profilePhoto!.isNotEmpty 
                  ? (auth.profilePhoto!.startsWith('http') 
                      ? NetworkImage(auth.profilePhoto!) 
                      : FileImage(File(auth.profilePhoto!)) as ImageProvider)
                  : null,
              child: auth.profilePhoto == null || auth.profilePhoto!.isEmpty
                  ? const Icon(Icons.person, color: Colors.white, size: 18)
                  : null,
            ),
            onTap: _pickPhoto,
          ),
          _listTile(
            icon: Icons.badge_outlined,
            title: 'Full Name',
            subtitle: auth.fullName != null && auth.fullName!.isNotEmpty ? auth.fullName! : 'Add your name',
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            onTap: _editName,
          ),
          _listTile(
            icon: Icons.phone_iphone_rounded,
            title: 'Mobile',
            subtitle: auth.phoneNumber ?? 'Not provided',
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            onTap: () {}, // Mobile cannot be edited
          ),
          _listTile(
            icon: Icons.email_outlined,
            title: Row(
              children: [
                const Text('E-mail '),
                if (auth.email == null || auth.email!.isEmpty)
                  const Text(
                    'Unverified',
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            subtitle: auth.email != null && auth.email!.isNotEmpty ? auth.email! : 'Add email address',
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            onTap: _editEmail,
          ),
          _listTile(
            icon: Icons.cake_outlined,
            title: 'Birthday',
            subtitle: auth.birthday != null && auth.birthday!.isNotEmpty ? auth.birthday : 'Not provided',
            onTap: _editBirthday,
          ),
          _listTile(
            icon: Icons.transgender_outlined,
            title: 'Gender',
            subtitle: auth.gender != null && auth.gender!.isNotEmpty ? auth.gender : 'Not provided',
            onTap: _editGender,
          ),
          
          const SizedBox(height: 24),
          _sectionLabel('Your preferences'),
          _listTile(
            icon: Icons.emergency_outlined,
            title: 'Add emergency contact(s)',
            subtitle: auth.emergencyContact != null && auth.emergencyContact!.isNotEmpty ? auth.emergencyContact : 'Add emergency contact(s)',
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            onTap: _editEmergencyContact,
          ),
          _listTile(
            icon: Icons.settings_outlined,
            title: 'Additional settings',
            trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdditionalSettingsScreen()),
              );
            },
          ),
          
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: OutlinedButton(
              onPressed: _confirmLogout,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _listTile({
    required IconData icon,
    required dynamic title, // String or Widget
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 24),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title is String)
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: subtitle != null ? 13 : 15,
                        color: subtitle != null ? AppColors.textSecondary : AppColors.textPrimary,
                        fontWeight: subtitle != null ? FontWeight.w500 : FontWeight.w600,
                      ),
                    )
                  else
                    title,
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }


}
