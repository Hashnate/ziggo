import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/app_colors.dart';

/// Frosted-glass card with a subtle gradient border. Use on top of a colored
/// background (gradient hero, map, ambient orbs) for that premium look.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;
  final Color? tint;
  final bool gradientBorder;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.blur = 24,
    this.tint,
    this.gradientBorder = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = tint ?? Colors.white.withOpacity(0.16);
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
          ),
          child: child,
        ),
      ),
    );

    if (!gradientBorder) return card;

    return Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent.withOpacity(0.6),
            Colors.white.withOpacity(0.25),
            AppColors.primaryLight.withOpacity(0.45),
          ],
        ),
      ),
      child: card,
    );
  }
}

/// Premium shimmer line — a slowly traveling highlight across a card. Place
/// inside a Stack as the top child of a hero card.
class ShimmerHighlight extends StatefulWidget {
  final double height;
  const ShimmerHighlight({super.key, this.height = 80});

  @override
  State<ShimmerHighlight> createState() => _ShimmerHighlightState();
}

class _ShimmerHighlightState extends State<ShimmerHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final t = _ctrl.value;
          return SizedBox(
            height: widget.height,
            child: ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment(-1 + 2 * t, -1),
                end: Alignment(0 + 2 * t, 1),
                colors: const [
                  Colors.transparent,
                  Color(0x55FFFFFF),
                  Colors.transparent,
                ],
                stops: const [0.35, 0.5, 0.65],
              ).createShader(rect),
              child: Container(color: Colors.white),
            ),
          );
        },
      ),
    );
  }
}
