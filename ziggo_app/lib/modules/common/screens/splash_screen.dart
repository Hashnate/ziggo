import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/app_colors.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/motion.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _orbitController;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _scale = CurvedAnimation(parent: _logoController, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _logoController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            // Layered ambient glow blobs
            Positioned(
              top: -130,
              left: -90,
              child: _blob(260, Colors.white.withOpacity(0.08)),
            ),
            Positioned(
              bottom: -120,
              right: -70,
              child: _blob(220, AppColors.accent.withOpacity(0.16)),
            ),
            Positioned(
              top: 140,
              right: -60,
              child: _blob(140, AppColors.primaryLight.withOpacity(0.18)),
            ),
            // Soft orbiting dots for depth
            Center(
              child: AnimatedBuilder(
                animation: _orbitController,
                builder: (_, __) {
                  return SizedBox(
                    width: 320,
                    height: 320,
                    child: Stack(
                      alignment: Alignment.center,
                      children: List.generate(3, (i) {
                        final angle = _orbitController.value * 2 * math.pi +
                            i * (2 * math.pi / 3);
                        final r = 130.0 + i * 8;
                        return Transform.translate(
                          offset: Offset(
                            math.cos(angle) * r,
                            math.sin(angle) * r,
                          ),
                          child: Container(
                            width: 10 - i * 1.5,
                            height: 10 - i * 1.5,
                            decoration: BoxDecoration(
                              color: i == 1
                                  ? AppColors.accent.withOpacity(0.9)
                                  : Colors.white.withOpacity(0.7),
                              shape: BoxShape.circle,
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                },
              ),
            ),
            // Center brand lockup
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: _scale,
                    child: Container(
                      padding: const EdgeInsets.all(26),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withOpacity(0.28),
                            blurRadius: 50,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.asset(
                          'assets/images/logo.jpeg',
                          width: 96,
                          height: 96,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 34),
                  const EntranceSlide(
                    delay: Duration(milliseconds: 400),
                    child: ZiggoWordmark(onDark: true, size: 74),
                  ),
                  const SizedBox(height: 16),
                  EntranceSlide(
                    delay: const Duration(milliseconds: 600),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                        ),
                      ),
                      child: Text(
                        'Rides · Food · Market · Parcels',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Bottom loader + signature
            Positioned(
              bottom: 54,
              left: 0,
              right: 0,
              child: EntranceSlide(
                delay: const Duration(milliseconds: 750),
                child: Column(
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        color: Colors.white.withOpacity(0.85),
                        strokeWidth: 2.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'POWERED BY ZIGGO TECHNOLOGIES',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color, blurRadius: 80, spreadRadius: 20),
        ],
      ),
    );
  }
}
