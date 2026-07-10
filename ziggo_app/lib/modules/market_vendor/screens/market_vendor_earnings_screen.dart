import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/widgets/motion.dart';
import '../market_vendor_provider.dart';
import 'market_vendor_daily_report_screen.dart';


class MarketVendorEarningsScreen extends StatefulWidget {
  const MarketVendorEarningsScreen({super.key});

  @override
  State<MarketVendorEarningsScreen> createState() =>
      _MarketVendorEarningsScreenState();
}

class _MarketVendorEarningsScreenState extends State<MarketVendorEarningsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _week;
  Map<String, dynamic>? _month;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = context.read<MarketVendorProvider>();
    final w = await p.fetchEarnings(period: 'week');
    final m = await p.fetchEarnings(period: 'month');
    if (!mounted) return;
    setState(() {
      _week = w;
      _month = m;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _tabs.index == 0 ? _week : _month;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('Earnings',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.3)),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              boxShadow: AppStyles.shadowSm,
            ),
            child: TabBar(
              controller: _tabs,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(AppStyles.radiusMd),
              ),
              indicatorPadding: const EdgeInsets.all(4),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              dividerColor: Colors.transparent,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
                letterSpacing: 0.4,
              ),
              tabs: const [
                Tab(text: 'Last 7 days'),
                Tab(text: 'Last 30 days'),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : data == null
                    ? const Center(
                        child: Text("Couldn't load earnings",
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          children: staggered([
                            _HeaderCard(data: data),
                            const SizedBox(height: 16),
                            _BreakdownGrid(data: data),
                            const SizedBox(height: 18),
                            const _SectionTitle(text: 'Daily breakdown'),
                            _DailyChart(data: data),
                            const SizedBox(height: 14),
                            _DailyList(data: data),
                          ]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HeaderCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final revenue = (data['total_revenue'] as num? ?? 0).toDouble();
    final delivered = (data['total_delivered'] as num? ?? 0).toInt();
    final orders = (data['total_orders'] as num? ?? 0).toInt();
    final aov = (data['average_order_value'] as num? ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF14532D), Color(0xFF15803D), Color(0xFF22C55E)],
        ),
        borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        boxShadow: AppStyles.shadowLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(100),
            ),
            child: const Text(
              'NET REVENUE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Rs.${NumberFormat('#,##0').format(revenue.round())}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$delivered delivered • $orders orders • avg Rs.${NumberFormat('#,##0').format(aov.round())}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownGrid extends StatelessWidget {
  final Map<String, dynamic> data;
  const _BreakdownGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final cancelled = (data['total_cancelled'] as num? ?? 0).toInt();
    final delivered = (data['total_delivered'] as num? ?? 0).toInt();
    final orders = (data['total_orders'] as num? ?? 0).toInt();
    final completion =
        orders == 0 ? 0 : ((delivered / orders) * 100).round();

    return Row(
      children: [
        Expanded(
          child: _Stat(
            color: AppColors.success,
            icon: Icons.check_circle_rounded,
            label: 'COMPLETED',
            value: '$delivered',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Stat(
            color: AppColors.error,
            icon: Icons.cancel_rounded,
            label: 'CANCELLED',
            value: '$cancelled',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Stat(
            color: AppColors.primary,
            icon: Icons.bolt_rounded,
            label: 'COMPLETION',
            value: '$completion%',
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final String value;

  const _Stat({
    required this.color,
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              )),
          Text(label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              )),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 16,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DailyChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final days =
        (data['days'] as List? ?? []).cast<Map<String, dynamic>>();
    if (days.isEmpty) return const SizedBox.shrink();
    final maxRev = days
        .map((d) => (d['revenue'] as num? ?? 0).toDouble())
        .fold<double>(0, (a, b) => b > a ? b : a);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: SizedBox(
        height: 150,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in days)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _Bar(
                    value: (d['revenue'] as num? ?? 0).toDouble(),
                    maxValue: maxRev <= 0 ? 1 : maxRev,
                    label: _shortDay(d['date']?.toString() ?? ''),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _shortDay(String iso) {
    try {
      final d = DateTime.parse(iso);
      return DateFormat('E').format(d).substring(0, 1);
    } catch (_) {
      return '';
    }
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double maxValue;
  final String label;
  const _Bar(
      {required this.value, required this.maxValue, required this.label});

  @override
  Widget build(BuildContext context) {
    final pct = (value / maxValue).clamp(0.0, 1.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: FractionallySizedBox(
            alignment: Alignment.bottomCenter,
            heightFactor: value <= 0 ? 0.04 : pct,
            widthFactor: 1,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF22C55E), Color(0xFF15803D)],
                ),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.textTertiary,
              letterSpacing: 1,
            )),
      ],
    );
  }
}

class _DailyList extends StatelessWidget {
  final Map<String, dynamic> data;
  const _DailyList({required this.data});

  @override
  Widget build(BuildContext context) {
    final days = (data['days'] as List? ?? [])
        .cast<Map<String, dynamic>>()
        .reversed
        .toList();
    if (days.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: AppStyles.shadowSm,
      ),
      child: Column(
        children: [
          for (var i = 0; i < days.length; i++) ...[
            _DailyRow(day: days[i]),
            if (i != days.length - 1)
              const Divider(height: 1, indent: 16, endIndent: 16),
          ],
        ],
      ),
    );
  }
}

class _DailyRow extends StatelessWidget {
  final Map<String, dynamic> day;
  const _DailyRow({required this.day});

  @override
  Widget build(BuildContext context) {
    final iso = day['date']?.toString() ?? '';
    DateTime? parsed;
    try {
      parsed = DateTime.parse(iso);
    } catch (_) {}
    final dateLabel =
        parsed == null ? iso : DateFormat('EEE, MMM d').format(parsed);
    final delivered = (day['delivered'] as num? ?? 0).toInt();
    final orders = (day['orders'] as num? ?? 0).toInt();
    final revenue = (day['revenue'] as num? ?? 0).toDouble();

    return InkWell(
      onTap: () {
        if (iso.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MarketVendorDailyReportScreen(date: iso),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dateLabel,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14)),
                  Text(
                    '$delivered delivered • $orders total',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'Rs.${NumberFormat('#,##0').format(revenue.round())}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 18,
            ),
          ],
        ),
      ),
    );

  }
}
