import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';

/// Screen displaying the official Ziggo Privacy Policy and Terms of Service.
/// Fulfills TC_ZIG_SUP_003 (ZIG-SUP-03 / BUG-010) requirements.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({
    super.key,
    this.initialTab = 'privacy',
  });

  /// 'privacy' or 'terms'
  final String initialTab;

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  late String _currentTab;
  int _selectedFilterIndex = 0;

  final List<String> _privacyFilters = [
    'All',
    'Collection',
    'Usage',
    'Sharing',
    'Your Rights',
    'Retention',
    'Security',
    'Contact',
  ];

  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab == 'terms' ? 'terms' : 'privacy';
  }

  Future<void> _launchEmail(String email, String subject) async {
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {'subject': subject},
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _showCopySnackBar('Email address: $email');
      }
    } catch (_) {
      _showCopySnackBar('Email address: $email');
    }
  }

  Future<void> _launchWeb(String url) async {
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showCopySnackBar('Visit: $url');
      }
    } catch (_) {
      _showCopySnackBar('Visit: $url');
    }
  }

  void _showCopySnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.primaryDark,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: Text(
          _currentTab == 'privacy' ? 'Privacy Policy' : 'Terms of Service',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded, color: AppColors.primary),
            tooltip: 'Open in web browser',
            onPressed: () => _launchWeb(
              _currentTab == 'privacy'
                  ? 'https://ziggo.lk/pages/privacy'
                  : 'https://ziggo.lk/pages/terms',
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 36),
        children: [
          // ── Hero Banner ──────────────────────────────────────────────────
          EntranceSlide(
            child: _buildHeroCard(),
          ),
          const SizedBox(height: 18),

          // ── Tab Selector (Privacy Policy vs Terms of Service) ────────────
          EntranceSlide(
            delay: const Duration(milliseconds: 60),
            child: _buildTabSelector(),
          ),
          const SizedBox(height: 18),

          // ── Topic Filter Chips (for Privacy Policy) ──────────────────────
          if (_currentTab == 'privacy') ...[
            EntranceSlide(
              delay: const Duration(milliseconds: 100),
              child: _buildFilterChips(),
            ),
            const SizedBox(height: 16),
            ..._buildPrivacyContent(),
          ] else ...[
            ..._buildTermsContent(),
          ],

          const SizedBox(height: 24),

          // ── Contact / Action Card ─────────────────────────────────────────
          EntranceSlide(
            delay: const Duration(milliseconds: 200),
            child: _buildContactCard(),
          ),
          const SizedBox(height: 20),

          // ── Footer Copyright ──────────────────────────────────────────────
          const Center(
            child: Text(
              '© 2026 Ziggo Lanka (Pvt) Ltd • All Rights Reserved',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Card ─────────────────────────────────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.25)),
            ),
            child: Icon(
              _currentTab == 'privacy'
                  ? Icons.shield_rounded
                  : Icons.gavel_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Text(
                    'ZIGGO LEGAL & TRUST',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _currentTab == 'privacy'
                      ? 'Your Privacy & Data Protection'
                      : 'Terms of Service',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currentTab == 'privacy'
                      ? 'Last updated: May 1, 2026 • Sri Lanka PDPA Compliant'
                      : 'Last updated: September 1, 2026 • Colombo Jurisdiction',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab Selector ──────────────────────────────────────────────────────────
  Widget _buildTabSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              title: 'Privacy Policy',
              icon: Icons.lock_outline_rounded,
              isActive: _currentTab == 'privacy',
              onTap: () {
                setState(() {
                  _currentTab = 'privacy';
                  _selectedFilterIndex = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _tabButton(
              title: 'Terms of Service',
              icon: Icons.description_outlined,
              isActive: _currentTab == 'terms',
              onTap: () {
                setState(() {
                  _currentTab = 'terms';
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Colors.white : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: isActive ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Filter Chips ──────────────────────────────────────────────────────────
  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: List.generate(_privacyFilters.length, (index) {
          final isSelected = _selectedFilterIndex == index;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                _privacyFilters[index],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
              selected: isSelected,
              selectedColor: AppColors.primary,
              backgroundColor: Colors.white,
              elevation: isSelected ? 2 : 0,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.cardBorder,
                ),
              ),
              onSelected: (val) {
                if (val) {
                  setState(() => _selectedFilterIndex = index);
                }
              },
            ),
          );
        }),
      ),
    );
  }

  // ── Privacy Content ───────────────────────────────────────────────────────
  List<Widget> _buildPrivacyContent() {
    final showAll = _selectedFilterIndex == 0;

    return [
      if (showAll || _selectedFilterIndex == 1)
        _buildSectionCard(
          badge: 'OVERVIEW',
          badgeColor: AppColors.primary,
          title: 'Introduction & Scope',
          icon: Icons.info_outline_rounded,
          content: [
            'Ziggo Lanka (Pvt) Ltd ("Ziggo", "we", "us") respects your privacy. '
            'This Privacy Policy explains what personal data we collect, why we collect it, how it is handled, '
            'and the rights you have over your data in accordance with Sri Lanka’s Personal Data Protection Act (PDPA No. 9 of 2022).',
            'By using the Ziggo application or accessing our on-demand services (Rides, Food, Flash Parcels, Mart & Logistics), '
            'you acknowledge the practices detailed in this policy.',
          ],
        ),

      if (showAll || _selectedFilterIndex == 1)
        _buildSectionCard(
          badge: 'SECTION 1',
          badgeColor: AppColors.info,
          title: '1. Information We Collect',
          icon: Icons.storage_rounded,
          subsections: [
            _SubItem(
              title: 'Information You Provide Us',
              body:
                  '• Name, mobile number (+94), email address, and date of birth upon account registration.\n'
                  '• Payment credentials (handled strictly through PCI-DSS Level 1 compliant gateways; Ziggo never stores full card numbers or CVV).\n'
                  '• National Identity Card (NIC), driving licence, and vehicle registration documents for driver and partner accounts.\n'
                  '• Emergency contacts and delivery address nicknames (Home, Work, Favourites).',
            ),
            _SubItem(
              title: 'Information Collected Automatically',
              body:
                  '• Precise GPS Location: Collected while the app is active in the foreground or during an active ride/delivery dispatch to enable driver matching, navigation, and fare calculation.\n'
                  '• Trip and Order History: Pick-up and drop-off coordinates, routes traversed, timestamps, distance, and payment breakdown.\n'
                  '• Device and Telemetry: Device model, operating system version, IP address, carrier network, and unique app installation identifiers.',
            ),
          ],
        ),

      if (showAll || _selectedFilterIndex == 2)
        _buildSectionCard(
          badge: 'SECTION 2',
          badgeColor: AppColors.success,
          title: '2. How We Use Your Information',
          icon: Icons.psychology_rounded,
          content: [
            'We use personal information exclusively to deliver safe, transparent, and efficient super-app services:',
            '• To match you with nearby drivers, couriers, and partner restaurants.\n'
            '• To calculate fair and upfront fare estimates based on distance, time, and active surge zones.\n'
            '• To process authorized digital and cash payments, top-ups, and customer refunds.\n'
            '• To verify identity, conduct driver background checks, and prevent fraudulent activity.\n'
            '• To enable real-time safety tracking, including the in-app SOS emergency broadcast feature.\n'
            '• To send critical service receipts, driver arrival alerts, and customer support responses.',
          ],
        ),

      if (showAll || _selectedFilterIndex == 3)
        _buildSectionCard(
          badge: 'SECTION 3',
          badgeColor: AppColors.warning,
          title: '3. Sharing Your Information',
          icon: Icons.share_rounded,
          content: [
            'We share only what is strictly necessary to complete your requested services:',
            '• With Drivers & Couriers: Your first name, pickup location, drop-off location, and masked in-app call/chat.\n'
            '• With Merchants & Restaurants: Your delivery address and order specifications.\n'
            '• With Licensed Payment Processors: Transaction amounts, tokenized card tokens, and currency identifiers.\n'
            '• Regulatory & Law Enforcement: When mandated by applicable Sri Lankan court orders or emergency safety requirements.',
            'Strict No-Sale Policy: Ziggo does NOT sell, rent, monetize, or trade your personal data to third-party advertisers or brokers under any circumstance.',
          ],
        ),

      if (showAll || _selectedFilterIndex == 4)
        _buildSectionCard(
          badge: 'SECTION 4',
          badgeColor: AppColors.accent,
          title: '4. Your Rights & Account Controls',
          icon: Icons.admin_panel_settings_rounded,
          content: [
            'Under Sri Lanka’s data privacy framework and global standards, you retain comprehensive control:',
            '• In-App Access: Review personal data, trip histories, and payment methods directly via your Profile.\n'
            '• Data Rectification: Update your name, emergency contacts, or phone number in Edit Profile.\n'
            '• Account Deletion: Request permanent account and credential deletion at any time via Profile > Additional Settings > Delete my account.\n'
            '• Machine-Readable Export: Request a copy of your personal data archive by contacting privacy@ziggo.lk.\n'
            '• Marketing Opt-Out: Disable promotional alerts anytime while retaining transactional receipts.',
          ],
        ),

      if (showAll || _selectedFilterIndex == 5)
        _buildSectionCard(
          badge: 'SECTION 5',
          badgeColor: const Color(0xFF8B5CF6),
          title: '5. Data Retention Periods',
          icon: Icons.hourglass_top_rounded,
          content: [
            '• Trip & Financial Records: Retained for 7 years to comply with Sri Lanka Inland Revenue Department (IRD) taxation and consumer protection statutory mandates.\n'
            '• Account Identification Documents: Retained for the active duration of the partner relationship plus 2 years for regulatory audit compliance.\n'
            '• Temporary Telemetry & GPS Pings: High-resolution route GPS pings are aggregated and depersonalized within 90 days of trip completion.',
          ],
        ),

      if (showAll || _selectedFilterIndex == 6)
        _buildSectionCard(
          badge: 'SECTION 6',
          badgeColor: AppColors.flash,
          title: '6. Security & Safeguards',
          icon: Icons.security_rounded,
          content: [
            '• Industry-Standard Encryption: TLS 1.2+ for all data in transit across mobile clients and servers; AES-256 encryption for data at rest.\n'
            '• Access Governance: Strict role-based permissions; support staff only access records required to resolve explicit complaints.\n'
            '• Incident Notification: In the unlikely event of a security breach affecting your personal data, Ziggo will notify affected users within 72 hours.',
          ],
        ),

      if (showAll || _selectedFilterIndex == 0)
        _buildSectionCard(
          badge: 'SECTION 7',
          badgeColor: AppColors.textSecondary,
          title: '7. Children’s Privacy',
          icon: Icons.family_restroom_rounded,
          content: [
            'Ziggo is strictly intended for individuals aged 16 and above. We do not knowingly collect personal information from individuals under 16. '
            'If we discover that a minor under 16 has created an unauthorized account, the account and associated records will be deleted promptly.',
          ],
        ),

      if (showAll || _selectedFilterIndex == 7)
        _buildSectionCard(
          badge: 'SECTION 8',
          badgeColor: AppColors.primary,
          title: '8. Data Protection Officer & Contact',
          icon: Icons.contact_support_rounded,
          content: [
            'For data privacy inquiries, formal requests, or regulatory filings, reach out directly to our Data Protection Officer (DPO):',
            '• Email: privacy@ziggo.lk\n'
            '• Security Desk: security@ziggo.lk\n'
            '• Postal Address: Ziggo Lanka (Pvt) Ltd, #75/30, Abdul Hameed Street, Colombo - 12, Sri Lanka.',
          ],
        ),
    ];
  }

  // ── Terms of Service Content ──────────────────────────────────────────────
  List<Widget> _buildTermsContent() {
    return [
      _buildSectionCard(
        badge: 'AGREEMENT',
        badgeColor: AppColors.primary,
        title: 'Terms of Service Overview',
        icon: Icons.gavel_rounded,
        content: [
          'Welcome to Ziggo, an on-demand ride, food delivery, and logistics platform operated by Ziggo Lanka (Pvt) Ltd. '
          'These Terms govern your use of the Ziggo mobile application, web portals, and services.',
          'Ziggo acts as the direct service provider and merchant of record for all transactions processed through our platform.',
        ],
      ),
      _buildSectionCard(
        badge: 'SECTION 1',
        badgeColor: AppColors.info,
        title: '1. Eligibility & User Identity',
        icon: Icons.verified_user_rounded,
        content: [
          '• Riders must be at least 16 years of age.\n'
          '• Drivers and delivery partners must be at least 21 years of age with a valid Sri Lankan commercial driving license.\n'
          '• You must use your verified identity and genuine mobile telephone number.',
        ],
      ),
      _buildSectionCard(
        badge: 'SECTION 2',
        badgeColor: AppColors.warning,
        title: '2. Account Responsibilities',
        icon: Icons.key_rounded,
        content: [
          '• You are responsible for safeguarding your OTP credentials and all activities occurring on your account.\n'
          '• Notify security@ziggo.lk immediately if you suspect unauthorized access or device loss.',
        ],
      ),
      _buildSectionCard(
        badge: 'SECTION 3',
        badgeColor: AppColors.error,
        title: '3. Platform Code of Conduct',
        icon: Icons.report_problem_rounded,
        content: [
          '• Zero Tolerance: Harassment, hate speech, threats, and discrimination against riders or drivers are strictly prohibited.\n'
          '• Prohibited Items: Smoking, alcohol, narcotics, weapons, and hazardous goods are forbidden in all vehicles.\n'
          '• Platform Integrity: Any attempt to reverse engineer, scrape, or falsify GPS coordinates will trigger immediate account suspension.',
        ],
      ),
      _buildSectionCard(
        badge: 'SECTION 4',
        badgeColor: AppColors.success,
        title: '4. Fares, Payments & Refunds',
        icon: Icons.payments_rounded,
        content: [
          '• Upfront Fare Transparency: Fares are displayed prior to booking confirmation.\n'
          '• Merchant of Record: Ziggo Lanka (Pvt) Ltd processes and settles all payments.\n'
          '• Cancellation Policy: Free cancellation within the 3-minute grace window. Subsequent cancellations may incur a nominal compensation fee for the driver.\n'
          '• Refund Processing: Billing inquiries and fare overcharge disputes are reviewed and settled via Help & Support within 24 hours.',
        ],
      ),
      _buildSectionCard(
        badge: 'SECTION 5',
        badgeColor: AppColors.primaryDark,
        title: '5. Governing Law & Dispute Resolution',
        icon: Icons.account_balance_rounded,
        content: [
          'These Terms are governed by and construed in accordance with the laws of the Democratic Socialist Republic of Sri Lanka. '
          'Disputes arising out of or in connection with these terms shall be subject to the exclusive jurisdiction of the competent courts of Colombo.',
        ],
      ),
    ];
  }

  // ── Section Card Widget ───────────────────────────────────────────────────
  Widget _buildSectionCard({
    required String badge,
    required Color badgeColor,
    required String title,
    required IconData icon,
    List<String>? content,
    List<_SubItem>? subsections,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: badgeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badge,
                        style: TextStyle(
                          color: badgeColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (content != null)
            ...content.map((p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    p,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.55,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )),
          if (subsections != null)
            ...subsections.map((sub) => Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sub.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sub.body,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  // ── Contact / Action Card ─────────────────────────────────────────────────
  Widget _buildContactCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        boxShadow: AppStyles.shadowMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mark_email_read_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Have a Privacy Question?',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Our Data Protection Officer is ready to assist',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _launchEmail(
                    _currentTab == 'privacy' ? 'privacy@ziggo.lk' : 'legal@ziggo.lk',
                    'Privacy Policy Inquiry - Ziggo App',
                  ),
                  icon: const Icon(Icons.email_outlined, size: 16),
                  label: const Text(
                    'Email DPO',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _launchWeb(
                    _currentTab == 'privacy'
                        ? 'https://ziggo.lk/pages/privacy'
                        : 'https://ziggo.lk/pages/terms',
                  ),
                  icon: const Icon(Icons.language_rounded, size: 16),
                  label: const Text(
                    'Online Version',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SubItem {
  final String title;
  final String body;

  const _SubItem({required this.title, required this.body});
}
