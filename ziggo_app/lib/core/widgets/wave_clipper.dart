import 'package:flutter/material.dart';

/// Smooth curved-bottom shape for hero headers.
class WaveClipper extends CustomClipper<Path> {
  final double height;
  WaveClipper({this.height = 28});

  @override
  Path getClip(Size size) {
    final p = Path();
    p.lineTo(0, size.height - height);
    p.quadraticBezierTo(
      size.width / 4, size.height + 4,
      size.width / 2, size.height - height / 2,
    );
    p.quadraticBezierTo(
      size.width * 3 / 4, size.height - height - 6,
      size.width, size.height - height,
    );
    p.lineTo(size.width, 0);
    p.close();
    return p;
  }

  @override
  bool shouldReclip(CustomClipper<Path> old) => false;
}

/// Wraps a hero header in a wave-clipped container with the given gradient.
class WaveHeader extends StatelessWidget {
  final LinearGradient gradient;
  final Widget child;
  final double waveHeight;

  const WaveHeader({
    super.key,
    required this.gradient,
    required this.child,
    this.waveHeight = 28,
  });

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: WaveClipper(height: waveHeight),
      child: Container(
        decoration: BoxDecoration(gradient: gradient),
        padding: EdgeInsets.only(bottom: waveHeight + 8),
        child: child,
      ),
    );
  }
}
