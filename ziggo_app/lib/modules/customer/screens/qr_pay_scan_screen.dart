import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../app/app_colors.dart';
import '../../../app/app_styles.dart';
import '../wallet_provider.dart';
import 'qr_pay_confirm_screen.dart';

class QrPayScanScreen extends StatefulWidget {
  const QrPayScanScreen({super.key});

  @override
  State<QrPayScanScreen> createState() => _QrPayScanScreenState();
}

class _QrPayScanScreenState extends State<QrPayScanScreen> {
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
    setState(() {
      _isProcessing = true;
    });

    try {
      final walletProv = context.read<WalletProvider>();
      final merchantInfo = await walletProv.resolveQrCode(payload);

      if (!mounted) return;

      if (merchantInfo != null) {
        // Stop scanning while on confirmation screen
        _scannerController.stop();
        
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => QrPayConfirmScreen(
              merchantInfo: merchantInfo,
            ),
          ),
        );

        // Resume scanning when coming back
        _scannerController.start();
      } else {
        throw Exception('No merchant details found');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
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
          'Scan QR Code',
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
          // Background Camera scanner
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
                      'Use the simulator option below to test the payment flow',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),

          // Scanning Overlay guide
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

          // Processing spinner
          if (_isProcessing)
            Container(
              color: Colors.black.withOpacity(0.6),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  const Text(
                    'Resolving merchant details...',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          // Simulator action overlay
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Align QR code within the frame',
                  style: TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class QrScannerOverlayShape extends ShapeBorder {
  final Color borderColor;
  final double borderWidth;
  final double borderLength;
  final double borderRadius;
  final double cutOutSize;

  const QrScannerOverlayShape({
    this.borderColor = Colors.white,
    this.borderWidth = 1.0,
    this.borderLength = 40.0,
    this.borderRadius = 0.0,
    this.cutOutSize = 250.0,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()
      ..addOval(
        Rect.fromCircle(
          center: rect.center,
          radius: cutOutSize / 2,
        ),
      );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(rect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final double width = rect.width;
    final double height = rect.height;

    final Paint backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    final Paint borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;

    final double cutOutLeft = (width - cutOutSize) / 2;
    final double cutOutTop = (height - cutOutSize) / 2;

    // Draw opaque background mask
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(rect),
        Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(cutOutLeft, cutOutTop, cutOutSize, cutOutSize),
              Radius.circular(borderRadius),
            ),
          ),
      ),
      backgroundPaint,
    );

    // Draw scanning border corners
    final double cornerRadius = borderRadius;
    final double sideLength = borderLength;

    final Path path = Path()
      // Top Left Corner
      ..moveTo(cutOutLeft + sideLength, cutOutTop)
      ..lineTo(cutOutLeft + cornerRadius, cutOutTop)
      ..quadraticBezierTo(cutOutLeft, cutOutTop, cutOutLeft, cutOutTop + cornerRadius)
      ..lineTo(cutOutLeft, cutOutTop + sideLength)
      // Bottom Left Corner
      ..moveTo(cutOutLeft, cutOutTop + cutOutSize - sideLength)
      ..lineTo(cutOutLeft, cutOutTop + cutOutSize - cornerRadius)
      ..quadraticBezierTo(
          cutOutLeft, cutOutTop + cutOutSize, cutOutLeft + cornerRadius, cutOutTop + cutOutSize)
      ..lineTo(cutOutLeft + sideLength, cutOutTop + cutOutSize)
      // Bottom Right Corner
      ..moveTo(cutOutLeft + cutOutSize - sideLength, cutOutTop + cutOutSize)
      ..lineTo(cutOutLeft + cutOutSize - cornerRadius, cutOutTop + cutOutSize)
      ..quadraticBezierTo(cutOutLeft + cutOutSize, cutOutTop + cutOutSize,
          cutOutLeft + cutOutSize, cutOutTop + cutOutSize - cornerRadius)
      ..lineTo(cutOutLeft + cutOutSize, cutOutTop + cutOutSize - sideLength)
      // Top Right Corner
      ..moveTo(cutOutLeft + cutOutSize, cutOutTop + sideLength)
      ..lineTo(cutOutLeft + cutOutSize, cutOutTop + cornerRadius)
      ..quadraticBezierTo(cutOutLeft + cutOutSize, cutOutTop,
          cutOutLeft + cutOutSize - cornerRadius, cutOutTop)
      ..lineTo(cutOutLeft + cutOutSize - sideLength, cutOutTop);

    canvas.drawPath(path, borderPaint);
  }

  @override
  ShapeBorder scale(double t) {
    return QrScannerOverlayShape(
      borderColor: borderColor,
      borderWidth: borderWidth,
      borderLength: borderLength,
      borderRadius: borderRadius,
      cutOutSize: cutOutSize * t,
    );
  }
}
