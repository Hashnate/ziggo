import 'package:flutter/material.dart';

/// The Ziggo brand wordmark — renders the official PNG. On dark backgrounds
/// the mark is tinted white via a ColorFilter so it sits cleanly on the
/// gradient without needing a chip or pill backing.
class ZiggoWordmark extends StatelessWidget {
  final bool onDark;
  final double size;

  const ZiggoWordmark({super.key, this.onDark = false, this.size = 24});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      onDark ? 'assets/images/dark.png' : 'assets/images/light.png',
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
