import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../app/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../booking_provider.dart';

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

  String _vehicleAsset(String? type) {
    switch (type?.toLowerCase()) {
      case 'bike': return 'assets/icons/bike.png';
      case 'tuk': return 'assets/icons/tuk.png';
      case 'truck': return 'assets/icons/truck.png';
      case 'mini': return 'assets/icons/car.png';
      case 'van':
      case 'car':
      default: return 'assets/icons/car.png';
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd MMM yyyy, hh:mm a').format(date);
    } catch (_) {
      if (dateStr.length >= 16) return dateStr.substring(0, 16);
      return dateStr;
    }
  }
  
  String _formatTimeOnly(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
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

  String _formatDurationDetail(Map<String, dynamic> r) {
    final startedStr = r['started_at']?.toString();
    final completedStr = r['completed_at']?.toString();
    if (startedStr != null && completedStr != null) {
      try {
        final started = DateTime.parse(startedStr);
        final completed = DateTime.parse(completedStr);
        final diff = completed.difference(started);
        final mins = diff.inMinutes;
        final secs = diff.inSeconds % 60;
        if (mins > 0) {
          return '$mins minute${mins > 1 ? "s" : ""} $secs second${secs != 1 ? "s" : ""}';
        } else {
          return '$secs second${secs != 1 ? "s" : ""}';
        }
      } catch (_) {}
    }
    final durationMinRaw = r['duration_min'];
    if (durationMinRaw != null) {
      final val = (durationMinRaw is num) ? durationMinRaw.toDouble() : double.tryParse(durationMinRaw.toString());
      if (val != null) {
        return '${val.round()} minute${val.round() != 1 ? "s" : ""}';
      }
    }
    return '0 minutes';
  }

  String _formatEstimatedDuration(Map<String, dynamic> r) {
    final val = r['duration_min'];
    if (val != null) {
      final minutes = (val is num) ? val.toInt() : int.tryParse(val.toString());
      if (minutes != null) {
        if (minutes >= 60) {
          final hrs = minutes ~/ 60;
          final mins = minutes % 60;
          return '$hrs hour${hrs > 1 ? "s" : ""} $mins minute${mins != 1 ? "s" : ""}';
        }
        return '$minutes minute${minutes != 1 ? "s" : ""}';
      }
    }
    return '0 minutes';
  }

  String _formatDistanceDetail(Map<String, dynamic> r) {
    final raw = r['distance_km'];
    final dist = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
    if (dist != null) {
      return '${dist.toStringAsFixed(2)} km';
    }
    return '0.00 km';
  }

  double _parseNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  IconData _getPaymentIcon(String? method) {
    if (method == null) return Icons.payments_outlined;
    final m = method.toLowerCase();
    if (m.startsWith('card')) {
      return Icons.credit_card_rounded;
    } else if (m.startsWith('wallet')) {
      return Icons.account_balance_wallet_rounded;
    } else {
      return Icons.payments_outlined;
    }
  }

  String _getPaymentLabel(String? method) {
    if (method == null) return 'Cash';
    final m = method.toLowerCase();
    if (m.startsWith('card')) {
      return 'Card';
    } else if (m.startsWith('wallet')) {
      return 'Wallet';
    } else {
      return 'Cash';
    }
  }

  Widget _receiptRow(String label, String value, {bool isNegative = false, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? Colors.black87 : Colors.black54,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: isNegative
                  ? Colors.red
                  : (isBold ? Colors.black87 : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptSectionHeader(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _receiptSectionDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black45,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black45,
              fontWeight: FontWeight.w500,
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
    
    final finalAmount = _parseNum(rideData['final_amount']);
    final discountAmount = _parseNum(rideData['discount_amount']);
    final redeemDiscount = _parseNum(rideData['redeem_discount']);
    final totalDiscount = discountAmount + redeemDiscount;
    final fareAmount = rideData['fare_amount'] != null ? _parseNum(rideData['fare_amount']) : finalAmount;
    final actualGrossFare = finalAmount + totalDiscount;

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
            Builder(builder: (context) {
              final stopsList = (rideData['stops'] as List?) ?? [];
              // Build a flat list of all waypoints: pickup, stops..., drop
              final allPoints = <Map<String, String?>>[
                {'address': pickup, 'time': _formatTimeOnly(rideData['started_at']?.toString() ?? bookedAt)},
                for (final s in stopsList)
                  {'address': s['address']?.toString() ?? '', 'time': null},
                {'address': drop, 'time': _formatTimeOnly(rideData['completed_at']?.toString())},
              ];

              return Container(
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
                    // Left indicator column
                    Column(
                      children: [
                        const SizedBox(height: 4),
                        // Pickup dot
                        Container(width: 12, height: 12, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)),
                        for (int i = 1; i < allPoints.length; i++) ...[
                          // Connector line
                          Container(width: 2, height: 40, color: Colors.grey.shade200, margin: const EdgeInsets.symmetric(vertical: 4)),
                          // Stop or drop dot
                          if (i < allPoints.length - 1)
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.orange, width: 2),
                                color: Colors.orange.withValues(alpha: 0.15),
                              ),
                            )
                          else
                            Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.orange, width: 3))),
                        ],
                      ],
                    ),
                    const SizedBox(width: 16),
                    // Right address column
                    Builder(builder: (context) {
                      final requestedDrop = rideData['requested_drop_address']?.toString() ?? '';
                      final hasEndedEarly = requestedDrop.isNotEmpty && requestedDrop != drop;

                      return Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (int i = 0; i < allPoints.length; i++) ...[
                              if (i > 0) const SizedBox(height: 16),
                              if (i == allPoints.length - 1 && hasEndedEarly) ...[
                                Text(
                                  'Actual Drop-off:',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  allPoints[i]['address'] ?? '',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Selected Destination (Ended Early):',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  requestedDrop,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black54,
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  allPoints[i]['address'] ?? '',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: i == 0 || i == allPoints.length - 1 ? Colors.black87 : Colors.black54,
                                  ),
                                ),
                              ],
                              if (i == 0 && allPoints[i]['time'] != null && allPoints[i]['time']!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(allPoints[i]['time']!, style: const TextStyle(fontSize: 13, color: Colors.black45)),
                              ] else if (i == allPoints.length - 1 && allPoints[i]['time'] != null && allPoints[i]['time']!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(allPoints[i]['time']!, style: const TextStyle(fontSize: 13, color: Colors.black45)),
                              ] else if (i > 0 && i < allPoints.length - 1) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.radio_button_checked_rounded, size: 11, color: Colors.orange.shade400),
                                    const SizedBox(width: 4),
                                    Text('Stop $i', style: TextStyle(fontSize: 11, color: Colors.orange.shade600, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ],
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
            
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
                        Image.asset(
                          _vehicleAsset(serviceType),
                          width: 36,
                          height: 36,
                          errorBuilder: (context, error, stackTrace) => Icon(_vehicleIcon(serviceType), size: 24, color: Colors.black54),
                        ),
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
            
            // --- FARE BREAKDOWN CARD ---
            Container(
              margin: const EdgeInsets.only(top: 16),
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
                  const Text('RECEIPT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54, letterSpacing: 1.2)),
                  const SizedBox(height: 16),
                  
                  // Estimated Fare block
                  _receiptSectionHeader('Estimated Fare', fmt.format(fareAmount)),
                  _receiptSectionDetail('Estimated Duration', _formatEstimatedDuration(rideData)),
                  _receiptSectionDetail('Estimated Distance', _formatDistanceDetail(rideData)),
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: Colors.black12),
                  ),
                  
                  // Actual Fare block
                  _receiptSectionHeader('Actual Fare', fmt.format(actualGrossFare)),
                  _receiptSectionDetail('Actual Duration', _formatDurationDetail(rideData)),
                  _receiptSectionDetail('Actual Distance', _formatDistanceDetail(rideData)),
                  
                  if (totalDiscount > 0) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: Colors.black12),
                    ),
                    _receiptRow('Discount', '-${fmt.format(totalDiscount)}', isNegative: true),
                  ],
                  
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: Colors.black12),
                  ),
                  
                  _receiptRow('Total Trip Fare', fmt.format(actualGrossFare), isBold: true),
                  _receiptRow('Paid Amount', fmt.format(finalAmount), isBold: true),
                  
                  const SizedBox(height: 12),
                  
                  // Paid by
                  Row(
                    children: [
                      const Text(
                        'Paid by',
                        style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Icon(_getPaymentIcon(rideData['payment_method']?.toString()), size: 16, color: Colors.black54),
                      const SizedBox(width: 6),
                      Text(
                        _getPaymentLabel(rideData['payment_method']?.toString()),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        fmt.format(finalAmount),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ],
                  ),
                  
                  // Savings banner if savings > 0
                  if (totalDiscount > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.local_offer_rounded, color: Colors.green.shade700, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Your saving ${fmt.format(totalDiscount)} on this bill!',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            if (status.toLowerCase() == 'searching') ...[
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          title: const Text('Cancel Ride?'),
                          content: const Text('Are you sure you want to cancel this scheduled ride?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('No'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: TextButton.styleFrom(foregroundColor: AppColors.error),
                              child: const Text('Yes, Cancel'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (ctx) => const Center(child: CircularProgressIndicator()),
                        );
                        try {
                          final bp = Provider.of<BookingProvider>(context, listen: false);
                          await bp.updateStatus(rideData['id'] as int, 'cancelled', reason: 'Cancelled by user');
                          if (context.mounted) {
                            Navigator.pop(context); // pop loading
                            Navigator.pop(context); // pop details
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Ride cancelled successfully')),
                            );
                          }
                        } catch (_) {
                          if (context.mounted) {
                            Navigator.pop(context); // pop loading
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to cancel ride')),
                            );
                          }
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Text(
                      'CANCEL BOOKING',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),
            
            // --- BRANDING ---
            Center(
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/light.png',
                    height: 60,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Thanks for choosing Ziggo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // --- CUSTOMER & TRIP REF INFO ---
            Center(
              child: Column(
                children: [
                  Text('Trip ID: $bookingRef', style: const TextStyle(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w600)),
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
