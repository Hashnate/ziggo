import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../auth_provider.dart';
import 'profile_details_screen.dart';

class OTPVerificationScreen extends StatefulWidget {
  final String phoneNumber;
  final String role;
  /// Optional — passed in from the Registration screen so the backend can
  /// stamp it on the User row at first-ever signup. Ignored for users who
  /// already exist (returning logins).
  final String? fullName;
  const OTPVerificationScreen({
    super.key,
    required this.phoneNumber,
    required this.role,
    this.fullName,
  });

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  static const int _len = 6;
  late final TextEditingController _otpCtrl;
  late final FocusNode _focusNode;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _otpCtrl = TextEditingController();
    _focusNode = FocusNode();

    final dev = context.read<AuthProvider>().devOtp;
    if (dev != null && dev.length == _len) {
      _otpCtrl.text = dev;
    }
  }

  @override
  void dispose() {
    _otpCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String get _code => _otpCtrl.text.replaceAll(RegExp(r'\D'), '');

  Future<void> _verify() async {
    if (_code.length != _len) {
      setState(() => _error = 'Enter the $_len-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final ok = await auth.verifyOTP(
      widget.phoneNumber,
      _code,
      widget.role,
      fullName: widget.fullName,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = auth.lastError ?? 'Invalid or expired OTP');
      return;
    }
    // New customers complete their profile ("Your details") before landing on
    // home. The details screen pops back to root when done. Returning users —
    // and non-customer roles, which have their own onboarding — skip straight
    // through.
    if (auth.isNewUser && widget.role == 'customer') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ProfileDetailsScreen()),
      );
      return;
    }
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  Future<void> _resend() async {
    final auth = context.read<AuthProvider>();
    await auth.sendOTP(widget.phoneNumber);
    if (!mounted) return;
    final dev = auth.devOtp;
    if (dev != null && dev.length == _len) {
      _otpCtrl.text = dev;
      setState(() {});
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code resent'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
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
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppStyles.shadowSm,
                  ),
                  child: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 36),
              EntranceSlide(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: AppStyles.goldGlow,
                      ),
                      child: const Icon(Icons.sms_rounded, color: Colors.black, size: 30),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Verify your\nphone',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        height: 1.1,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 10),
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        children: [
                          const TextSpan(text: "Enter the 6-digit code we sent to "),
                          TextSpan(
                            text: widget.phoneNumber,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              EntranceSlide(
                delay: const Duration(milliseconds: 120),
                child: AutofillGroup(
                  child: GestureDetector(
                    onTap: () => _focusNode.requestFocus(),
                    behavior: HitTestBehavior.opaque,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Offstage/transparent single TextField handling OS SMS autofill & keyboard input
                        Opacity(
                          opacity: 0.0,
                          child: TextField(
                            controller: _otpCtrl,
                            focusNode: _focusNode,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            maxLength: _len,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            enableSuggestions: true,
                            onChanged: (v) {
                              final digits = v.replaceAll(RegExp(r'\D'), '');
                              if (digits != v) {
                                _otpCtrl.value = TextEditingValue(
                                  text: digits,
                                  selection: TextSelection.collapsed(offset: digits.length),
                                );
                              }
                              setState(() {});
                              if (digits.length == _len && !_busy) {
                                _verify();
                              }
                            },
                            decoration: const InputDecoration(
                              counterText: '',
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                        ),
                        // Visual 6-cell PIN display
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(_len, (i) {
                            final code = _code;
                            final isFilled = i < code.length;
                            final isCurrent = _focusNode.hasFocus && i == code.length;
                            final char = isFilled ? code[i] : '';

                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 48,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isCurrent
                                      ? AppColors.primary
                                      : isFilled
                                          ? AppColors.primary.withOpacity(0.6)
                                          : AppColors.cardBorder,
                                  width: isCurrent || isFilled ? 2 : 1,
                                ),
                                boxShadow: isCurrent || isFilled ? AppStyles.shadowSm : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                char,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
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
                label: 'VERIFY CODE',
                icon: Icons.check_rounded,
                gold: true,
                busy: _busy,
                onPressed: _verify,
              ),
              const SizedBox(height: 18),
              Center(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      "Didn't receive it? ",
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    GestureDetector(
                      onTap: _resend,
                      child: const Text(
                        'Resend',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
