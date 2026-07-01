import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/motion.dart';
import '../booking_provider.dart';
import 'ride_details_screen.dart';

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<BookingProvider>().fetchHistory();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = context.read<BookingProvider>().fetchHistory();
    });
    await _future;
  }

  ({Color color, IconData icon, String label}) _statusMeta(String s) {
    switch (s) {
      case 'completed':
        return (color: AppColors.success, icon: Icons.check_circle_rounded, label: 'Completed');
      case 'cancelled':
        return (color: AppColors.error, icon: Icons.cancel_rounded, label: 'Cancelled');
      case 'started':
      case 'arrived':
      case 'accepted':
        return (color: AppColors.warning, icon: Icons.directions_car_rounded, label: 'In progress');
      default:
        return (color: AppColors.textTertiary, icon: Icons.hourglass_top_rounded, label: 'Pending');
    }
  }

  IconData _vehicleIcon(String type) {
    switch (type) {
      case 'bike':
        return Icons.motorcycle_rounded;
      case 'tuk':
        return Icons.electric_rickshaw_rounded;
      case 'van':
        return Icons.airport_shuttle_rounded;
      case 'truck':
        return Icons.local_shipping_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final d = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(d);
    } catch (_) {
      if (dateStr.length >= 16) return dateStr.substring(0, 16);
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'Rs.', decimalDigits: 0);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text('My Trips'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (_, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final rides = snapshot.data ?? [];
            if (rides.isEmpty) return _empty();

            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              itemCount: rides.length,
              itemBuilder: (_, i) {
                final r = rides[i];
                final status = (r['status'] ?? '').toString();
                final meta = _statusMeta(status);
                final serviceType = (r['service_type'] ?? 'car').toString();
                return EntranceSlide(
                  delay: Duration(milliseconds: 45 * i),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RideDetailsScreen(rideData: r),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: meta.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(_vehicleIcon(serviceType), color: meta.color, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r['booking_ref']?.toString() ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                                  ),
                                  Text(
                                    _formatDate(r['booked_at']?.toString()),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textTertiary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: meta.color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(meta.icon, size: 12, color: meta.color),
                                  const SizedBox(width: 4),
                                  Text(
                                    meta.label,
                                    style: TextStyle(
                                      color: meta.color,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.divider),
                      // Locations
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _locationLine(
                              icon: Icons.my_location_rounded,
                              color: AppColors.flash,
                              text: r['pickup_address']?.toString() ?? '',
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 6, top: 4, bottom: 4),
                              child: Column(
                                children: List.generate(
                                  2,
                                  (_) => Container(
                                    margin: const EdgeInsets.only(bottom: 2),
                                    width: 2,
                                    height: 3,
                                    color: AppColors.divider,
                                  ),
                                ),
                              ),
                            ),
                            _locationLine(
                              icon: Icons.location_on_rounded,
                              color: AppColors.error,
                              text: r['drop_address']?.toString() ?? '',
                            ),
                          ],
                        ),
                      ),
                      // Footer
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(20),
                            bottomRight: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              serviceType.toUpperCase(),
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                                letterSpacing: 1,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              fmt.format((r['final_amount'] as num?)?.toDouble() ?? 0),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _locationLine({required IconData icon, required Color color, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Map<String, dynamic> r) {
    final startedStr = r['started_at']?.toString();
    final completedStr = r['completed_at']?.toString();
    if (startedStr != null && completedStr != null) {
      try {
        final started = DateTime.parse(startedStr);
        final completed = DateTime.parse(completedStr);
        final diff = completed.difference(started);
        final secs = diff.inMilliseconds / 1000.0;
        if (secs < 60) {
          return '${secs.toStringAsFixed(2)}s';
        } else {
          final mins = secs / 60.0;
          return '${mins.toStringAsFixed(2)} min';
        }
      } catch (_) {}
    }
    final durationMinRaw = r['duration_min'];
    if (durationMinRaw != null) {
      final val = (durationMinRaw is num) ? durationMinRaw.toDouble() : double.tryParse(durationMinRaw.toString());
      if (val != null) {
        if (val > 300) {
          // If value is > 300, it's almost certainly in seconds from the backend
          return '${(val / 60).round()} min';
        }
        return '${val.round()} min';
      }
    }
    return '0 min';
  }

  String _formatDistance(Map<String, dynamic> r) {
    final raw = r['distance_km'];
    final dist = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
    if (dist != null) {
      return '${dist.toStringAsFixed(2)} km';
    }
    return '0.00 km';
  }

  Widget _breakdownRow(String label, String value, {bool isNegative = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          Text(
            isNegative ? '-$value' : value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
              color: isNegative
                  ? AppColors.error
                  : (isBold ? AppColors.success : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return ListView(
      children: [
        const SizedBox(height: 140),
        Center(
          child: Column(
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(Icons.history_rounded,
                    size: 44, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 18),
              const Text('No trips yet',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 4),
              const Text('Book a ride to see it here',
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}
