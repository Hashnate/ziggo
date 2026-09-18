import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_colors.dart';
import '../../app/app_styles.dart';

/// Android 14+ gate for the incoming-ride full-screen alert.
///
/// Before Android 14 `USE_FULL_SCREEN_INTENT` was granted at install. From
/// API 34 only dialers and alarm clocks get it automatically — everyone else
/// has to send the user to Settings. Without it the ride alert quietly drops
/// from a full-screen call takeover to an ordinary heads-up banner, which is
/// exactly the thing a driver misses.
///
/// No-ops on iOS (CallKit covers that) and on Android 13 and below.
class FullScreenAlertPermission {
  static const _channel = MethodChannel('lk.ziggo.app/ride_alert');

  /// Asked at most once per app launch so a driver who declines isn't nagged
  /// every time they open the home screen.
  static bool _askedThisSession = false;

  static Future<bool> isGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('canUseFullScreenIntent');
      return ok ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  static Future<void> openSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('openFullScreenIntentSettings');
    } catch (_) {}
  }

  /// Explain why it's needed, then hand off to Settings. Safe to call on every
  /// driver-home build — it self-limits.
  static Future<void> ensureGranted(BuildContext context) async {
    if (!Platform.isAndroid || _askedThisSession) return;
    if (await isGranted()) return;
    _askedThisSession = true;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppStyles.radiusLg),
        ),
        title: const Text('Allow full-screen ride alerts'),
        content: const Text(
          'Android needs your permission to show ride requests as a full-screen '
          'call, even when your phone is locked.\n\n'
          'Without it you will only get a small banner and may miss rides.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () {
              Navigator.of(ctx).pop();
              openSettings();
            },
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }
}
