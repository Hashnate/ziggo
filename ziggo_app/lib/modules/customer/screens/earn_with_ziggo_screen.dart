import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
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

  Future<void> _shareCode(BuildContext context, String code, double amount) async {
    final formattedAmt = amount.toStringAsFixed(2);
    final message = "Sign up for Ziggo using my referral code $code and get Rs.$formattedAmt wallet credit on your first completed trip! Download the app now.";
    
    final box = context.findRenderObject() as RenderBox?;
    final sharePositionOrigin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;

    await Share.share(
      message,
      sharePositionOrigin: sharePositionOrigin,
    );
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
    try {
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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Your Referral Code', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: AppColors.primary, letterSpacing: 2)),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy, color: AppColors.primary),
                              onPressed: () => _copyToClipboard(code),
                            ),
                            Builder(
                              builder: (buttonContext) => IconButton(
                                icon: const Icon(Icons.share, color: AppColors.primary),
                                onPressed: () => _shareCode(buttonContext, code, r.referralAmount),
                              ),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: _statCard('Total Referred', r.totalReferred.toString(), Icons.people_rounded, AppColors.info)),
                      const SizedBox(width: 12),
                      Expanded(child: _statCard('Earned (Rs)', r.earnedAmount.toStringAsFixed(0), Icons.payments_rounded, AppColors.success)),
                      const SizedBox(width: 12),
                      Expanded(child: _statCard('Pending (Rs)', r.pendingAmount.toStringAsFixed(0), Icons.hourglass_top_rounded, AppColors.warning)),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text('Referral History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                  const SizedBox(height: 16),
                  if (r.friends.isEmpty)
                    const Center(child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Text('You haven\'t referred anyone yet. Share your code to start earning!', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                    )),
                  ...r.friends.map((friend) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(friend['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            Text(friend['phone'] ?? '', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('Rs. ${(friend['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.success)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: friend['status'] == 'completed' ? AppColors.success.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                (friend['status'] ?? 'pending').toString().toUpperCase(),
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: friend['status'] == 'completed' ? AppColors.success : AppColors.warning),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )).toList(),
                ],
              ),
            ),
          )
        ],
      ),
    );
    } catch (e, stack) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Scrollbar(
              child: SingleChildScrollView(
                child: SelectableText('Error inside EarnWithZiggoScreen build:\n\n$e\n\n$stack'),
              ),
            ),
          ),
        ),
      );
    }
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
            textAlign: TextAlign.center,
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
