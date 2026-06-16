import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/ambient_orbs.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/auth_provider.dart';
import '../referrals_provider.dart';

class EarnWithZiggoScreen extends StatefulWidget {
  const EarnWithZiggoScreen({super.key});

  @override
  State<EarnWithZiggoScreen> createState() => _EarnWithZiggoScreenState();
}

class _EarnWithZiggoScreenState extends State<EarnWithZiggoScreen> {
  final _codeCtrl = TextEditingController();
  bool _applying = false;
  String? _applyError;
  String? _applySuccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ReferralsProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _copyToClipboard(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Referral code copied to clipboard!'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _shareCode(String code) async {
    final message = "Sign up for Ziggo using my referral code $code and get Rs.300.00 wallet credit on your first completed trip! Download the app now.";
    final url = Uri.parse("whatsapp://send?text=${Uri.encodeComponent(message)}");
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      // Fallback to clipboard and alert
      _copyToClipboard(code);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WhatsApp not installed. Code copied to share!'),
            backgroundColor: AppColors.info,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _applyReferral() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _applying = true;
      _applyError = null;
      _applySuccess = null;
    });

    final referrals = context.read<ReferralsProvider>();
    final ok = await referrals.applyReferralCode(code);
    
    if (mounted) {
      setState(() => _applying = false);
      if (ok) {
        setState(() => _applySuccess = 'Referral code applied successfully!');
        _codeCtrl.clear();
        context.read<AuthProvider>().bootstrap(); // Refresh user state
      } else {
        setState(() => _applyError = 'Invalid referral code or code already applied.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.watch<ReferralsProvider>();
    final auth = context.watch<AuthProvider>();
    final code = r.referralCode.isNotEmpty ? r.referralCode : (auth.referralCode ?? 'ZIGGO');
    final hasReferrer = auth.referredByUserId != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Earn with Ziggo', style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<ReferralsProvider>().refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: staggered([
            // Glassmorphic Hero Banner
            ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                children: [
                  Container(
                    height: 240,
                    decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
                  ),
                  const Positioned.fill(
                    child: AmbientOrbs(
                      colors: [
                        AppColors.primaryLight,
                        AppColors.accent,
                        AppColors.primary,
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                      boxShadow: AppStyles.shadowLg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: Colors.white.withOpacity(0.18)),
                          ),
                          child: const Text(
                            'REFER & EARN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Invite your friends\nto Ziggo!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            height: 1.1,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'You both get Rs.300.00 in wallet credit once they complete their first ride.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Share referral code card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.cardBorder),
                boxShadow: AppStyles.shadowSm,
              ),
              child: Column(
                children: [
                  const Text(
                    'YOUR REFERRAL CODE',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => _copyToClipboard(code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            code,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.copy_rounded, color: AppColors.primary, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => _shareCode(code),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.share_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'SHARE WITH FRIENDS',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Apply referral code if not already referred
            if (!hasReferrer) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.cardBorder),
                  boxShadow: AppStyles.shadowSm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WERE YOU REFERRED?',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: TextField(
                              controller: _codeCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                hintText: 'Enter referral code',
                                hintStyle: TextStyle(fontSize: 14, color: AppColors.textTertiary),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _applying ? null : _applyReferral,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _applying
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Text('APPLY', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ],
                    ),
                    if (_applyError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _applyError!,
                        style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (_applySuccess != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _applySuccess!,
                        style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Stats Dashboard Row
            Row(
              children: [
                Expanded(
                  child: _statCard('Total Invited', '${r.totalReferred}', Icons.people_outline_rounded, Colors.blue),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard('Pending', 'Rs.${r.pendingAmount.toStringAsFixed(0)}', Icons.hourglass_empty_rounded, Colors.orange),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _statCard('Earned', 'Rs.${r.earnedAmount.toStringAsFixed(0)}', Icons.account_balance_wallet_rounded, Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 26),

            // Friends List
            const Text(
              'Invited Friends',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (r.friends.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.share_rounded, color: AppColors.textTertiary, size: 36),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No friends invited yet',
                        style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Share your code above to start earning!',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ...r.friends.map((f) {
              final isCompleted = f['status'] == 'completed';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: (isCompleted ? AppColors.success : AppColors.warning).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isCompleted ? Icons.check_circle_rounded : Icons.pending_rounded,
                        color: isCompleted ? AppColors.success : AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            f['name']?.toString() ?? 'Friend',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            f['phone']?.toString() ?? '',
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Rs.${(f['amount'] as num?)?.toStringAsFixed(0) ?? '300'}',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: isCompleted ? AppColors.success : AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isCompleted ? 'Earned' : 'Pending',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isCompleted ? AppColors.success : AppColors.warning,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ]),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: AppColors.textPrimary),
            textAlign: Center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textTertiary, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
