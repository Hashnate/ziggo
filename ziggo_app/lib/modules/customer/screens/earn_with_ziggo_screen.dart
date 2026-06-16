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
      body: Center(
        child: Text('Code: $code', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
