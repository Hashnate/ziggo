import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import '../../common/screens/privacy_policy_screen.dart';
import 'support_chat_screen.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.isDriver = false, this.bookingId});

  final bool isDriver;
  final int? bookingId;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  // ── FAQ Knowledge Base Data ───────────────────────────────────────────────
  final List<Map<String, dynamic>> _faqItems = [
    {
      'title': 'Fare & Overcharging Disputes',
      'icon': Icons.payments_rounded,
      'color': AppColors.warning,
      'content':
          'Fares are calculated using base fare, distance, time, and active surge zones. '
          'If you were charged more than the upfront estimate due to driver route deviation, '
          'unnecessary detours, or off-meter cash demands, select "Fare / Billing" below. '
          'Attach your trip receipt or screenshot and our billing team will review and refund any excess charges.',
    },
    {
      'title': 'Reporting Lost Property in a Vehicle',
      'icon': Icons.luggage_rounded,
      'color': const Color(0xFF8B5CF6),
      'content':
          'Left a phone, bag, wallet, or other belongings behind? '
          'Select "Lost & Found" below with your Booking ID and a description of the item. '
          'Our safety and driver dispatch team will immediately coordinate with your driver to arrange a secure return or drop-off.',
    },
    {
      'title': 'Driver Cancellation & No-Show Policy',
      'icon': Icons.cancel_outlined,
      'color': AppColors.error,
      'content':
          'Drivers are granted a 5-minute arrival window upon reaching your pickup point. '
          'If a driver canceled without arriving, marked arrived from a distance, or demanded a cancellation, '
          'any cancellation fee will be credited back to your Ziggo wallet upon submitting a report under "Driver Behavior".',
    },
    {
      'title': 'Safety Concerns & Emergency Escalation',
      'icon': Icons.shield_rounded,
      'color': AppColors.flash,
      'content':
          'Your safety is our utmost priority. During an active ride, please use the in-app SOS button '
          'to immediately broadcast your GPS coordinates to our safety command and your emergency contacts. '
          'For post-trip safety reports, submit under "Safety" for top-priority escalation to our dedicated safety response desk.',
    },
    {
      'title': 'Ziggo Gold & Promo Code Inquiries',
      'icon': Icons.stars_rounded,
      'color': const Color(0xFFF59E0B),
      'content':
          'Ziggo Gold subscribers receive priority matching, discounted surge multipliers, and dedicated VIP support. '
          'Promo voucher codes must be entered on the fare estimate screen before confirming your ride. '
          'If a valid promo failed to apply, report under "Fare / Billing" with the promo code name.',
    },
  ];

  int? _expandedFaqIndex;

  // ── Categories / Topic Pills ──────────────────────────────────────────────
  late final List<Map<String, dynamic>> _categories = [
    widget.isDriver
        ? {
            'value': 'passenger_behavior',
            'label': 'Passenger Behavior',
            'icon': Icons.person_off_rounded,
            'color': AppColors.error
          }
        : {
            'value': 'driver_behavior',
            'label': 'Driver Behavior',
            'icon': Icons.person_off_rounded,
            'color': AppColors.error
          },
    {
      'value': 'fare_issue',
      'label': 'Fare / Billing',
      'icon': Icons.payments_rounded,
      'color': AppColors.warning
    },
    {
      'value': 'safety',
      'label': 'Safety',
      'icon': Icons.shield_rounded,
      'color': AppColors.flash
    },
    {
      'value': 'lost_found',
      'label': 'Lost & Found',
      'icon': Icons.luggage_rounded,
      'color': const Color(0xFF8B5CF6)
    },
    {
      'value': 'technical',
      'label': 'App Issue',
      'icon': Icons.bug_report_rounded,
      'color': AppColors.bike
    },
    {
      'value': 'other',
      'label': 'Other',
      'icon': Icons.help_outline_rounded,
      'color': AppColors.textSecondary
    },
  ];

  String _category = 'fare_issue';
  final _bookingIdCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  XFile? _selectedImage;
  bool _busy = false;

  List<Map<String, dynamic>> _myComplaints = [];

  @override
  void initState() {
    super.initState();
    if (widget.bookingId != null) {
      _bookingIdCtrl.text = widget.bookingId.toString();
    }
    _loadMine();
  }

  @override
  void dispose() {
    _bookingIdCtrl.dispose();
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMine() async {
    try {
      final resp = await ApiClient.instance.dio.get('/complaints');
      if (mounted) {
        setState(() => _myComplaints = List<Map<String, dynamic>>.from(resp.data as List));
      }
    } on DioException {
      // ignore
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final img = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (img != null && mounted) {
        setState(() => _selectedImage = img);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showImagePickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.cardBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Attach Photo or Screenshot',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                ),
                title: const Text('Choose from Gallery', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                ),
                title: const Text('Take a Photo', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final subject = _subjectCtrl.text.trim();
    final desc = _descCtrl.text.trim();

    if (subject.isEmpty || desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in both subject and description'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _busy = true);

    String? uploadedUrl;
    try {
      // 1. Upload screenshot attachment if selected
      if (_selectedImage != null) {
        final fileName = _selectedImage!.name;
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            _selectedImage!.path,
            filename: fileName,
          ),
        });

        final uploadResp = await ApiClient.instance.dio.post(
          '/complaints/upload',
          data: formData,
        );
        if (uploadResp.data != null && uploadResp.data['attachment_url'] != null) {
          uploadedUrl = uploadResp.data['attachment_url'] as String?;
        }
      }

      // 2. Parse optional booking ID
      int? bookingId;
      final rawBooking = _bookingIdCtrl.text.trim();
      if (rawBooking.isNotEmpty) {
        bookingId = int.tryParse(rawBooking);
      }

      // 3. Post complaint payload
      final payload = <String, dynamic>{
        'category': _category,
        'subject': subject,
        'description': desc,
        if (bookingId != null) 'booking_id': bookingId,
        if (uploadedUrl != null) 'attachment_url': uploadedUrl,
      };

      await ApiClient.instance.dio.post('/complaints', data: payload);

      if (!mounted) return;
      _subjectCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _selectedImage = null;
        if (widget.bookingId == null) {
          _bookingIdCtrl.clear();
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Report submitted successfully'),
            ],
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadMine();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.response?.data?['detail']?.toString() ?? 'Submission failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ({Color color, String label}) _statusMeta(String s) {
    switch (s.toLowerCase()) {
      case 'resolved':
        return (color: AppColors.success, label: 'Resolved');
      case 'in_progress':
        return (color: AppColors.flash, label: 'In progress');
      case 'closed':
        return (color: AppColors.textTertiary, label: 'Closed');
      default:
        return (color: AppColors.warning, label: 'Pending');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Help & Support',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: staggered([
          // ── SECTION 1: Interactive FAQ & Knowledge Base (Self-Help Accordion) ──
          _buildFaqSection(),

          const SizedBox(height: 28),

          // ── SECTION 2: Enhanced Report Form with Image Attachments ─────────────
          _buildReportFormSection(),

          const SizedBox(height: 32),

          // ── SECTION 3: My Reports & Chat History ───────────────────────────────
          _buildMyReportsSection(),

          const SizedBox(height: 32),

          // ── SECTION 4: Legal & Policies ────────────────────────────────────────
          _buildLegalSection(),
        ]),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 1: FAQ ACCORDION
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildFaqSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.help_outline_rounded, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Frequently Asked Questions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Instant answers before submitting a ticket',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...List.generate(_faqItems.length, (index) {
          final item = _faqItems[index];
          final isExpanded = _expandedFaqIndex == index;
          final color = item['color'] as Color;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isExpanded ? AppColors.primary.withOpacity(0.5) : AppColors.cardBorder,
                width: isExpanded ? 1.5 : 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    _expandedFaqIndex = isExpanded ? null : index;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(item['icon'] as IconData, size: 18, color: color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item['title'] as String,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          AnimatedRotation(
                            duration: const Duration(milliseconds: 200),
                            turns: isExpanded ? 0.5 : 0,
                            child: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: AppColors.textTertiary,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 200),
                        crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                        firstChild: const SizedBox(width: double.infinity),
                        secondChild: Padding(
                          padding: const EdgeInsets.only(top: 10, left: 41, right: 4),
                          child: Text(
                            item['content'] as String,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 2: ENHANCED REPORT FORM WITH IMAGE ATTACHMENTS
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildReportFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.rate_review_outlined, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Submit a Report',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'Need assistance? Select a topic and tell us what happened',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Topic Pills Wrap
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'SELECT TOPIC',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _categories.map((c) {
            final selected = _category == c['value'];
            final color = c['color'] as Color;
            return GestureDetector(
              onTap: () => setState(() => _category = c['value'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : Colors.white,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: selected ? AppColors.primary : AppColors.cardBorder,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      c['icon'] as IconData,
                      color: selected ? Colors.white : color,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c['label'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        color: selected ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        // Text input card (Booking ID, Subject, Description, Attachment)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Optional Booking ID Input
              TextField(
                controller: _bookingIdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Booking ID (Optional)',
                  hintText: 'e.g. 1042',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
              ),
              const SizedBox(height: 12),

              // Subject Input
              TextField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  hintText: 'Brief summary of the issue',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
              ),
              const SizedBox(height: 12),

              // Description Input
              TextField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Describe the issue',
                  hintText: 'Provide details to help us investigate quickly…',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),

              // Screenshot / Photo Upload Widget
              const Text(
                'ATTACH SCREENSHOT / PHOTO',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),

              if (_selectedImage == null)
                GestureDetector(
                  onTap: _showImagePickerSheet,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.cardBorder,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Add Photo or Screenshot',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          '(Max 5MB)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_selectedImage!.path),
                          width: 54,
                          height: 54,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedImage!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            const Row(
                              children: [
                                Icon(Icons.check_circle_rounded, color: AppColors.success, size: 14),
                                SizedBox(width: 4),
                                Text(
                                  'Ready to upload',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
                        onPressed: () => setState(() => _selectedImage = null),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        PrimaryButton(
          label: 'SUBMIT REPORT',
          icon: Icons.send_rounded,
          busy: _busy,
          gold: true,
          onPressed: _submit,
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 3: MY REPORTS & CHAT HISTORY
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildMyReportsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'My reports',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(width: 8),
            if (_myComplaints.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '${_myComplaints.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        if (_myComplaints.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.inbox_rounded, color: AppColors.textTertiary, size: 28),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'No reports yet',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Submitted tickets will appear here for live chat & tracking',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ..._myComplaints.map((c) {
            final meta = _statusMeta(c['status']?.toString() ?? 'pending');
            final bookingId = c['booking_id'];
            final attachmentUrl = c['attachment_url']?.toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SupportChatScreen(ticket: c),
                      ),
                    );
                    _loadMine();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Subject & Status
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c['subject']?.toString() ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: meta.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Text(
                                meta.label,
                                style: TextStyle(
                                  color: meta.color,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Badges: Category & Booking ID
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                (c['category'] ?? '').toString().replaceAll('_', ' ').toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            if (bookingId != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.confirmation_number_outlined,
                                        size: 11, color: AppColors.primary),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Ride #$bookingId',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const Spacer(),
                            const Icon(Icons.chat_bubble_outline_rounded,
                                size: 14, color: AppColors.textTertiary),
                            const SizedBox(width: 4),
                            const Text(
                              'Open chat',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // Description snippet & thumbnail preview if attachment exists
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (attachmentUrl != null && attachmentUrl.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  attachmentUrl.startsWith('http')
                                      ? attachmentUrl
                                      : '${ApiConfig.baseHost}$attachmentUrl',
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceMuted,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.image_not_supported_rounded,
                                        size: 18, color: AppColors.textTertiary),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Text(
                                c['description']?.toString() ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // SECTION 4: LEGAL & PRIVACY POLICIES
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildLegalSection() {
    return Container(
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
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.policy_outlined, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Legal & Privacy Policies',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Review how your personal data and rights are protected',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(initialTab: 'privacy'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.shield_outlined, size: 16),
                  label: const Text('Privacy Policy', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.cardBorder),
                    backgroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(initialTab: 'terms'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.gavel_outlined, size: 16),
                  label: const Text('Terms of Service', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.cardBorder),
                    backgroundColor: AppColors.background,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

