import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';

class DriverRideDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> rideData;

  const DriverRideDetailsScreen({super.key, required this.rideData});

  IconData _vehicleIcon(String type) {
    switch (type.toLowerCase()) {
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
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy, hh:mm a').format(date);
    } catch (_) {
      if (dateStr.length >= 16) return dateStr.substring(0, 16);
      return dateStr;
    }
  }

  String _formatTimeOnly(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('hh:mm a').format(date);
    } catch (_) {
      return '';
    }
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
          return '${secs.toStringAsFixed(0)}s';
        } else {
          final mins = secs / 60.0;
          return '${mins.toStringAsFixed(0)}m';
        }
      } catch (_) {}
    }
    final durationMinRaw = r['duration_min'];
    if (durationMinRaw != null) {
      final val = (durationMinRaw is num) ? durationMinRaw.toDouble() : double.tryParse(durationMinRaw.toString());
      if (val != null) {
        if (val > 300) {
          return '${(val / 60).round()}m';
        }
        return '${val.round()}m';
      }
    }
    return '0m';
  }

  String _formatDistance(Map<String, dynamic> r) {
    final raw = r['distance_km'];
    final dist = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
    if (dist != null) {
      return '${dist.toStringAsFixed(1)} km';
    }
    return '0 km';
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
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? Colors.black87 : Colors.black54,
            ),
          ),
          Text(
            isNegative ? '-$value' : value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isNegative
                  ? Colors.red
                  : (isBold ? Colors.green.shade700 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2);
    final bookingRef = rideData['booking_ref']?.toString() ?? rideData['id']?.toString() ?? 'Unknown';
    final serviceType = (rideData['service_type'] ?? 'car').toString();
    final status = (rideData['status'] ?? '').toString();

    // In Driver view, we show Customer Details in the profile card
    final customerName = rideData['customer_name']?.toString() ?? 'Customer';
    final customerPhone = rideData['customer_phone']?.toString() ?? 'N/A';
    
    // Check if customer_photo is available, otherwise use a placeholder
    String? customerPhoto = rideData['customer_photo']?.toString();
    if (customerPhoto != null && customerPhoto.isNotEmpty && customerPhoto.startsWith('/')) {
      customerPhoto = '${ApiConfig.baseHost}$customerPhoto';
    }

    final pickup = rideData['pickup_address']?.toString() ?? '';
    final drop = rideData['drop_address']?.toString() ?? '';
    final bookedAt = rideData['booked_at']?.toString();

    // For Driver, the highlight is Net Driver Earnings
    final driverEarnings = (rideData['driver_earnings'] as num?)?.toDouble() ?? (rideData['final_amount'] as num?)?.toDouble() ?? 0.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Trip Summary', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- FARE & STATUS HEADER ---
            Column(
              children: [
                const Text('NET EARNINGS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1.2)),
                const SizedBox(height: 4),
                Text(
                  fmt.format(driverEarnings),
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Colors.black, letterSpacing: -1),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: status.toLowerCase() == 'completed' ? Colors.green : Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${status.toUpperCase()} • ${_formatDate(bookedAt)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // --- LOCATIONS CARD ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4)),
                ],
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      const SizedBox(height: 4),
                      Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)),
                      Container(width: 2, height: 40, color: Colors.grey.shade200, margin: const EdgeInsets.symmetric(vertical: 4)),
                      Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.orange, width: 3))),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pickup, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text(_formatTimeOnly(rideData['started_at']?.toString() ?? bookedAt), style: const TextStyle(fontSize: 13, color: Colors.black45)),
                        const SizedBox(height: 16),
                        Text(drop, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text(_formatTimeOnly(rideData['completed_at']?.toString()), style: const TextStyle(fontSize: 13, color: Colors.black45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --- CUSTOMER PROFILE CARD ---
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4)),
                ],
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.grey.shade100,
                    backgroundImage: customerPhoto != null && customerPhoto.isNotEmpty ? NetworkImage(customerPhoto) : null,
                    child: customerPhoto == null || customerPhoto.isEmpty ? const Icon(Icons.person, color: Colors.black26, size: 28) : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customerName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.phone, color: Colors.blueGrey, size: 14),
                            const SizedBox(width: 4),
                            Text(customerPhone, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black54)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      children: [
                        Icon(_vehicleIcon(serviceType), size: 24, color: Colors.black54),
                        if (serviceType.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${serviceType[0].toUpperCase()}${serviceType.substring(1)}',
                            style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                          ),
                        ]
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // --- TRIP METRICS (DURATION & DISTANCE) ---
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.black45, size: 20),
                        const SizedBox(height: 12),
                        const Text('Duration', style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(_formatDuration(rideData), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade100),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.route_outlined, color: Colors.black45, size: 20),
                        const SizedBox(height: 12),
                        const Text('Distance', style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 2),
                        Text(_formatDistance(rideData), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // --- FARE BREAKDOWN ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4)),
                ],
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('FARE BREAKDOWN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1.2)),
                  const SizedBox(height: 12),
                  
                  // Top section
                  _breakdownRow('Trip fare', fmt.format((rideData['fare_amount'] as num?) ?? 0)),
                  if (((rideData['pickup_fee'] as num?) ?? 0) > 0)
                    _breakdownRow('Pickup fee (included)', fmt.format((rideData['pickup_fee'] as num?) ?? 0)),
                  _breakdownRow('Passenger deductibles', fmt.format((rideData['passenger_deductible'] as num?) ?? 0)),
                  
                  const Divider(height: 24),
                  _breakdownRow('Gross total', fmt.format(((rideData['fare_amount'] as num?) ?? 0) + ((rideData['passenger_deductible'] as num?) ?? 0)), isBold: true),
                  const SizedBox(height: 16),
                  
                  // Deductions section
                  _breakdownRow('App usage charges', fmt.format((rideData['app_usage_charges'] as num?) ?? (rideData['platform_fee'] as num?) ?? 0), isNegative: true),
                  _breakdownRow('Passenger deductibles', fmt.format((rideData['passenger_deductible'] as num?) ?? 0), isNegative: true),
                  
                  const Divider(height: 24),
                  _breakdownRow('Deduction', fmt.format((((rideData['app_usage_charges'] as num?) ?? (rideData['platform_fee'] as num?) ?? 0) + ((rideData['passenger_deductible'] as num?) ?? 0))), isBold: true, isNegative: true),
                  const SizedBox(height: 16),

                  // Final earnings
                  _breakdownRow('Your earnings', fmt.format(driverEarnings), isBold: true),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // --- TRIP REF INFO ---
            Center(
              child: Text('Trip ID: $bookingRef', style: const TextStyle(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w600)),
            ),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
