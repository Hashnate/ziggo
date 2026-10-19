import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_colors.dart';
import '../network/api_client.dart';

class AppUpdateService {
  static const String _keyLastPromptTime = 'app_update_last_soft_prompt_ms';
  static bool _isDialogShowing = false;

  /// Check app version and show force or soft update dialog if necessary.
  static Future<void> checkForUpdates(BuildContext context, {bool isManual = false}) async {
    // Only check on mobile devices
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }

    if (_isDialogShowing) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.trim(); // e.g. "1.0.15"

      final response = await ApiClient.client.get('/misc/app-version');
      if (response.statusCode != 200 || response.data == null) return;

      final data = response.data as Map<String, dynamic>;
      final platformKey = Platform.isIOS ? 'ios' : 'android';
      final platformConfig = (data[platformKey] as Map<String, dynamic>?) ?? {};

      final minVersion = (platformConfig['min_version'] as String?)?.trim() ?? '1.0.0';
      final latestVersion = (platformConfig['latest_version'] as String?)?.trim() ?? currentVersion;
      final storeUrl = platformConfig['store_url'] as String? ?? '';
      final marketUrl = platformConfig['market_url'] as String? ?? '';

      final title = (data['title'] as String?) ?? 'Update Available';
      final message = (data['message'] as String?) ??
          'A new version of Ziggo is ready with improvements and bug fixes.';
      final forceMessage = (data['force_message'] as String?) ??
          'This version of Ziggo is no longer supported. Please update to continue using Ziggo.';

      // Check if current version is below the minimum supported version (FORCE UPDATE)
      if (_compareVersions(currentVersion, minVersion) < 0) {
        if (!context.mounted) return;
        _isDialogShowing = true;
        await _showUpdateModal(
          context: context,
          title: 'Update Required',
          message: forceMessage,
          storeUrl: storeUrl,
          marketUrl: marketUrl,
          isForceUpdate: true,
          currentVersion: currentVersion,
          targetVersion: minVersion,
        );
        _isDialogShowing = false;
        return;
      }

      // Check if current version is below the latest version (SOFT UPDATE)
      if (_compareVersions(currentVersion, latestVersion) < 0) {
        // If not manual check, prompt soft update at most once every 24 hours
        if (!isManual) {
          final prefs = await SharedPreferences.getInstance();
          final lastPrompt = prefs.getInt(_keyLastPromptTime) ?? 0;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastPrompt < const Duration(hours: 24).inMilliseconds) {
            return;
          }
        }

        if (!context.mounted) return;
        _isDialogShowing = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_keyLastPromptTime, DateTime.now().millisecondsSinceEpoch);

        await _showUpdateModal(
          context: context,
          title: title,
          message: message,
          storeUrl: storeUrl,
          marketUrl: marketUrl,
          isForceUpdate: false,
          currentVersion: currentVersion,
          targetVersion: latestVersion,
        );
        _isDialogShowing = false;
      } else if (isManual && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are on the latest version of Ziggo!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('AppUpdateService.checkForUpdates failed: $e');
    }
  }

  /// Compares two semver strings (e.g. "1.0.15" vs "1.0.16").
  /// Returns:
  /// - negative if v1 < v2
  /// - 0 if v1 == v2
  /// - positive if v1 > v2
  static int _compareVersions(String v1, String v2) {
    try {
      final parts1 = v1.split('.').map((s) => int.tryParse(s.split('+').first) ?? 0).toList();
      final parts2 = v2.split('.').map((s) => int.tryParse(s.split('+').first) ?? 0).toList();

      final maxLength = parts1.length > parts2.length ? parts1.length : parts2.length;
      for (int i = 0; i < maxLength; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;
        if (p1 != p2) {
          return p1.compareTo(p2);
        }
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _launchStore(String marketUrl, String storeUrl) async {
    try {
      if (marketUrl.isNotEmpty) {
        final marketUri = Uri.parse(marketUrl);
        if (await canLaunchUrl(marketUri)) {
          final ok = await launchUrl(marketUri, mode: LaunchMode.externalApplication);
          if (ok) return;
        }
      }
    } catch (_) {}

    try {
      if (storeUrl.isNotEmpty) {
        final webUri = Uri.parse(storeUrl);
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('Failed to launch store URL: $e');
    }
  }

  static Future<void> _showUpdateModal({
    required BuildContext context,
    required String title,
    required String message,
    required String storeUrl,
    required String marketUrl,
    required bool isForceUpdate,
    required String currentVersion,
    required String targetVersion,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      builder: (dialogCtx) {
        return PopScope(
          canPop: !isForceUpdate,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            elevation: 16,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isForceUpdate
                          ? AppColors.error.withOpacity(0.12)
                          : AppColors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isForceUpdate ? Icons.system_security_update_rounded : Icons.rocket_launch_rounded,
                      size: 32,
                      color: isForceUpdate ? AppColors.error : AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Installed: v$currentVersion → Available: v$targetVersion',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (!isForceUpdate) ...[
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: AppColors.cardBorder),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () => Navigator.of(dialogCtx).pop(),
                            child: const Text(
                              'Later',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isForceUpdate ? AppColors.error : AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            if (!isForceUpdate) {
                              Navigator.of(dialogCtx).pop();
                            }
                            _launchStore(marketUrl, storeUrl);
                          },
                          child: const Text(
                            'Update Now',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
