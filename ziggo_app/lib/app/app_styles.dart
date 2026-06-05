import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared style tokens used across the app.
class AppStyles {
  // Radius — generous, rounded-everywhere (Foodix-style)
  static const double radiusXs = 12;
  static const double radiusSm = 16;
  static const double radiusMd = 22;
  static const double radiusLg = 28;
  static const double radiusXl = 36;

  // Spacing
  static const double spaceXs = 6;
  static const double spaceSm = 10;
  static const double spaceMd = 16;
  static const double spaceLg = 24;
  static const double spaceXl = 32;

  // Shadows — soft, diffuse, low-opacity (the signature soft-shadow look)
  static List<BoxShadow> get shadowSm => const [
        BoxShadow(color: Color(0x0D1A2B4A), blurRadius: 18, offset: Offset(0, 6)),
      ];
  static List<BoxShadow> get shadowMd => const [
        BoxShadow(color: Color(0x141A2B4A), blurRadius: 28, offset: Offset(0, 10)),
      ];
  static List<BoxShadow> get shadowLg => const [
        BoxShadow(color: Color(0x1F1A2B4A), blurRadius: 44, offset: Offset(0, 18)),
      ];
  static List<BoxShadow> get goldGlow => const [
        BoxShadow(color: Color(0x55FFD100), blurRadius: 24, spreadRadius: 1),
      ];

  // Card decorations — borderless, soft-shadowed by default
  static BoxDecoration card({double radius = radiusLg, bool bordered = false}) {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: bordered ? Border.all(color: AppColors.cardBorder) : null,
      boxShadow: shadowSm,
    );
  }

  static BoxDecoration glassCard({double radius = radiusMd}) {
    return BoxDecoration(
      color: AppColors.surface.withOpacity(0.92),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.6)),
      boxShadow: shadowMd,
    );
  }

  static BoxDecoration heroDark({double radius = radiusLg}) {
    return BoxDecoration(
      gradient: AppColors.blackGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: shadowLg,
    );
  }

  static BoxDecoration heroGold({double radius = radiusLg}) {
    return BoxDecoration(
      gradient: AppColors.goldGradient,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: goldGlow,
    );
  }

  // Text styles
  static const TextStyle title = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle h1 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w900,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: AppColors.textSecondary,
  );

  static const TextStyle label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w900,
    color: AppColors.textTertiary,
    letterSpacing: 1.4,
  );
}

/// Reusable widgets

class GlassPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? iconColor;
  const GlassPill({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(100),
          boxShadow: AppStyles.shadowSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: iconColor ?? AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                )),
          ],
        ),
      ),
    );
  }
}

class GradientServiceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isNew;
  final String? badgeText;

  /// Optional 3D illustration asset (e.g. 'assets/icons/food.png'). When set,
  /// the tile renders the illustration free-floating instead of the flat icon
  /// inside the navy badge.
  final String? imageAsset;

  const GradientServiceTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.isNew = false,
    this.badgeText,
    this.imageAsset,
  });

  Widget _glyph() {
    if (imageAsset != null) {
      return SizedBox(
        width: 70,
        height: 70,
        child: Image.asset(imageAsset!, fit: BoxFit.contain),
      );
    }
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E3A8A), Color(0xFF131C3D)],
        ),
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark.withOpacity(0.32),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 28),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              _glyph(),
              if (isNew || badgeText != null)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(badgeText ?? 'NEW',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        )),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool gold;
  final double height;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.busy = false,
    this.gold = false,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    // `gold` flag now means "filled brand" (primary blue with white text).
    // Default (gold=false) is the dark fallback used when a button sits on a
    // colored hero background and needs contrast.
    final bg = gold ? AppColors.primary : Colors.black;
    final fg = Colors.white;
    final enabled = !busy && onPressed != null;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppStyles.radiusMd),
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: bg.withOpacity(0.32),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ElevatedButton(
        onPressed: busy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppStyles.radiusMd),
          ),
          shadowColor: Colors.transparent,
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 0.6,
                      )),
                ],
              ),
      ),
    );
  }
}

/// Clean white card with a soft, diffuse shadow and generously rounded corners.
/// The default building block for the redesigned, minimalist surfaces.
class SoftCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;
  final List<BoxShadow>? shadow;

  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppStyles.spaceMd),
    this.radius = AppStyles.radiusLg,
    this.color,
    this.onTap,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ?? AppStyles.shadowSm,
      ),
      child: child,
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      ),
    );
  }
}
