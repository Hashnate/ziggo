import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../app/app_colors.dart';

enum LocationAccessStatus {
  granted,
  serviceDisabled,
  permissionDenied,
}

class LocationPermissionHelper {
  LocationPermissionHelper._();

  /// Check current status without prompting system dialogs
  static Future<LocationAccessStatus> checkStatus() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationAccessStatus.serviceDisabled;
      }
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever ||
          perm == LocationPermission.unableToDetermine) {
        return LocationAccessStatus.permissionDenied;
      }
      return LocationAccessStatus.granted;
    } catch (_) {
      return LocationAccessStatus.permissionDenied;
    }
  }

  /// Request permission or check if granted
  static Future<LocationAccessStatus> requestPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationAccessStatus.serviceDisabled;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever ||
          perm == LocationPermission.unableToDetermine) {
        return LocationAccessStatus.permissionDenied;
      }
      return LocationAccessStatus.granted;
    } catch (_) {
      return LocationAccessStatus.permissionDenied;
    }
  }

  /// Open either iOS/Android Location settings (if service off) or App settings (if permission denied)
  static Future<void> openSettings({bool isService = false}) async {
    try {
      if (isService) {
        await Geolocator.openLocationSettings();
      } else {
        await Geolocator.openAppSettings();
      }
    } catch (_) {}
  }

  /// Displays the location guidance dialog giving the option to navigate to Settings
  static Future<bool?> showLocationDialog({
    required BuildContext context,
    required String title,
    required String message,
    required String actionLabel,
    bool barrierDismissible = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.location_on, color: AppColors.primary, size: 36),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Not now',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              elevation: 0,
            ),
            child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// Verifies location status and if not granted, displays guidance dialog and optionally navigates to Settings.
  /// Returns true if permission is granted, false if denied or service is off.
  static Future<bool> ensureLocationAccess({
    required BuildContext context,
    String? customMessage,
    bool promptIfDenied = true,
  }) async {
    final status = await checkStatus();
    if (status == LocationAccessStatus.granted) {
      return true;
    }

    if (!promptIfDenied) return false;
    if (!context.mounted) return false;

    if (status == LocationAccessStatus.serviceDisabled) {
      final open = await showLocationDialog(
        context: context,
        title: 'Turn on location',
        message: customMessage ??
            'Ziggo needs your location to find nearby rides and set your pickup point. Please turn on Location services.',
        actionLabel: 'Open settings',
      );
      if (open == true) {
        await openSettings(isService: true);
      }
      return false;
    }

    // Permission denied: attempt request once if denied
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        return true;
      }
    }

    if (!context.mounted) return false;
    final open = await showLocationDialog(
      context: context,
      title: 'Location permission needed',
      message: customMessage ??
          'Location access is disabled. Open app settings to allow Ziggo to use your location for rides.',
      actionLabel: 'Open app settings',
    );
    if (open == true) {
      await openSettings(isService: false);
    }
    return false;
  }
}

/// A clean in-screen banner to guide users to re-enable location access from Settings
class LocationPermissionBanner extends StatelessWidget {
  final bool isServiceDisabled;
  final VoidCallback onOpenSettings;
  final VoidCallback? onDismiss;

  const LocationPermissionBanner({
    super.key,
    this.isServiceDisabled = false,
    required this.onOpenSettings,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: AppColors.primary.withOpacity(0.35), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_off_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isServiceDisabled
                      ? 'Location services turned off'
                      : 'Location permission disabled',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isServiceDisabled
                      ? 'Enable location services in Settings to find rides'
                      : 'Open Settings to enable location access for rides',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onOpenSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: const Text(
              'Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
