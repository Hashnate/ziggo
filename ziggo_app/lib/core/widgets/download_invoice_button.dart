import 'package:flutter/material.dart';
import '../../app/app_colors.dart';
import '../services/invoice_service.dart';

class DownloadInvoiceButton extends StatefulWidget {
  final Map<String, dynamic> rideData;
  final bool isDriver;

  const DownloadInvoiceButton({
    super.key,
    required this.rideData,
    required this.isDriver,
  });

  @override
  State<DownloadInvoiceButton> createState() => _DownloadInvoiceButtonState();
}

class _DownloadInvoiceButtonState extends State<DownloadInvoiceButton> {
  bool _isDownloading = false;

  Future<void> _handleDownload() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      await InvoiceService.downloadInvoice(
        context: context,
        rideData: widget.rideData,
        isDriver: widget.isDriver,
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 340),
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _isDownloading ? null : _handleDownload,
        icon: _isDownloading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.picture_as_pdf_rounded,
                size: 20,
                color: Colors.white,
              ),
        label: Text(
          _isDownloading ? 'Downloading PDF...' : 'Download Invoice PDF',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.7),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    );
  }
}
