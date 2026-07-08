import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/motion.dart';
import '../auth_provider.dart';
import 'otp_verification_screen.dart';

/// New-user registration screen — alternative entry to the implicit signup
/// that happens via the role cards. Captures full_name up-front so the
/// backend can stamp it on the User row at first OTP verification.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  String? _role;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  String get _normalizedPhone {
    final raw = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    return raw.length > 10 ? raw.substring(0, 10) : raw;
  }

  Future<void> _register() async {
    setState(() => _error = null);
    final role = _role;
    if (role == null) {
      setState(() => _error = 'Choose Customer or Driver to continue');
      return;
    }
    if (_nameCtrl.text.trim().length < 2) {
      setState(() => _error = 'Enter your full name');
      return;
    }
    final phone = _normalizedPhone;
    if (phone.length != 10) {
      setState(() => _error = 'Enter a valid 10-digit phone number');
      return;
    }

    setState(() => _busy = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendOTP(phone);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = auth.lastError ?? 'Failed to send OTP');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OTPVerificationScreen(
          phoneNumber: phone,
          role: role,
          fullName: _nameCtrl.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Pressable(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.12)),
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const EntranceSlide(
                    child: ZiggoWordmark(onDark: true, size: 56),
                  ),
                  const SizedBox(height: 18),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 100),
                    child: const Text(
                      'Create your\naccount',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.1,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 160),
                    child: Text(
                      "We'll text you a 6-digit code to confirm your number.",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Role tabs
                  EntranceSlide(
                    delay: const Duration(milliseconds: 200),
                    child: _RoleTabs(
                      role: _role,
                      onChanged: (v) => setState(() => _role = v),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // Name input
                  EntranceSlide(
                    delay: const Duration(milliseconds: 260),
                    child: _input(
                      label: 'FULL NAME',
                      controller: _nameCtrl,
                      icon: Icons.person_outline_rounded,
                      hint: 'e.g. Faris Ahmed',
                      keyboardType: TextInputType.name,
                      capitalize: true,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Phone input
                  EntranceSlide(
                    delay: const Duration(milliseconds: 320),
                    child: _input(
                      label: 'PHONE NUMBER',
                      controller: _phoneCtrl,
                      icon: Icons.phone_iphone_rounded,
                      hint: '0712345678',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                    ),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.error.withOpacity(0.3)),
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
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 380),
                    child: PrimaryButton(
                      label: 'CONTINUE',
                      icon: Icons.arrow_forward_rounded,
                      gold: true,
                      busy: _busy,
                      onPressed: _register,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.45),
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          const TextSpan(text: 'Already have an account?  '),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: const Text(
                                'Sign in',
                                style: TextStyle(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
    );
  }

  Widget _input({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool capitalize = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white54,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  textCapitalization: capitalize
                      ? TextCapitalization.words
                      : TextCapitalization.none,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontWeight: FontWeight.w500,
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoleTabs extends StatelessWidget {
  final String? role;
  final ValueChanged<String> onChanged;
  const _RoleTabs({required this.role, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Row(
        children: [
          _tab(
            label: 'Customer',
            icon: Icons.shopping_bag_rounded,
            selected: role == 'customer',
            onTap: () => onChanged('customer'),
          ),
          _tab(
            label: 'Driver',
            icon: Icons.directions_car_filled_rounded,
            selected: role == 'driver',
            onTap: () => onChanged('driver'),
          ),
        ],
      ),
    );
  }

  Widget _tab({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
                  )
                : null,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.45),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
