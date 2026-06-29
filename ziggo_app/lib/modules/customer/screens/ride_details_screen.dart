import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';

class RideDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> rideData;

  const RideDetailsScreen({super.key, required this.rideData});

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

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2);
    final bookingRef = rideData['booking_ref']?.toString() ?? rideData['id']?.toString() ?? 'Unknown';
    final serviceType = (rideData['service_type'] ?? 'car').toString();
    final status = (rideData['status'] ?? '').toString();
    
    final driverRaw = rideData['driver'];
    final driverData = driverRaw is Map ? driverRaw : {};
    final driverName = driverData['full_name']?.toString() ?? 'Driver';
    final driverRating = driverData['rating']?.toString() ?? '4.5';
    
    final vehiclePlate = driverData['vehicle_number']?.toString() ?? 'N/A';
    String? driverPhoto = driverData['profile_photo']?.toString();
    if (driverPhoto != null && driverPhoto.isNotEmpty && driverPhoto.startsWith('/')) {
      driverPhoto = '${ApiConfig.baseHost}$driverPhoto';
    }
    
    final pickup = rideData['pickup_address']?.toString() ?? '';
    final drop = rideData['drop_address']?.toString() ?? '';
    final bookedAt = rideData['booked_at']?.toString();
    
    final customerName = rideData['customer_name']?.toString();
    final customerPhone = rideData['customer_phone']?.toString();
    
    final finalAmount = (rideData['final_amount'] as num?)?.toDouble() ?? 0.0;

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
                Text(
                  fmt.format(finalAmount),
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
            
            // --- DRIVER PROFILE CARD ---
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
                    backgroundImage: driverPhoto != null && driverPhoto.isNotEmpty ? NetworkImage(driverPhoto) : null,
                    child: driverPhoto == null || driverPhoto.isEmpty ? const Icon(Icons.person, color: Colors.black26, size: 28) : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(driverName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.orange, size: 16),
                            const SizedBox(width: 4),
                            Text(driverRating, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.black54)),
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
                        const SizedBox(height: 4),
                        Text(vehiclePlate, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900)),
                        if (serviceType.isNotEmpty)
                          Text(
                            '${serviceType[0].toUpperCase()}${serviceType.substring(1)}',
                            style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                          ),
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
            
            const SizedBox(height: 32),
            
            // --- CUSTOMER & TRIP REF INFO ---
            Center(
              child: Column(
                children: [
                  Text('Trip ID: $bookingRef', style: const TextStyle(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w600)),
                  if (customerName != null || customerPhone != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [customerName, customerPhone].where((e) => e != null && e.isNotEmpty).join(' • '),
                      style: const TextStyle(fontSize: 12, color: Colors.black38),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
