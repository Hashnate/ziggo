import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/auth_provider.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _emContactNameCtrl = TextEditingController();
  final _emContactNumCtrl = TextEditingController();

  String? _selectedGender;
  String? _selectedLanguage;
  DateTime? _selectedBirthday;

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _nameCtrl.text = auth.fullName ?? '';
    _emailCtrl.text = auth.email ?? '';
    _emContactNameCtrl.text = auth.emergencyContactName ?? '';
    _emContactNumCtrl.text = auth.emergencyContactNumber ?? '';
    
    _selectedGender = auth.gender;
    _selectedLanguage = auth.language;
    
    if (auth.birthday != null && auth.birthday!.isNotEmpty) {
      try {
        _selectedBirthday = DateTime.parse(auth.birthday!);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _emContactNameCtrl.dispose();
    _emContactNumCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedBirthday ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (date != null) {
      setState(() {
        _selectedBirthday = date;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final bdayStr = _selectedBirthday != null 
          ? "${_selectedBirthday!.year.toString().padLeft(4, '0')}-${_selectedBirthday!.month.toString().padLeft(2, '0')}-${_selectedBirthday!.day.toString().padLeft(2, '0')}"
          : null;

      await context.read<AuthProvider>().updateProfile(
            fullName: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
            gender: _selectedGender,
            language: _selectedLanguage,
            birthday: bdayStr,
            emergencyContactName: _emContactNameCtrl.text.trim(),
            emergencyContactNumber: _emContactNumCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await context.read<AuthProvider>().logout();
    if (mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final c = auth.completeness;
    final percent = c != null ? ((c['percent'] as num?)?.toInt() ?? 0).clamp(0, 100) : 100;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Your profile',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Completeness Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$percent% complete',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (percent == 100)
                      const Row(
                        children: [
                          Text(
                            'Your information is secure',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(Icons.verified_user, color: AppColors.primary, size: 14),
                        ],
                      )
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    minHeight: 6,
                    backgroundColor: AppColors.surfaceMuted,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryDark),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              children: staggered([
                const Text('Your information', style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildInfoSection(auth),
                const SizedBox(height: 24),
                const Text('Your preferences', style: TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                _buildPreferencesSection(),
                const SizedBox(height: 30),
                PrimaryButton(
                  label: 'SAVE CHANGES',
                  icon: Icons.check_rounded,
                  busy: _busy,
                  onPressed: _save,
                ),
                const SizedBox(height: 16),
                _logoutButton(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(AuthProvider auth) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          _buildListTile(
            icon: Icons.person_outline,
            title: 'Add profile picture',
            showArrow: true,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming soon')));
            },
          ),
          const Divider(height: 1),
          _buildTextFieldTile(
            icon: Icons.badge_outlined,
            label: 'Full Name',
            controller: _nameCtrl,
          ),
          const Divider(height: 1),
          _buildListTile(
            icon: Icons.phone_android_outlined,
            title: 'Mobile',
            subtitle: auth.phoneNumber ?? '',
            showArrow: false,
            onTap: null, // Read-only
          ),
          const Divider(height: 1),
          _buildTextFieldTile(
            icon: Icons.email_outlined,
            label: 'E-mail',
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
          ),
          const Divider(height: 1),
          _buildListTile(
            icon: Icons.cake_outlined,
            title: 'Birthday',
            subtitle: _selectedBirthday != null 
                ? "${_selectedBirthday!.year}-${_selectedBirthday!.month.toString().padLeft(2, '0')}-${_selectedBirthday!.day.toString().padLeft(2, '0')}"
                : 'Select birthday',
            showArrow: true,
            onTap: _pickBirthday,
          ),
          const Divider(height: 1),
          _buildDropdownTile(
            icon: Icons.transgender_outlined,
            label: 'Gender',
            value: _selectedGender,
            items: const ['Male', 'Female', 'Other'],
            onChanged: (v) => setState(() => _selectedGender = v),
          ),
        ],
      ),
    );
  }

  Widget _buildPreferencesSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          _buildDropdownTile(
            icon: Icons.language_outlined,
            label: 'Language',
            value: _selectedLanguage,
            items: const ['English', 'Sinhala', 'Tamil'],
            onChanged: (v) => setState(() => _selectedLanguage = v),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.contact_emergency_outlined, color: AppColors.textSecondary, size: 22),
                    SizedBox(width: 16),
                    Text('Emergency Contact', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 38),
                  child: Column(
                    children: [
                      TextField(
                        controller: _emContactNameCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Contact Name',
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      TextField(
                        controller: _emContactNumCtrl,
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Contact Number',
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        keyboardType: TextInputType.phone,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildListTile(
            icon: Icons.settings_outlined,
            title: 'Additional settings',
            showArrow: true,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming soon')));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    bool showArrow = false,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null) ...[
                    Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  ] else
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (showArrow) const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildTextFieldTile({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 4),
                    border: InputBorder.none,
                  ),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  keyboardType: keyboardType,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownTile({
    required IconData icon,
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isDense: true,
                    isExpanded: true,
                    value: value,
                    hint: const Text('Select', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    icon: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    items: items.map((String item) {
                      return DropdownMenuItem<String>(
                        value: item,
                        child: Text(item),
                      );
                    }).toList(),
                    onChanged: onChanged,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoutButton() {
    return GestureDetector(
      onTap: _confirmLogout,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.textPrimary),
        ),
        child: const Text(
          'Logout',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
