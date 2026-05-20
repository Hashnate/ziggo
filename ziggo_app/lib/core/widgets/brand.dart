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
    final image = Image.asset(
      'assets/images/ziggo.png',
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (!onDark) return image;

    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      child: image,
    );
  }
}
