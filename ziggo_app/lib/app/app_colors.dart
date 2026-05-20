import 'package:flutter/material.dart';

/// Dark-blue brand palette.
class AppColors {
  // Brand — deep royal blue
  static const Color primary = Color(0xFF1E40AF);       // blue-800
  static const Color primaryDark = Color(0xFF172554);   // blue-950
  static const Color primaryLight = Color(0xFF3B82F6);  // blue-500
  static const Color primarySoft = Color(0xFFDBEAFE);   // blue-100

  static const Color accent = Color(0xFFFBBF24);        // gold accent for premium/Gold tier
  static const Color secondary = Color(0xFF1F2937);

  // Surfaces — clean, airy, minimal (Foodix-style soft canvas)
  static const Color background = Color(0xFFF5F7FB);
  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF2F4F8);
  static const Color cardBorder = Color(0xFFEEF1F6);
  static const Color divider = Color(0xFFEFF1F5);

  // Text
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textTertiary = Color(0xFF94A3B8);
  static const Color textOnPrimary = Colors.white;

  // Semantic
  static const Color error = Color(0xFFEF4444);
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF0EA5E9);

  // Service brand colors (each vertical has its own accent)
  static const Color rides = primary;                 // dark blue
  static const Color food = Color(0xFFFF7849);        // orange
  static const Color flash = Color(0xFF06B6D4);       // cyan (moved off blue to avoid collision)
  static const Color market = Color(0xFF22C55E);      // green
  static const Color truck = Color(0xFFE11D48);       // rose
  static const Color bike = Color(0xFFA855F7);        // violet

  // Legacy aliases (kept to avoid widespread breakage)
  static const Color white = Colors.white;
  static const Color darkBlue = primaryDark;

  // Gradients
  /// Brand gradient — used on hero cards, buttons, FABs
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
  );

  /// Alias kept for back-compat with screens that still reference `goldGradient`
  static const LinearGradient goldGradient = primaryGradient;

  /// Real gold gradient — used ONLY for the "Ziggo Gold" subscription tier
  static const LinearGradient goldTierGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
  );

  static const LinearGradient blackGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFFFFF), Color(0xFFF1F5F9)],
  );

  static LinearGradient serviceGradient(Color base) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [base.withOpacity(0.85), base],
      );
}
