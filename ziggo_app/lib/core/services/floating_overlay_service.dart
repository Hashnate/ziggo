import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FloatingOverlayService {
  static const MethodChannel _channel = MethodChannel('lk.ziggo.app/floating_widget');
  static const String _prefKey = 'driver_floating_widget_enabled';

  /// Returns true if floating overlays are supported on this platform (Android only).
  static bool get isSupported => Platform.isAndroid;

  /// Check whether the driver has enabled floating widget in app preferences.
  static Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_prefKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Update the driver's floating widget preference.
  static Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);
      if (!enabled) {
        await hideFloatingWidget();
      }
    } catch (_) {}
  }

  /// Check whether "Display over other apps" (SYSTEM_ALERT_WINDOW) permission is granted.
  static Future<bool> isPermissionGranted() async {
    if (!isSupported) return false;
    try {
      final bool? granted = await _channel.invokeMethod<bool>('canDrawOverlays');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Launch Android system settings to grant "Display over other apps" permission.
  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>('requestOverlayPermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Show the floating driver icon widget on top of all other apps.
  static Future<void> showFloatingWidget() async {
    if (!isSupported) return;
    final enabled = await isEnabled();
    if (!enabled) return;
    try {
      await _channel.invokeMethod('showFloatingWidget');
    } catch (_) {}
  }

  /// Hide/dismiss the floating driver icon widget.
  static Future<void> hideFloatingWidget() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('hideFloatingWidget');
    } catch (_) {}
  }

  /// Check if the floating widget is currently displaying.
  static Future<bool> isShowing() async {
    if (!isSupported) return false;
    try {
      final bool? showing = await _channel.invokeMethod<bool>('isFloatingWidgetShowing');
      return showing ?? false;
    } catch (_) {
      return false;
    }
  }
}
