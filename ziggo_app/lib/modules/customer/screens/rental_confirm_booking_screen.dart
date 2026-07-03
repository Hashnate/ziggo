import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../core/map/places.dart';
import '../../../core/network/api_client.dart';
import '../booking_provider.dart';
import 'ride_tracking_screen.dart';
import 'payment_selection_screen.dart';
import 'promotions_selection_screen.dart';

class RentalConfirmBookingScreen extends StatefulWidget {
  final Place pickup;
  final Place? drop;
  final String vehicleType;
  final int hours;
  final double distance;
  final bool isNow;
  final DateTime? scheduledDate;
  final TimeOfDay? scheduledTime;

  const RentalConfirmBookingScreen({
    super.key,
    required this.pickup,
    this.drop,
    required this.vehicleType,
    required this.hours,
    required this.distance,
    this.isNow = true,
    this.scheduledDate,
    this.scheduledTime,
  });

  @override
  State<RentalConfirmBookingScreen> createState() => _RentalConfirmBookingScreenState();
}

class _RentalConfirmBookingScreenState extends State<RentalConfirmBookingScreen> {
  bool _busy = false;
  String _selectedPayment = 'cash';
  String _selectedPromo = '';

  Future<void> _confirmBooking() async {
    setState(() => _busy = true);
    final created = await context.read<BookingProvider>().createBooking(
          serviceType: widget.vehicleType,
          pickup: widget.pickup.location,
          pickupAddress: widget.pickup.fullAddress,
          drop: widget.drop?.location ?? widget.pickup.location,
          dropAddress: widget.drop?.fullAddress ?? widget.pickup.fullAddress,
          paymentMethod: _selectedPayment,
          isRental: true,
          rentalHours: widget.hours,
        );
    if (!mounted) return;
    setState(() => _busy = false);
    
    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<BookingProvider>().lastError ?? 'Could not book'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RideTrackingScreen()),
      (route) => route.isFirst,
    );
  }

  String _getVehicleName(String type) {
    if (type == 'car') return 'Car';
    if (type == 'mini') return 'Mini';
    if (type == 'minivan') return 'Minivan';
    if (type == 'van') return 'Van';
    return 'Vehicle';
  }

  double _calculateTotal() {
    double base = 0;
    if (widget.vehicleType == 'mini') base = 1100;
    else if (widget.vehicleType == 'car') base = 1300;
    else if (widget.vehicleType == 'minivan') base = 1200;
    else if (widget.vehicleType == 'van') base = 2500;
    else base = 1000;

    double extraKm = widget.distance > 5 ? (widget.distance - 5) : 0;
    return (base * widget.hours) + (extraKm * 140);
  }

  @override
  Widget build(BuildContext context) {
    final double totalAmount = _calculateTotal();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Confirm Booking', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.divider),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: const [
                Icon(Icons.person_outline_rounded, size: 16, color: AppColors.primary),
                SizedBox(width: 4),
                Text('For Me', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          )
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vehicle, Time, Distance Summary Box
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                      ]
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Icon(Icons.directions_car_rounded, size: 28, color: AppColors.textSecondary),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(_getVehicleName(widget.vehicleType), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.person, size: 12, color: AppColors.textSecondary),
                                  const Text('4', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 40, color: AppColors.divider),
                        Expanded(
                          child: Column(
                            children: [
                              const Text('Time', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text.rich(TextSpan(
                                children: [
                                  TextSpan(text: '${widget.hours}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                                  const TextSpan(text: ' hrs', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                ]
                              )),
                            ],
                          ),
                        ),
                        Container(width: 1, height: 40, color: AppColors.divider),
                        Expanded(
                          child: Column(
                            children: [
                              const Text('Distance', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                              const SizedBox(height: 2),
                              Text.rich(TextSpan(
                                children: [
                                  TextSpan(text: '${widget.distance.toInt()}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                                  const TextSpan(text: ' Km', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                                ]
                              )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date and Time Box
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.cardBorder),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                            ]
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Pickup Date', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary)),
                              const SizedBox(height: 6),
                              Text(widget.isNow ? 'Today' : (widget.scheduledDate != null ? DateFormat('MMM dd, yyyy').format(widget.scheduledDate!) : 'Today'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.cardBorder),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                            ]
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Pickup Time', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.textSecondary)),
                              const SizedBox(height: 6),
                              Text(widget.isNow ? 'Now' : (widget.scheduledTime != null ? widget.scheduledTime!.format(context) : 'Now'), style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Location Box
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                      ]
                    ),
                    child: Column(
                      children: [
                        _buildLocationRow(Icons.arrow_upward_rounded, AppColors.primary, 'Pickup :', widget.pickup.fullAddress),
                        const SizedBox(height: 16),
                        _buildLocationRow(Icons.arrow_downward_rounded, Colors.orange, 'Drop :', widget.drop?.fullAddress ?? 'Drop location not provided', isPlaceholder: widget.drop == null),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Info Box
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
                      ]
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 20),
                            SizedBox(width: 8),
                            Text('Important Information', style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 15)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text('Additional Charges', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('• Per extra km:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            Text('140.00', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text('• Per extra hour:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                            Text('660.00', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text('Other Fees', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                        const SizedBox(height: 8),
                        const Text('• Toll fees and parking fees not included.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Payment Summary Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.cardBorder),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
                      ]
                    ),
                    child: Column(
                      children: [
                        // Payment options
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.money_rounded, color: AppColors.success, size: 18),
                                ),
                                const SizedBox(width: 14),
                                Text(_selectedPayment == 'cash' ? 'Cash' : _selectedPayment.toUpperCase(), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            GestureDetector(
                              onTap: () async {
                                final result = await Navigator.push<String>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PaymentSelectionScreen(currentPayment: _selectedPayment),
                                  ),
                                );
                                if (result != null) {
                                  setState(() => _selectedPayment = result);
                                }
                              },
                              child: const Text('Change', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14)),
                            ),
                          ],
                        ),
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Divider(height: 1, color: AppColors.divider),
                        ),
                        
                        // Promo options
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: AppColors.primarySoft,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.local_offer_rounded, color: AppColors.primary, size: 18),
                                ),
                                if (_selectedPromo.isNotEmpty) ...[
                                  const SizedBox(width: 14),
                                  Text(_selectedPromo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                                ],
                              ],
                            ),
                            GestureDetector(
                              onTap: () async {
                                final result = await Navigator.push<String>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => PromotionsSelectionScreen(currentPromo: _selectedPromo),
                                  ),
                                );
                                if (result != null) {
                                  setState(() => _selectedPromo = result);
                                }
                              },
                              child: Text(_selectedPromo.isEmpty ? 'Add Promo' : 'Change Promo', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14)),
                            ),
                          ],
                        ),
                        
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Divider(height: 1, color: AppColors.divider),
                        ),

                        // Total
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Amount', style: TextStyle(fontSize: 15, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                            Text('LKR ${totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Confirm button
                  Container(
                    width: double.infinity,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ElevatedButton(
                      onPressed: _confirmBooking,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text('Confirm Booking', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildLocationRow(IconData icon, Color color, String title, String address, {bool isPlaceholder = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(
                address, 
                style: TextStyle(
                  fontSize: 13, 
                  color: isPlaceholder ? AppColors.textTertiary : AppColors.textSecondary,
                  fontWeight: isPlaceholder ? FontWeight.w500 : FontWeight.w400,
                )
              ),
            ],
          ),
        ),
      ],
    );
  }
}
