import 'package:flutter/material.dart';

/// Premium motion primitives — entrance animations and tactile press feedback.
/// Use these liberally across screens to lift the app from "static" to "alive".

/// App-wide page transition — a smooth fade + subtle slide-up. Wired into the
/// theme so every screen navigation feels polished, not abrupt.
class PremiumPageTransitionsBuilder extends PageTransitionsBuilder {
  const PremiumPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Fades + slides a child up into place when it first mounts. Give siblings an
/// increasing [delay] to get a staggered, cascading reveal.
class EntranceSlide extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;
  final Curve curve;

  const EntranceSlide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 480),
    this.offsetY = 26,
    this.curve = Curves.easeOutCubic,
  });

  @override
  State<EntranceSlide> createState() => _EntranceSlideState();
}

class _EntranceSlideState extends State<EntranceSlide>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final AnimationController _ctrl;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final curved = CurvedAnimation(parent: _ctrl, curve: widget.curve);
    return AnimatedBuilder(
      animation: curved,
      builder: (_, child) {
        return Opacity(
          opacity: curved.value,
          child: Transform.translate(
            offset: Offset(0, widget.offsetY * (1 - curved.value)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Convenience: wraps each child of a column/list in a staggered [EntranceSlide].
List<Widget> staggered(
  List<Widget> children, {
  Duration step = const Duration(milliseconds: 70),
  Duration start = Duration.zero,
}) {
  return List.generate(children.length, (i) {
    return EntranceSlide(
      delay: start + step * i,
      child: children[i],
    );
  });
}

/// Wraps a tappable surface so it scales down slightly while pressed — the
/// tactile feedback premium apps use everywhere.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final Duration duration;
  final BorderRadius? borderRadius;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
    this.duration = const Duration(milliseconds: 110),
    this.borderRadius,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: widget.duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// A slow, looping shimmer sweep — place over a gradient hero/card as a sheen.
class Sheen extends StatefulWidget {
  final Widget child;
  final Duration duration;
  const Sheen({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 2800),
  });

  @override
  State<Sheen> createState() => _SheenState();
}

class _SheenState extends State<Sheen> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _ctrl,
                builder: (_, __) {
                  final t = _ctrl.value;
                  return ShaderMask(
                    blendMode: BlendMode.srcATop,
                    shaderCallback: (rect) => LinearGradient(
                      begin: Alignment(-1.4 + 2.8 * t, -1),
                      end: Alignment(-1.0 + 2.8 * t, 1),
                      colors: const [
                        Color(0x00FFFFFF),
                        Color(0x40FFFFFF),
                        Color(0x00FFFFFF),
                      ],
                      stops: const [0.35, 0.5, 0.65],
                    ).createShader(rect),
                    child: Container(color: Colors.white),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
