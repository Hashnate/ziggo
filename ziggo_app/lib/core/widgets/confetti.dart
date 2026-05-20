import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lightweight confetti — no external packages. Fires once when [trigger] flips
/// (e.g., success moment). Wrap any screen content in this to overlay confetti.
class Confetti extends StatefulWidget {
  final bool trigger;
  final Widget child;
  final int particleCount;

  const Confetti({
    super.key,
    required this.trigger,
    required this.child,
    this.particleCount = 80,
  });

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late List<_Particle> _particles;
  bool _firedFor = false;

  static const _palette = [
    Color(0xFFFFD100),
    Color(0xFFFF7849),
    Color(0xFF22C55E),
    Color(0xFF3B82F6),
    Color(0xFFEC4899),
    Color(0xFFA855F7),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _particles = _generate();
    if (widget.trigger) _fire();
  }

  @override
  void didUpdateWidget(covariant Confetti oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger && !_firedFor) _fire();
    if (!widget.trigger) _firedFor = false;
  }

  void _fire() {
    _firedFor = true;
    setState(() => _particles = _generate());
    _ctrl.forward(from: 0);
  }

  List<_Particle> _generate() {
    final r = math.Random();
    return List.generate(widget.particleCount, (_) {
      return _Particle(
        x: r.nextDouble(),
        // Slight vertical clustering near the center on launch
        vx: (r.nextDouble() - 0.5) * 2.4,
        vy: -2 - r.nextDouble() * 2,
        color: _palette[r.nextInt(_palette.length)],
        size: 6 + r.nextDouble() * 6,
        rotation: r.nextDouble() * math.pi * 2,
        rotationSpeed: (r.nextDouble() - 0.5) * 8,
        shape: r.nextInt(2),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_firedFor)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) => CustomPaint(
                  painter: _ConfettiPainter(
                    particles: _particles,
                    t: _ctrl.value,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Particle {
  final double x;
  final double vx;
  final double vy;
  final Color color;
  final double size;
  final double rotation;
  final double rotationSpeed;
  final int shape;
  _Particle({
    required this.x,
    required this.vx,
    required this.vy,
    required this.color,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
    required this.shape,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;

  _ConfettiPainter({required this.particles, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final gravity = 9.0;
    final fade = (1 - t).clamp(0.0, 1.0);
    for (final p in particles) {
      // Position
      final x = p.x * size.width + p.vx * t * 100;
      final y = size.height * 0.4 + p.vy * t * 120 + gravity * t * t * 80;
      if (y > size.height + 20) continue;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.rotation + p.rotationSpeed * t);
      final paint = Paint()..color = p.color.withOpacity(fade);
      if (p.shape == 0) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
          paint,
        );
      } else {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
