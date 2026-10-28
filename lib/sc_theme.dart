import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:soundclock/theme_controller.dart';

/// SoundClock design system (dark navy + purple neon).
/// Saare pages yahin ke colors / widgets use karte hain, taake theme ek jagah se badal sake.
///
/// Is file mein dono tarah ke naam hain (purane aur naye), taake koi file na toote:
///   colors:   bg, bgAlt, surface, surfaceHi, border, primary, primaryDeep, violet,
///             blue, cyan, pink, gold, danger, purple, accent
///   gradient: brand, brandDiag, gradient, gradientDiagonal
///   helpers:  card(), glow(), glowBox()
///   widgets:  ScLogo, ScLoader, ScLoading, ScGradientButton, ScOutlineButton,
///             ScPlayNowPill, SCGradientButton
class SC {
  SC._();

  static const String appName = 'SoundClock';

  // Backgrounds
  static const Color bg = Color(0xFF060A1C);
  static const Color bgAlt = Color(0xFF0A1030);
  static const Color surface = Color(0xFF0F1538);
  static const Color surfaceHi = Color(0xFF171F52);
  static const Color border = Color(0xFF262F73);

  // Brand
  static const Color primary = Color(0xFF7C5CFF);
  static const Color primaryDeep = Color(0xFF5A3BF0);
  static const Color violet = Color(0xFFA77BFF);
  static const Color blue = Color(0xFF4A8BFF);
  static const Color cyan = Color(0xFF3CC8FF);
  static const Color pink = Color(0xFFFF5FA2);
  static const Color gold = Color(0xFFFFC043);
  static const Color danger = Color(0xFFFF5A6E);

  // Alias / extra naam
  static const Color purple = primary;
  static const Color accent = Color(0xFF8EA2FF); // artist naam / chhota text

  static const LinearGradient brand = LinearGradient(
    colors: [primaryDeep, violet],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient brandDiag = LinearGradient(
    colors: [blue, primary, violet],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient gradient = LinearGradient(
    colors: [primary, blue],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient gradientDiagonal = LinearGradient(
    colors: [primary, blue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ---------------------------------------------------------------------------
  // THEME-AWARE RANG (Dark / Light). Purane naam upar jaise the waise hi hain.
  // Naye screens yahi use karte hain; Dark me values bilkul purani wali hain.
  // ---------------------------------------------------------------------------

  static bool get isDark =>
      AppThemeController.themeMode.value != ThemeMode.light;

  static Color get pageBg => isDark ? bg : const Color(0xFFF4F2FF);
  static Color get pageBgAlt => isDark ? bgAlt : const Color(0xFFFFFFFF);
  static Color get cardBg => isDark ? surface : const Color(0xFFFFFFFF);
  static Color get cardBgHi => isDark ? surfaceHi : const Color(0xFFEBE7FF);
  static Color get line => isDark ? border : const Color(0xFFDCD6F7);

  static Color get text => isDark ? Colors.white : const Color(0xFF14102E);
  static Color get textSoft => isDark ? Colors.white70 : const Color(0xFF4B4768);
  static Color get textFaint =>
      isDark ? Colors.white54 : const Color(0xFF7C789A);
  static Color get textHint =>
      isDark ? Colors.white38 : const Color(0xFF9B97B5);

  static Color get textMid => isDark ? Colors.white60 : const Color(0xFF5B5778);

  /// Chhoti lakeeren / handle bar (Dark me white24).
  static Color get stroke => isDark ? Colors.white24 : const Color(0xFFDCD6F7);

  /// Progress bar ka peeche wala rang, halki lakeeren.
  static Color get overlay =>
      isDark ? Colors.white12 : const Color(0x1F14102E);

  /// Artist naam / chhota highlight text (Dark me cyan, Light me gehra neela).
  static Color get accentText => isDark ? cyan : const Color(0xFF0B86B5);

  /// Purple text / icon (Dark me violet, Light me gehra purple).
  static Color get link => isDark ? violet : primaryDeep;

  /// Card jo theme ke hisaab se badalta hai (purana card() waisa hi hai).
  static BoxDecoration themedCard({double radius = 16, bool glow = false}) {
    return BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: line),
      boxShadow: glow
          ? [BoxShadow(color: primary.withAlpha(isDark ? 60 : 38), blurRadius: 18)]
          : null,
    );
  }

  static BoxDecoration themedGlowBox({double radius = 18, Color? fill}) {
    return BoxDecoration(
      color: fill ?? cardBg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: line.withValues(alpha: 0.9)),
      boxShadow: glow(isDark ? 0.18 : 0.10, 14),
    );
  }

  /// Standard dark card with thin indigo border (optional soft purple glow).
  static BoxDecoration card({double radius = 16, bool glow = false}) {
    return BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
      boxShadow: glow
          ? [BoxShadow(color: primary.withAlpha(60), blurRadius: 18)]
          : null,
    );
  }

  /// Neon glow (card / cover ke peeche).
  static List<BoxShadow> glow([double alpha = 0.35, double blur = 18]) => [
        BoxShadow(
          color: primary.withValues(alpha: alpha),
          blurRadius: blur,
        ),
      ];

  /// Neon border wala card.
  static BoxDecoration glowBox({double radius = 18, Color? fill}) {
    return BoxDecoration(
      color: fill ?? surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border.withValues(alpha: 0.9)),
      boxShadow: glow(0.18, 14),
    );
  }
}

// -----------------------------------------------------------------------------
// Logo (equalizer bars)
// -----------------------------------------------------------------------------

class ScLogo extends StatelessWidget {
  final double size;

  const ScLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: const _BarsPainter([0.45, 0.75, 1.0, 0.75, 0.5]),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final List<double> heights;

  const _BarsPainter(this.heights);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [SC.violet, SC.blue],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);

    final n = heights.length;
    final slot = size.width / n;
    final barW = slot * 0.62;

    for (var i = 0; i < n; i++) {
      final h = size.height * heights[i];
      final x = i * slot + (slot - barW) / 2;
      final y = (size.height - h) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barW, h),
          Radius.circular(barW / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.heights != heights;
}

// -----------------------------------------------------------------------------
// Loader (naachti hui equalizer bars)
// -----------------------------------------------------------------------------

class ScLoader extends StatefulWidget {
  final double size;

  const ScLoader({super.key, this.size = 40});

  @override
  State<ScLoader> createState() => _ScLoaderState();
}

class _ScLoaderState extends State<ScLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final barW = s / 9;

    return SizedBox(
      height: s,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < 5; i++)
                Container(
                  width: barW,
                  height: s *
                      (0.25 +
                          0.75 *
                              math.sin(_c.value * 2 * math.pi + i * 0.9).abs()),
                  margin: EdgeInsets.symmetric(horizontal: barW / 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [SC.primary, SC.blue],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(barW),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Poori screen ka loader (center mein loader + optional text).
class ScLoading extends StatelessWidget {
  final String? message;

  const ScLoading({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ScLoader(size: 46),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              style: TextStyle(color: SC.textSoft, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Buttons
// -----------------------------------------------------------------------------

class ScGradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;

  const ScGradientButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: SC.gradient,
          borderRadius: BorderRadius.circular(height / 2),
          boxShadow: SC.glow(0.35, 14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white, size: 22),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScOutlineButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;

  const ScOutlineButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: SC.cardBg,
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: SC.line),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(height / 2),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: SC.text, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: SC.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Banner par "Play Now" chhota gradient pill.
class ScPlayNowPill extends StatelessWidget {
  const ScPlayNowPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        gradient: SC.gradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: SC.glow(0.4, 12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
          SizedBox(width: 4),
          Text(
            'Play Now',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Purple gradient pill button (Get Started, Start Download, Play...).
/// (Aap ki purani files isi naam se use karti hain.)
class SCGradientButton extends StatelessWidget {
  const SCGradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.height = 54,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);

    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: SC.brand,
          boxShadow: [
            BoxShadow(
              color: SC.primary.withAlpha(110),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: busy ? null : onTap,
            child: Center(
              child: busy
                  ? const ScLoader(size: 22)
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                        ],
                        Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}