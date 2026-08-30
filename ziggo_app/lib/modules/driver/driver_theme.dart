import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/app_colors.dart';
import '../../app/app_styles.dart';

/// Shared theme tokens for the driver side of the app (matching light theme).
/// Use [driverTheme] to wrap a driver screen's Scaffold so default text,
/// icons, inputs, app bars and dividers flip to the light palette automatically.
const Color kDriverBg = AppColors.background;
const Color kDriverCard = AppColors.surface;
const Color kDriverCardLight = AppColors.surfaceMuted;
const Color kDriverGold = AppColors.accent;

ThemeData driverTheme(BuildContext context) {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    primaryColor: AppColors.primary,
    scaffoldBackgroundColor: kDriverBg,
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      surface: kDriverCard,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
    ),
    textTheme: GoogleFonts.poppinsTextTheme(Theme.of(context).textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: kDriverBg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      titleTextStyle: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w900,
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kDriverCardLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
      hintStyle: const TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w500),
      prefixIconColor: AppColors.textSecondary,
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
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
  );
}

// Keep a deprecated alias to avoid immediate compilation failure before updating other files
@deprecated
ThemeData driverDarkTheme(BuildContext context) => driverTheme(context);

