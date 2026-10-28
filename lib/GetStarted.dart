import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soundclock/Bottom.dart';
import 'package:soundclock/Login.dart';
import 'package:soundclock/sc_theme.dart';

class GetStartedScreen extends StatefulWidget {
  const GetStartedScreen({
    super.key,
    required this.onGetStarted,
  });

  final VoidCallback onGetStarted;

  @override
  State<GetStartedScreen> createState() => _GetStartedScreenState();
}

class _GetStartedScreenState extends State<GetStartedScreen> {
  static const String _bgAsset = 'assets/images/Background_image.png';
  static const String _personAsset = 'assets/images/person1.png';
  static const String _logoAsset = 'assets/images/logo.png';

  // Login logic pehle jaisa hi hai: user logged-in ho to seedha app, warna Login.
  Future<void> _openLogin() async {
    final user = FirebaseAuth.instance.currentUser;

    if (!mounted) return;

    if (user != null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const MainShell()),
        (route) => false,
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: SC.bg,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _background(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height * 0.62,
              child: Image.asset(
                _personAsset,
                fit: BoxFit.contain,
                alignment: Alignment.bottomCenter,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    SC.bg.withAlpha(190),
                    Colors.transparent,
                    Colors.transparent,
                    SC.bg.withAlpha(235),
                  ],
                  stops: const [0, 0.32, 0.55, 1],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  _logo(),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                          ),
                          children: [
                            TextSpan(text: 'Sound'),
                            TextSpan(
                              text: 'Clock',
                              style: TextStyle(color: SC.violet),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Your Music. Anytime. Anywhere.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withAlpha(230),
                        fontSize: 15,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                top: false,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 24 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: SCGradientButton(
                          label: 'Get Started',
                          height: 56,
                          onTap: _openLogin,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _features(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _background() {
    return Image.asset(
      _bgAsset,
      fit: BoxFit.cover,
      alignment: Alignment.bottomCenter,
      errorBuilder: (_, __, ___) {
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF060A1C),
                Color(0xFF2A1F6B),
                Color(0xFF8A3F8F),
                Color(0xFF120E36),
              ],
              stops: [0, 0.45, 0.75, 1],
            ),
          ),
        );
      },
    );
  }

  Widget _logo() {
    return Image.asset(
      _logoAsset,
      height: 88,
      errorBuilder: (_, __, ___) {
        return Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: SC.brandDiag,
            boxShadow: [
              BoxShadow(color: SC.primary.withAlpha(110), blurRadius: 24),
            ],
          ),
          child: const Icon(
            Icons.graphic_eq_rounded,
            color: Colors.white,
            size: 48,
          ),
        );
      },
    );
  }

  Widget _features() {
    final style = TextStyle(
      color: Colors.white.withAlpha(220),
      fontSize: 13,
    );

    Widget dot() {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: SC.violet,
            shape: BoxShape.circle,
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Stream', style: style),
        dot(),
        Text('Download', style: style),
        dot(),
        Text('Enjoy Offline', style: style),
      ],
    );
  }
}
