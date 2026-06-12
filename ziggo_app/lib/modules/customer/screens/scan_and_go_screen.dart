import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../../../core/map/places.dart';
import '../../../core/map/place_search_sheet.dart';
import '../../../core/map/maps_service.dart';
import '../../../core/network/api_client.dart';
import '../booking_provider.dart';
import 'ride_tracking_screen.dart';
import 'qr_pay_scan_screen.dart';

class ScanAndGoScreen extends StatefulWidget {
  const ScanAndGoScreen({super.key});

  @override
  State<ScanAndGoScreen> createState() => _ScanAndGoScreenState();
}

class _ScanAndGoScreenState extends State<ScanAndGoScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final String code = barcodes.first.rawValue!;
      _handlePayload(code);
    }
  }

  void _handlePayload(String payload) async {
    if (!payload.startsWith('ziggo://scan-and-go')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid QR Code format'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final uri = Uri.parse(payload);
      final driverIdStr = uri.queryParameters['driver_id'];
      final name = Uri.decodeComponent(uri.queryParameters['name'] ?? 'Driver');
      final vehicle = Uri.decodeComponent(uri.queryParameters['vehicle'] ?? '—');
      final vehicleType = Uri.decodeComponent(uri.queryParameters['vehicle_type'] ?? 'car');

      if (driverIdStr == null) {
        throw Exception('Driver ID missing in QR');
      }

      final driverId = int.parse(driverIdStr);

      _scannerController.stop();

      // Show the confirmation sheet to pick destination and start ride
      await _showSetupSheet(driverId, name, vehicle, vehicleType);

      if (mounted && !_isProcessing) {
        _scannerController.start();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _showSetupSheet(
    int driverId,
    String name,
    String vehicle,
    String vehicleType,
  ) async {
    Place? pickup = await MapsService.instance.currentLocationAsPlace() ??
        const Place('Galle Face Green', 'Colombo 3', LatLng(6.9271, 79.8420));
    Place? drop;
    String paymentMethod = 'cash';
    Map<String, dynamic>? estimate;
    bool bookingInProgress = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setStateSheet) {
          final isEstimated = estimate != null;
          final finalAmount = isEstimated ? (estimate!['final_amount'] as num).toDouble() : 0.0;

          Future<void> selectDropLocation() async {
            final p = await showPlaceSearch(sheetCtx, title: 'Where to?');
            if (p != null) {
              setStateSheet(() {
                drop = p;
                estimate = null;
              });

              // Fetch estimate
              final bookingProv = context.read<BookingProvider>();
              final est = await bookingProv.estimateFare(
                serviceType: vehicleType,
                pickup: pickup!.location,
                drop: drop!.location,
              );

              if (est != null) {
                setStateSheet(() {
                  estimate = est;
                });
              }
            }
          }

          Future<void> confirmBooking() async {
            if (drop == null) return;

            setStateSheet(() {
              bookingInProgress = true;
            });

            // Let's call the backend scan-and-go API directly from Provider/Dio instead!
            final bookingResponse = await _executeScanAndGo(
              vehicleType,
              pickup!,
              drop!,
              paymentMethod,
              driverId,
            );

            if (sheetCtx.mounted) {
              Navigator.pop(sheetCtx); // Close sheet
            }

            if (bookingResponse != null && mounted) {
              // Reload active booking
              context.read<BookingProvider>().loadActive();
              // Navigate to active ride screen
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const RideTrackingScreen()),
              );
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to start Scan & Go ride'),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            }
          }

          return Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: AppColors.textPrimary),
                          ),
                          Text(
                            '$vehicleType • $vehicle',
                            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                const Text(
                  'CONFIRM TRIP DETAILS',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.textTertiary, letterSpacing: 1.2),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.my_location_rounded, color: AppColors.primary),
                  title: const Text('Pickup Address', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  subtitle: Text(pickup?.fullAddress ?? 'Detecting Location...', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.textPrimary)),
                ),
                const Divider(height: 1),
                ListTile(
                  onTap: selectDropLocation,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.pin_drop_rounded, color: AppColors.error),
                  title: const Text('Drop-off Destination', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    drop?.fullAddress ?? 'Tap to select destination',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: drop != null ? AppColors.textPrimary : AppColors.primary,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                ),
                const Divider(height: 1),
                const SizedBox(height: 16),
                if (isEstimated) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Estimated Fare',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textSecondary),
                      ),
                      Text(
                        'Rs.${finalAmount.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    const Icon(Icons.payment_rounded, color: AppColors.textSecondary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.textSecondary)),
                    const Spacer(),
                    DropdownButton<String>(
                      value: paymentMethod,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash', style: TextStyle(fontWeight: FontWeight.w800))),
                        DropdownMenuItem(value: 'wallet', child: Text('Wallet', style: TextStyle(fontWeight: FontWeight.w800))),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setStateSheet(() {
                            paymentMethod = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (drop == null || bookingInProgress) ? null : confirmBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: bookingInProgress
                        ? const CircularProgressIndicator(color: AppColors.primary)
                        : const Text(
                            'Start Scan & Go Ride',
                            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<Map<String, dynamic>?> _executeScanAndGo(
    String serviceType,
    Place pickup,
    Place drop,
    String paymentMethod,
    int driverId,
  ) async {
    try {
      final bookingProv = context.read<BookingProvider>();
      final resp = await ApiClient.instance.dio.post(
        '/bookings/scan-and-go',
        queryParameters: {'driver_id': driverId},
        data: {
          'service_type': serviceType,
          'pickup_lat': pickup.location.latitude,
          'pickup_lng': pickup.location.longitude,
          'pickup_address': pickup.fullAddress,
          'drop_lat': drop.location.latitude,
          'drop_lng': drop.location.longitude,
          'drop_address': drop.fullAddress,
          'payment_method': paymentMethod,
        },
      );
      return resp.data as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  void _showSimulateDialog() {
    final controller = TextEditingController(
      text: 'ziggo://scan-and-go?driver_id=1&name=John%20Doe&vehicle=WP%20CAB%201234&vehicle_type=car',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Simulate Scan & Go QR',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter QR code payload string:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                hintText: 'ziggo://scan-and-go?driver_id=1&name=John%20Doe...',
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handlePayload(controller.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Simulate Scan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Scan & Go',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.switch_camera_rounded),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.videocam_off_rounded,
                        color: Colors.white54,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Camera unavailable or permission denied',
                      style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use the simulator option below to test the Scan & Go flow',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),
          IgnorePointer(
            child: Container(
              decoration: ShapeDecoration(
                shape: QrScannerOverlayShape(
                  borderColor: AppColors.primary,
                  borderRadius: 24,
                  borderLength: 30,
                  borderWidth: 8,
                  cutOutSize: MediaQuery.of(context).size.width * 0.7,
                ),
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.6),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text(
                    'Matching with driver...',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Scan the driver\'s Scan & Go QR code',
                  style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _showSimulateDialog,
                    icon: const Icon(Icons.integration_instructions_rounded),
                    label: const Text(
                      'Simulate QR Scan (Emulator)',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.15),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.white.withOpacity(0.18)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
