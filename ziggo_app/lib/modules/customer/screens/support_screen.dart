import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/motion.dart';
import 'support_chat_screen.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, this.isDriver = false});

  final bool isDriver;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final List<Map<String, dynamic>> _categories = [
    widget.isDriver
        ? {'value': 'passenger_behavior', 'label': 'Passenger behavior', 'icon': Icons.person_off_rounded, 'color': AppColors.error}
        : {'value': 'driver_behavior', 'label': 'Driver behavior', 'icon': Icons.person_off_rounded, 'color': AppColors.error},
    {'value': 'fare_issue', 'label': 'Fare / billing', 'icon': Icons.payments_rounded, 'color': AppColors.warning},
    {'value': 'safety', 'label': 'Safety concern', 'icon': Icons.shield_rounded, 'color': AppColors.flash},
    {'value': 'technical', 'label': 'Technical issue', 'icon': Icons.bug_report_rounded, 'color': AppColors.bike},
    {'value': 'other', 'label': 'Other', 'icon': Icons.help_rounded, 'color': AppColors.textSecondary},
  ];

  String _category = 'other';
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _busy = false;

  List<Map<String, dynamic>> _myComplaints = [];

  @override
  void initState() {
    super.initState();
    _loadMine();
  }

  @override
  void dispose() {
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

  Future<void> _submit() async {
    if (_subjectCtrl.text.trim().isEmpty || _descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fill in subject and description'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ApiClient.instance.dio.post('/complaints', data: {
        'category': _category,
        'subject': _subjectCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
      });
      if (!mounted) return;
      _subjectCtrl.clear();
      _descCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Complaint submitted'),
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
          content: Text(e.response?.data?['detail']?.toString() ?? 'Failed'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ({Color color, String label}) _statusMeta(String s) {
    switch (s) {
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
        title: const Text('Support'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
        children: staggered([
          // Help banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: AppColors.blackGradient,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.support_agent_rounded,
                      color: Colors.black, size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'How can we help?',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tell us what happened, we\'ll respond fast.',
                        style: TextStyle(
                          color: Colors.white60,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'PICK A CATEGORY',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
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
                    color: selected ? Colors.black : Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: selected ? Colors.black : AppColors.cardBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        c['icon'] as IconData,
                        color: selected ? color : color,
                        size: 16,
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
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                TextField(
                  controller: _subjectCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _descCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Describe the issue',
                    alignLabelWithHint: true,
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
            onPressed: _submit,
          ),
          const SizedBox(height: 30),
          Row(
            children: [
              const Text(
                'My reports',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              const Spacer(),
              if (_myComplaints.isNotEmpty)
                Text(
                  '${_myComplaints.length}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
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
                      child: const Icon(Icons.inbox_rounded,
                          color: AppColors.textTertiary, size: 28),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'No reports yet',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._myComplaints.map((c) {
              final meta = _statusMeta(c['status']?.toString() ?? 'pending');
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
                      // refresh list when returning — status may have changed
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
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                (c['category'] ?? '').toString().replaceAll('_', ' ').toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
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
                          const SizedBox(height: 6),
                          Text(
                            c['description']?.toString() ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
        ]),
      ),
    );
  }
}
