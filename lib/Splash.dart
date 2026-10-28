import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soundclock/GetStarted.dart';
import 'package:soundclock/sc_theme.dart';

/// Purane naam (MelodyColors) yahan isliye rakhe hain taake Login.dart jaisi
/// files jo inhe use karti hain, bina badlaav ke compile hoti rahein.
/// Values ab naye SoundClock theme ki hain.
class MelodyColors {
  static const Color bg = SC.bg;
  static const Color bgLight = SC.surfaceHi;
  static const Color deepOrange = SC.primaryDeep;
  static const Color orange = SC.primary;
  static const Color amber = SC.violet;
  static const Color surface = SC.surface;
  static const Color cyan = SC.cyan;
}

// Loading ke baad Get Started screen khol do.
void _openGetStarted(BuildContext context) {
  if (!context.mounted) return;

  Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, animation, secondaryAnimation) {
        return GetStartedScreen(onGetStarted: () {});
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        );
      },
    ),
  );
}

// main.dart mein home: Splash() use karein.
class Splash extends StatelessWidget {
  const Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return const MelodyLoadingScreen();
  }
}

class MelodyLoadingScreen extends StatefulWidget {
  const MelodyLoadingScreen({
    super.key,
    this.duration = const Duration(seconds: 4),
    this.onComplete,
  });

  final Duration duration;
  final VoidCallback? onComplete;

  @override
  State<MelodyLoadingScreen> createState() => _MelodyLoadingScreenState();
}

class _MelodyLoadingScreenState extends State<MelodyLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  bool _done = false;

  @override
  void initState() {
    super.initState();
    _progress.forward().whenComplete(_finish);
  }

  Future<void> _finish() async {
    // 100% ek lamha dikhne do.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || _done) return;
    _done = true;

    final cb = widget.onComplete;
    if (cb != null) {
      cb();
    } else {
      _openGetStarted(context);
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.bg,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _MountainPainter()),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                AnimatedBuilder(
                  animation: _loop,
                  builder: (context, _) => _LogoBars(t: _loop.value),
                ),
                const SizedBox(height: 22),
                const Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Sound',
                        style: TextStyle(color: Colors.white),
                      ),
                      TextSpan(
                        text: 'Clock',
                        style: TextStyle(color: SC.violet),
                      ),
                    ],
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Music  •  Anytime  •  Anywhere',
                  style: TextStyle(
                    color: Colors.white.withAlpha(200),
                    fontSize: 13,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(flex: 5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 56),
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: Curves.easeInOut.transform(_progress.value),
                          minHeight: 4,
                          backgroundColor: Colors.white.withAlpha(36),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(SC.violet),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Your Music, Your Time',
                  style: TextStyle(
                    color: Colors.white.withAlpha(170),
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated waveform logo (7 bars).
class _LogoBars extends StatelessWidget {
  const _LogoBars({required this.t});

  final double t;

  static const List<double> _base = [0.35, 0.6, 0.85, 1.0, 0.85, 0.6, 0.35];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 0; i < _base.length; i++)
            Container(
              width: 7,
              height: 14 +
                  56 *
                      _base[i] *
                      (0.7 + 0.3 * math.sin(2 * math.pi * t + i * 0.9)),
              margin: const EdgeInsets.symmetric(horizontal: 3.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [SC.cyan, SC.primary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: SC.primary.withAlpha(90),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sunset sky + 3 layers of purple mountains.
class _MountainPainter extends CustomPainter {
  const _MountainPainter();

  void _ridge(Canvas canvas, Size s, List<Offset> pts, Color color) {
    final path = Path()..moveTo(0, s.height);
    for (final o in pts) {
      path.lineTo(o.dx * s.width, o.dy * s.height);
    }
    path
      ..lineTo(s.width, s.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF060A1C),
            Color(0xFF1A1450),
            Color(0xFF4A2A8C),
            Color(0xFFC2548A),
            Color(0xFFFF9A5C),
          ],
          stops: [0, 0.35, 0.58, 0.8, 1],
        ).createShader(rect),
    );

    _ridge(
      canvas,
      size,
      const [
        Offset(0, 0.70),
        Offset(0.18, 0.62),
        Offset(0.32, 0.72),
        Offset(0.50, 0.60),
        Offset(0.70, 0.74),
        Offset(0.88, 0.64),
        Offset(1, 0.72),
      ],
      const Color(0xFF3B2A7A),
    );

    _ridge(
      canvas,
      size,
      const [
        Offset(0, 0.80),
        Offset(0.20, 0.72),
        Offset(0.40, 0.82),
        Offset(0.62, 0.70),
        Offset(0.82, 0.83),
        Offset(1, 0.76),
      ],
      const Color(0xFF241A5C),
    );

    _ridge(
      canvas,
      size,
      const [
        Offset(0, 0.90),
        Offset(0.25, 0.84),
        Offset(0.50, 0.92),
        Offset(0.75, 0.85),
        Offset(1, 0.91),
      ],
      const Color(0xFF120E36),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
