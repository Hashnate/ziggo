import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/app_colors.dart';
import '../../app/app_styles.dart';

/// Shared dark theme tokens for the driver side of the app (PickMe-style navy).
/// Use [driverDarkTheme] to wrap a driver screen's Scaffold so default text,
/// icons, inputs, app bars and dividers flip to the dark palette automatically.
const Color kDriverBg = Color(0xFF12151C);
const Color kDriverCard = Color(0xFF1B1E25);
const Color kDriverCardLight = Color(0xFF262A33);
const Color kDriverGold = AppColors.accent;

ThemeData driverDarkTheme(BuildContext context) {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: kDriverBg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primaryLight,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      surface: kDriverCard,
      onSurface: Colors.white,
      error: AppColors.error,
    ),
    textTheme: GoogleFonts.outfitTextTheme(Theme.of(context).textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kDriverBg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    ),
    iconTheme: const IconThemeData(color: Colors.white),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kDriverCardLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w500),
      prefixIconColor: Colors.white54,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusSm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusSm),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppStyles.radiusSm),
        borderSide: const BorderSide(color: AppColors.primaryLight, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: Colors.white12,
      thickness: 1,
      space: 1,
    ),
  );
}
