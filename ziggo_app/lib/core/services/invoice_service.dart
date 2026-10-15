import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../app/app_colors.dart';

class InvoiceService {
  static const MethodChannel _downloaderChannel =
      MethodChannel('lk.ziggo.app/file_downloader');

  /// Generates the PDF invoice and directly downloads it to the mobile Downloads folder.
  static Future<void> downloadInvoice({
    required BuildContext context,
    required Map<String, dynamic> rideData,
    required bool isDriver,
  }) async {
    final bookingRef = rideData['booking_ref']?.toString() ??
        rideData['id']?.toString() ??
        'Invoice';
    final fileName = isDriver
        ? 'ziggo_driver_invoice_$bookingRef.pdf'
        : 'ziggo_invoice_$bookingRef.pdf';

    try {
      final pdfBytes = isDriver
          ? await _generateDriverInvoice(rideData)
          : await _generateCustomerInvoice(rideData);

      String? savedPath;

      // 1. Primary path: Android MediaStore direct write to Downloads folder
      if (Platform.isAndroid) {
        try {
          savedPath = await _downloaderChannel.invokeMethod<String>(
            'saveToDownloads',
            {
              'fileName': fileName,
              'bytes': pdfBytes,
              'mimeType': 'application/pdf',
            },
          );
        } catch (e) {
          debugPrint('MethodChannel saveToDownloads error: $e');
        }

        // 2. Direct write to /storage/emulated/0/Download
        if (savedPath == null) {
          try {
            final publicDir = Directory('/storage/emulated/0/Download');
            if (await publicDir.exists()) {
              final file = File('${publicDir.path}/$fileName');
              await file.writeAsBytes(pdfBytes);
              savedPath = file.path;
            }
          } catch (e) {
            debugPrint('Public Downloads direct write error: $e');
          }
        }

        // 3. App external Downloads directory
        if (savedPath == null) {
          try {
            final extDirs = await getExternalStorageDirectories(
              type: StorageDirectory.downloads,
            );
            if (extDirs != null && extDirs.isNotEmpty) {
              final file = File('${extDirs.first.path}/$fileName');
              await file.writeAsBytes(pdfBytes);
              savedPath = file.path;
            }
          } catch (e) {
            debugPrint('ExternalStorageDirectories write error: $e');
          }
        }
      }

      // 4. Fallback for iOS / macOS / Linux / Windows
      if (savedPath == null) {
        try {
          final docDir = await getDownloadsDirectory() ??
              await getApplicationDocumentsDirectory();
          final file = File('${docDir.path}/$fileName');
          await file.writeAsBytes(pdfBytes);
          savedPath = file.path;
        } catch (e) {
          debugPrint('DocumentsDirectory write error: $e');
        }
      }

      if (!context.mounted) return;

      if (Platform.isIOS) {
        // On iOS, invoke system share/files dialog so user can save directly to Files / Downloads
        await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.success,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Invoice downloaded: $fileName',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // On Android, show success banner with location + open/share action
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF0F172A),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Downloaded to mobile Downloads',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fileName,
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'OPEN / SHARE',
              textColor: const Color(0xFF38BDF8),
              onPressed: () {
                Printing.sharePdf(bytes: pdfBytes, filename: fileName);
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Invoice download error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.error,
            content: Text('Failed to download invoice: $e'),
          ),
        );
      }
    }
  }

  // --- CUSTOMER INVOICE GENERATOR ---
  static Future<Uint8List> _generateCustomerInvoice(
      Map<String, dynamic> rideData) async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      final imgBytes = await rootBundle.load('assets/images/light.png');
      logoImage = pw.MemoryImage(imgBytes.buffer.asUint8List());
    } catch (_) {}

    final fmt = NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2);
    final bookingRef = rideData['booking_ref']?.toString() ??
        rideData['id']?.toString() ??
        'N/A';
    final dateStr = rideData['booked_at']?.toString() ?? '';
    final date = dateStr.isNotEmpty
        ? DateFormat('dd MMM yyyy, hh:mm a')
            .format(DateTime.parse(dateStr).toLocal())
        : '';
    final status = (rideData['status'] ?? 'COMPLETED').toString().toUpperCase();

    final pickup = rideData['pickup_address']?.toString() ?? 'N/A';
    final actualDrop = rideData['actual_drop_address']?.toString() ??
        rideData['drop_address']?.toString() ??
        'N/A';
    final selectedDrop = rideData['drop_address']?.toString();
    final endedEarly = rideData['ended_early'] == true ||
        (selectedDrop != null &&
            selectedDrop.isNotEmpty &&
            selectedDrop != actualDrop);

    final driverRaw = rideData['driver'];
    final driverData = driverRaw is Map ? driverRaw : {};
    final driverName = driverData['full_name']?.toString() ?? 'Driver';
    final driverPlate = driverData['vehicle_number']?.toString() ?? '';
    final vehicleType = rideData['service_type']?.toString().toUpperCase() ??
        driverData['vehicle_type']?.toString().toUpperCase() ??
        'VEHICLE';

    final duration = _formatDuration(rideData);
    final distance = _formatDistance(rideData);

    final finalAmount = _parseNum(rideData['final_amount']);
    final discountAmount = _parseNum(rideData['discount_amount']);
    final redeemDiscount = _parseNum(rideData['redeem_discount']);
    final totalDiscount = discountAmount + redeemDiscount;
    final fareAmount = rideData['fare_amount'] != null
        ? _parseNum(rideData['fare_amount'])
        : finalAmount;
    final actualGrossFare = finalAmount + totalDiscount;
    final paymentMethod =
        (rideData['payment_method'] ?? 'cash').toString().toUpperCase();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoImage != null)
                    pw.Image(logoImage, height: 45)
                  else
                    pw.Text('ZIGGO',
                        style: pw.TextStyle(
                            fontSize: 28,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900)),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('TAX INVOICE / RECEIPT',
                          style: pw.TextStyle(
                              fontSize: 14,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800)),
                      pw.SizedBox(height: 4),
                      pw.Text('Trip ID: $bookingRef',
                          style: pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.grey700,
                              fontWeight: pw.FontWeight.bold)),
                      pw.Text('Date: $date',
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 10),

              // Total Amount Box
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL AMOUNT PAID',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey700)),
                        pw.SizedBox(height: 4),
                        pw.Text(fmt.format(finalAmount),
                            style: pw.TextStyle(
                                fontSize: 20,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blue900)),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green100,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(status,
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.green800)),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // Driver & Vehicle Card
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('DRIVER DETAILS',
                            style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey600)),
                        pw.SizedBox(height: 4),
                        pw.Text(driverName,
                            style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('$vehicleType ${driverPlate.isNotEmpty ? "• $driverPlate" : ""}',
                            style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blue800)),
                        pw.SizedBox(height: 2),
                        pw.Text('Duration: $duration | Distance: $distance',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey600)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // Trip Route
              pw.Text('TRIP ROUTE',
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800)),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey200),
                  borderRadius: pw.BorderRadius.circular(8),
                  color: PdfColors.grey50,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('• Pickup: ',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                                color: PdfColors.black)),
                        pw.Expanded(
                            child: pw.Text(pickup,
                                style: const pw.TextStyle(fontSize: 10))),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('• Drop-off: ',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                                color: PdfColors.green800)),
                        pw.Expanded(
                            child: pw.Text(actualDrop,
                                style: const pw.TextStyle(fontSize: 10))),
                      ],
                    ),
                    if (endedEarly && selectedDrop != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Text(
                          '  (Destination ended early from: $selectedDrop)',
                          style: const pw.TextStyle(
                              fontSize: 9,
                              color: PdfColors.orange800,
                              fontStyle: pw.FontStyle.italic)),
                    ],
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // RECEIPT BREAKDOWN
              pw.Text('RECEIPT BREAKDOWN',
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800)),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 6),

              _pdfRow('Base Fare / Trip Fare', fmt.format(fareAmount)),
              if (rideData['waiting_charge'] != null &&
                  _parseNum(rideData['waiting_charge']) > 0)
                _pdfRow('Waiting Charges',
                    fmt.format(_parseNum(rideData['waiting_charge']))),
              if (rideData['pickup_fee'] != null &&
                  _parseNum(rideData['pickup_fee']) > 0)
                _pdfRow('Pickup Fee',
                    fmt.format(_parseNum(rideData['pickup_fee']))),
              if (rideData['peak_surcharge'] != null &&
                  _parseNum(rideData['peak_surcharge']) > 0)
                _pdfRow('Peak Surcharge',
                    fmt.format(_parseNum(rideData['peak_surcharge']))),

              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              pw.SizedBox(height: 6),

              _pdfRow('Total Trip Fare', fmt.format(actualGrossFare),
                  isBold: true),

              if (totalDiscount > 0) ...[
                _pdfRow('Promotional Savings', '-${fmt.format(totalDiscount)}',
                    isNegative: true),
              ],

              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.black),
              pw.SizedBox(height: 6),

              _pdfRow('Paid Amount', fmt.format(finalAmount),
                  isBold: true, fontSize: 13),
              _pdfRow('Paid by', '$paymentMethod (${fmt.format(finalAmount)})',
                  isBold: false),

              pw.Spacer(),

              // Footer
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('Thanks for choosing Ziggo!',
                        style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800)),
                    pw.SizedBox(height: 2),
                    pw.Text('Ziggo Super App • For questions, contact support@ziggo.lk',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey500)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // --- DRIVER INVOICE GENERATOR ---
  static Future<Uint8List> _generateDriverInvoice(
      Map<String, dynamic> rideData) async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      final imgBytes = await rootBundle.load('assets/images/light.png');
      logoImage = pw.MemoryImage(imgBytes.buffer.asUint8List());
    } catch (_) {}

    final fmt = NumberFormat.currency(symbol: 'LKR ', decimalDigits: 2);
    final bookingRef = rideData['booking_ref']?.toString() ??
        rideData['id']?.toString() ??
        'N/A';
    final dateStr = rideData['booked_at']?.toString() ?? '';
    final date = dateStr.isNotEmpty
        ? DateFormat('dd MMM yyyy, hh:mm a')
            .format(DateTime.parse(dateStr).toLocal())
        : '';
    final status = (rideData['status'] ?? 'COMPLETED').toString().toUpperCase();

    final pickup = rideData['pickup_address']?.toString() ?? 'N/A';
    final actualDrop = rideData['actual_drop_address']?.toString() ??
        rideData['drop_address']?.toString() ??
        'N/A';
    final passengerName = rideData['customer_name']?.toString() ??
        rideData['customer']?['name']?.toString() ??
        'Passenger';
    final vehicleType = rideData['vehicle_type']?.toString().toUpperCase() ??
        rideData['service_type']?.toString().toUpperCase() ??
        'VEHICLE';

    final duration = _formatDuration(rideData);
    final distance = _formatDistance(rideData);

    final isFood = rideData['is_food'] == true ||
        (rideData['service_type']?.toString().toLowerCase().contains('food') ??
            false);
    final isMarket = rideData['is_market'] == true ||
        (rideData['service_type']?.toString().toLowerCase().contains('market') ??
            false);

    final pickupFee = _parseNum(rideData['pickup_fee']);
    final boost = _parseNum(rideData['boost']);
    final grossTotal = _parseNum(rideData['final_amount'] ?? rideData['fare_amount']);
    final fareAmount = _parseNum(rideData['fare_amount']);
    final appUsage = _parseNum(rideData['app_usage_charges'] ?? rideData['platform_fee']);
    final passengerDeductible = _parseNum(rideData['passenger_deductible']);
    final totalDeductions = appUsage + passengerDeductible;
    final driverEarnings = _parseNum(rideData['driver_earnings'] ?? (grossTotal - totalDeductions));
    final paymentMethod =
        (rideData['payment_method'] ?? 'cash').toString().toUpperCase();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoImage != null)
                    pw.Image(logoImage, height: 45)
                  else
                    pw.Text('ZIGGO',
                        style: pw.TextStyle(
                            fontSize: 28,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blue900)),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('DRIVER TRIP SUMMARY & INVOICE',
                          style: pw.TextStyle(
                              fontSize: 13,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue800)),
                      pw.SizedBox(height: 4),
                      pw.Text('Trip ID: $bookingRef',
                          style: pw.TextStyle(
                              fontSize: 10,
                              color: PdfColors.grey700,
                              fontWeight: pw.FontWeight.bold)),
                      pw.Text('Date: $date',
                          style: const pw.TextStyle(
                              fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 10),

              // Earnings Banner
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.green200),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('NET DRIVER EARNINGS',
                            style: pw.TextStyle(
                                fontSize: 10,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.green900)),
                        pw.SizedBox(height: 4),
                        pw.Text(fmt.format(driverEarnings),
                            style: pw.TextStyle(
                                fontSize: 20,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.green800)),
                      ],
                    ),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.green200,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(status,
                          style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.green900)),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // Passenger & Vehicle Card
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PASSENGER',
                            style: pw.TextStyle(
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.grey600)),
                        pw.SizedBox(height: 4),
                        pw.Text(passengerName,
                            style: pw.TextStyle(
                                fontSize: 13,
                                fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(vehicleType,
                            style: pw.TextStyle(
                                fontSize: 11,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.blue800)),
                        pw.SizedBox(height: 2),
                        pw.Text('Duration: $duration | Distance: $distance',
                            style: const pw.TextStyle(
                                fontSize: 9, color: PdfColors.grey600)),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // Trip Route
              pw.Text('TRIP ROUTE',
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800)),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey200),
                  borderRadius: pw.BorderRadius.circular(8),
                  color: PdfColors.grey50,
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('• Pickup: ',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10)),
                        pw.Expanded(
                            child: pw.Text(pickup,
                                style: const pw.TextStyle(fontSize: 10))),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('• Drop-off: ',
                            style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 10,
                                color: PdfColors.green800)),
                        pw.Expanded(
                            child: pw.Text(actualDrop,
                                style: const pw.TextStyle(fontSize: 10))),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 16),

              // FARE BREAKDOWN
              pw.Text('FARE BREAKDOWN',
                  style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.grey800)),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.grey300),
              pw.SizedBox(height: 6),

              if (isFood || isMarket) ...[
                _pdfRow('Pickup fee', fmt.format(pickupFee)),
                _pdfRow('Distance fare', fmt.format(fareAmount)),
                if (boost > 0) _pdfRow('Boost incentive', fmt.format(boost)),
              ] else ...[
                _pdfRow('Trip fare', fmt.format(fareAmount)),
                if (pickupFee > 0)
                  _pdfRow('Pickup fee (included)', fmt.format(pickupFee)),
                if (passengerDeductible > 0)
                  _pdfRow('Passenger deductibles', fmt.format(passengerDeductible)),
              ],

              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              pw.SizedBox(height: 6),

              _pdfRow('Gross Total', fmt.format(grossTotal), isBold: true),

              pw.SizedBox(height: 6),
              _pdfRow('App usage charges', '-${fmt.format(appUsage)}',
                  isNegative: true),
              if (passengerDeductible > 0)
                _pdfRow('Passenger deductibles', '-${fmt.format(passengerDeductible)}',
                    isNegative: true),
              _pdfRow('Total Deductions', '-${fmt.format(totalDeductions)}',
                  isBold: true, isNegative: true),

              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.black),
              pw.SizedBox(height: 6),

              _pdfRow('Your Earnings', fmt.format(driverEarnings),
                  isBold: true, fontSize: 13),
              _pdfRow('Payment Method', paymentMethod),

              pw.Spacer(),

              // Footer
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              pw.SizedBox(height: 8),
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text('Thank you for driving with Ziggo!',
                        style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.grey800)),
                    pw.SizedBox(height: 2),
                    pw.Text('Ziggo Driver Partner • support@ziggo.lk',
                        style: const pw.TextStyle(
                            fontSize: 9, color: PdfColors.grey500)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  // --- HELPERS ---
  static pw.Widget _pdfRow(String label, String value,
      {bool isNegative = false, bool isBold = false, double fontSize = 10}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isBold ? PdfColors.black : PdfColors.grey800,
            ),
          ),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: isNegative
                  ? PdfColors.red800
                  : (isBold ? PdfColors.black : PdfColors.grey900),
            ),
          ),
        ],
      ),
    );
  }

  static double _parseNum(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static String _formatDuration(Map<String, dynamic> r) {
    final startedStr = r['started_at']?.toString();
    final completedStr = r['completed_at']?.toString();
    if (startedStr != null && completedStr != null) {
      try {
        final started = DateTime.parse(startedStr);
        final completed = DateTime.parse(completedStr);
        final diff = completed.difference(started);
        final secs = diff.inMilliseconds / 1000.0;
        if (secs < 60) return '${secs.toStringAsFixed(0)}s';
        final mins = secs / 60.0;
        return '${mins.toStringAsFixed(0)}m';
      } catch (_) {}
    }
    final durationMinRaw = r['duration_min'];
    if (durationMinRaw != null) {
      final val = (durationMinRaw is num)
          ? durationMinRaw.toDouble()
          : double.tryParse(durationMinRaw.toString());
      if (val != null) {
        if (val > 300) return '${(val / 60).round()}m';
        return '${val.round()}m';
      }
    }
    return '0m';
  }

  static String _formatDistance(Map<String, dynamic> r) {
    final raw = r['distance_km'];
    final dist = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
    if (dist != null) return '${dist.toStringAsFixed(1)} km';
    return '0.0 km';
  }
}
