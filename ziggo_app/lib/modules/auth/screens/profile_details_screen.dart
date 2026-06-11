import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../auth_provider.dart';

/// Shown once, right after a new user verifies their OTP (signup). Captures the
/// name + optional email and writes them onto the user profile, then drops the
/// user onto the home screen. Returning users skip this entirely.
class ProfileDetailsScreen extends StatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  late final TextEditingController _firstCtrl;
  late final TextEditingController _lastCtrl;
  late final TextEditingController _emailCtrl;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Prefill from anything the backend already knows (e.g. a full_name stamped
    // at signup from the Registration screen).
    final auth = context.read<AuthProvider>();
    final parts = (auth.fullName ?? '').trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first : '';
    final last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    _firstCtrl = TextEditingController(text: first);
    _lastCtrl = TextEditingController(text: last);
    _emailCtrl = TextEditingController(text: auth.email ?? '');
  }

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (first.length < 2) {
      setState(() => _error = 'Please enter your first name');
      return;
    }
    if (email.isNotEmpty && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final fullName = [first, last].where((s) => s.isNotEmpty).join(' ');
    final auth = context.read<AuthProvider>();
    try {
      await auth.updateProfile(
        fullName: fullName,
        email: email.isEmpty ? null : email,
      );
    } catch (_) {
      // Don't trap the user on a save failure — let them into the app; the
      // profile screen can collect these again later.
    }
    if (!mounted) return;
    // Back to _Root, which now routes to home for the authenticated user.
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          // Already authenticated at this point — "back" just skips into home
          // rather than dropping back onto the login stack.
          onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
        ),
        title: const Text(
          'Your details',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You are just one step away from creating your new Ziggo '
                'account. How should we address you?',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              EntranceSlide(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        label: 'First Name',
                        controller: _firstCtrl,
                        hint: 'e.g. Mohamed',
                        keyboardType: TextInputType.name,
                        capitalize: true,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _field(
                        label: 'Last Name',
                        controller: _lastCtrl,
                        hint: 'e.g. Faris',
                        keyboardType: TextInputType.name,
                        capitalize: true,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              EntranceSlide(
                delay: const Duration(milliseconds: 100),
                child: _field(
                  label: 'E-mail (Optional)',
                  controller: _emailCtrl,
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
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
              const Spacer(),
              PrimaryButton(
                label: 'NEXT',
                icon: Icons.arrow_forward_rounded,
                gold: true,
                busy: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    bool capitalize = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            textCapitalization:
                capitalize ? TextCapitalization.words : TextCapitalization.none,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: const TextStyle(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
              ),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ],
      ),
    );
  }
}
