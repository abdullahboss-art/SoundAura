import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:soundclock/Bottom.dart'; // MainShell (bottom nav bar)
import 'package:soundclock/Signup.dart'; // SignUpScreen

/// Logo image ka path. Agar aapki file ka naam alag hai to sirf yahan badlein.
/// pubspec.yaml mein ye asset register hona zaroori hai.
const String kLogoAsset = 'assets/images/logo.png';

/// Theme colors: yahan badlein, poori screen change ho jayegi.
/// NOTE: signup_page.dart mein bhi yehi class hai. Dono files ek hi jagah
/// import karein to isay alag file (app_colors.dart) mein rakh dein.
class AppColors {
  static const background = Color(0xFF060A1C);
  static const surface = Color(0xFF0E1433);
  static const fieldBorder = Color(0xFF2C3A9E);
  static const primary = Color(0xFF8B5CF6); // neon purple
  static const gradientStart = Color(0xFF8B5CF6); // purple
  static const gradientEnd = Color(0xFF3B82F6); // blue
  static const textSecondary = Colors.white54;
}

class LoginPage extends StatefulWidget {
  final VoidCallback? onSuccess;
  const LoginPage({super.key, this.onSuccess});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool googleLoading = false;
  bool appleLoading = false;
  bool obscurePassword = true;
  bool rememberMe = true;

  void _goHome() {
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => const MainShell(),
      ),
      (route) => false,
    );
  }

  void _goSignUp() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SignUpScreen()),
    );
  }

  void showAlertDialog({
    required String title,
    required String message,
    bool isSuccess = false,
    String? userName,
    bool goHomeOnOk = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.fieldBorder),
        ),
        backgroundColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSuccess ? Icons.check_circle : Icons.error,
                  color: isSuccess ? AppColors.primary : Colors.redAccent,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ],
            ),
            if (userName != null) ...[
              const SizedBox(height: 8),
              Text(
                userName,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (goHomeOnOk) _goHome();
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('OK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() => loading = true);

      // Web par "Remember me" ke hisaab se session persistence set hoti hai.
      // Android/iOS par Firebase login by default yaad rakhta hai.
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(
          rememberMe ? Persistence.LOCAL : Persistence.SESSION,
        );
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      if (!mounted) return;
      setState(() => loading = false);
      _goHome(); // seedha bottom nav wali screen
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => loading = false);

      String msg;
      switch (e.code) {
        case 'user-not-found':
          msg = 'No account found with this email.';
          break;
        case 'wrong-password':
        case 'invalid-credential':
          msg = 'Incorrect email or password.';
          break;
        case 'invalid-email':
          msg = 'Email address is not valid.';
          break;
        case 'user-disabled':
          msg = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          msg = 'Too many failed attempts. Please try again later.';
          break;
        case 'network-request-failed':
          msg = 'No internet connection. Please check your network.';
          break;
        default:
          msg = e.message ?? 'Login failed. Please try again.';
      }
      showAlertDialog(title: 'Login Failed', message: msg);
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      showAlertDialog(title: 'Error', message: 'Something went wrong. Please try again later.');
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      setState(() => googleLoading = true);

      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      } else {
        await GoogleSignIn.instance.signOut();
        final googleUser = await GoogleSignIn.instance.authenticate();
        final idToken = googleUser.authentication.idToken;

        await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken),
        );
      }

      if (!mounted) return;
      setState(() => googleLoading = false);
      _goHome(); // seedha home
    } on GoogleSignInException catch (e) {
      if (!mounted) return;
      setState(() => googleLoading = false);
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      showAlertDialog(title: 'Google Sign-In Failed', message: e.toString());
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => googleLoading = false);
      showAlertDialog(title: 'Google Sign-In Failed', message: e.message ?? e.code);
    } catch (e) {
      if (!mounted) return;
      setState(() => googleLoading = false);
      showAlertDialog(title: 'Google Sign-In Failed', message: e.toString());
    }
  }

  /// Apple Sign-In: Firebase Console mein Apple provider enable karna hoga.
  /// iOS par Xcode mein "Sign in with Apple" capability bhi add karein.
  Future<void> signInWithApple() async {
    try {
      setState(() => appleLoading = true);

      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');

      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        await FirebaseAuth.instance.signInWithProvider(provider);
      }

      if (!mounted) return;
      setState(() => appleLoading = false);
      _goHome(); // seedha home
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => appleLoading = false);
      if (e.code == 'canceled' ||
          e.code == 'popup-closed-by-user' ||
          e.code == 'web-context-canceled') return;
      showAlertDialog(title: 'Apple Sign-In Failed', message: e.message ?? e.code);
    } catch (e) {
      if (!mounted) return;
      setState(() => appleLoading = false);
      showAlertDialog(title: 'Apple Sign-In Failed', message: e.toString());
    }
  }

  Future<void> _handleForgotPassword() async {
    final controller = TextEditingController(text: emailController.text);

    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.fieldBorder),
        ),
        title: const Text(
          'Reset Password',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your email',
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: AppColors.background,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Send Link', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    controller.dispose();

    if (email == null || email.trim().isEmpty) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
      if (!mounted) return;
      showAlertDialog(
        title: 'Email Sent',
        message: 'A password reset link has been sent to ${email.trim()}.',
        isSuccess: true,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      showAlertDialog(title: 'Reset Failed', message: e.message ?? 'Could not send reset email.');
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color c, [double w = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: c, width: w),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white54),
      prefixIcon: Icon(icon, color: Colors.white70),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      enabledBorder: border(AppColors.fieldBorder),
      border: border(AppColors.fieldBorder),
      focusedBorder: border(AppColors.primary, 1.6),
      errorBorder: border(Colors.redAccent),
      focusedErrorBorder: border(Colors.redAccent, 1.6),
    );
  }

  Widget _socialCircle({
    required Widget child,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF111A4A), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo (bina shadow ke)
                      Center(
                        child: Column(
                          children: [
                            ClipOval(
                              child: Image.asset(
                                kLogoAsset,
                                width: 84,
                                height: 84,
                                fit: BoxFit.cover,
                                // Image na mile to purana EqLogo dikhega
                                errorBuilder: (_, __, ___) =>
                                    const EqLogo(size: 64),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Sound',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  TextSpan(
                                    text: 'Aura',
                                    style: TextStyle(color: Color(0xFF9DA8FF)),
                                  ),
                                ],
                              ),
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Music  •  Anytime  •  Anywhere',
                              style: TextStyle(color: Color(0xFF8EA2FF), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),

                      const Text(
                        'Welcome Back!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Log in to continue your music journey.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 22),

                      // Email
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: AppColors.primary,
                        decoration: _fieldDecoration(
                            hint: 'Email or Username', icon: Icons.mail_outline),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter email';
                          // Firebase Auth ko email chahiye hota hai
                          if (!v.contains('@')) return 'Enter valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Password
                      TextFormField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        style: const TextStyle(color: Colors.white),
                        cursorColor: AppColors.primary,
                        decoration: _fieldDecoration(
                          hint: 'Password',
                          icon: Icons.lock_outline,
                          suffix: IconButton(
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.white54,
                            ),
                            onPressed: () =>
                                setState(() => obscurePassword = !obscurePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Please enter password';
                          if (v.length < 6) return 'Password must be at least 6 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),

                      // Remember me + Forgot password
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: rememberMe,
                              activeColor: AppColors.primary,
                              checkColor: Colors.white,
                              side: const BorderSide(color: AppColors.primary, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5)),
                              onChanged: (v) => setState(() => rememberMe = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => setState(() => rememberMe = !rememberMe),
                            child: const Text(
                              'Remember me',
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: _handleForgotPassword,
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(color: Color(0xFF8EA2FF), fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Login gradient button
                      Opacity(
                        opacity: loading ? 0.7 : 1,
                        child: Container(
                          width: double.infinity,
                          height: 55,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              colors: [AppColors.gradientStart, AppColors.gradientEnd],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.gradientStart.withValues(alpha: 0.45),
                                blurRadius: 18,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: loading ? null : loginUser,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              disabledBackgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28)),
                            ),
                            child: loading
                                ? const EqLoader(size: 24)
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Login',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward_rounded,
                                          color: Colors.white, size: 22),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      const Row(
                        children: [
                          Expanded(child: Divider(color: Colors.white12)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('OR',
                                style: TextStyle(color: Colors.white54, fontSize: 12)),
                          ),
                          Expanded(child: Divider(color: Colors.white12)),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Google button (white)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: googleLoading ? null : signInWithGoogle,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            disabledBackgroundColor: Colors.white70,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(26)),
                          ),
                          child: googleLoading
                              ? const EqLoader(size: 22)
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/images/google_logo.png',
                                      width: 30,
                                      height: 30,
                                      errorBuilder: (_, __, ___) => const Text(
                                        'G',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF4285F4),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Continue with Google',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Don't have an account?
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("Don't have an account? ",
                                style: TextStyle(color: Colors.white70, fontSize: 13)),
                            GestureDetector(
                              onTap: _goSignUp,
                              child: const Text(
                                'Sign Up',
                                style: TextStyle(
                                  color: AppColors.gradientStart,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// SoundClock logo aur loader.
// NOTE: Ye PUBLIC hain (EqLogo / EqLoader) taake Signup.dart bhi use kar sake.
// -----------------------------------------------------------------------------

class EqLogo extends StatelessWidget {
  final double size;

  const EqLogo({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: const _EqBarsPainter(),
    );
  }
}

class _EqBarsPainter extends CustomPainter {
  const _EqBarsPainter();

  static const List<double> _heights = [0.45, 0.75, 1.0, 0.75, 0.5];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.gradientStart, AppColors.gradientEnd],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);

    final n = _heights.length;
    final slot = size.width / n;
    final barW = slot * 0.62;

    for (var i = 0; i < n; i++) {
      final h = size.height * _heights[i];
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
  bool shouldRepaint(covariant _EqBarsPainter old) => false;
}

/// Naachti hui neon bars wala loader.
class EqLoader extends StatefulWidget {
  final double size;

  const EqLoader({super.key, required this.size});

  @override
  State<EqLoader> createState() => _EqLoaderState();
}

class _EqLoaderState extends State<EqLoader>
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
                      colors: [AppColors.gradientStart, AppColors.gradientEnd],
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