import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Soft, slowly drifting colored orbs in the background. Adds depth + premium
/// feel without overpowering content. Stack this BEHIND your main widgets.
class AmbientOrbs extends StatefulWidget {
  final List<Color> colors;
  final int count;

  const AmbientOrbs({
    super.key,
    this.colors = const [
      Color(0xFF1E40AF),
      Color(0xFF3B82F6),
      Color(0xFFFBBF24),
    ],
    this.count = 3,
  });

  @override
  State<AmbientOrbs> createState() => _AmbientOrbsState();
}

class _AmbientOrbsState extends State<AmbientOrbs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _OrbPainter(t: _ctrl.value, colors: widget.colors, count: widget.count),
        size: Size.infinite,
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  final int count;

  _OrbPainter({required this.t, required this.colors, required this.count});

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < count; i++) {
      final phase = t * 2 * math.pi + i * (2 * math.pi / count);
      final cx = size.width * (0.3 + 0.4 * math.sin(phase));
      final cy = size.height * (0.3 + 0.4 * math.cos(phase * 0.8 + i));
      final radius = size.shortestSide * (0.45 + 0.05 * math.sin(phase * 1.3));

      final color = colors[i % colors.length];
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withOpacity(0.22),
            color.withOpacity(0.0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);

      canvas.drawCircle(Offset(cx, cy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) => old.t != t;
}
