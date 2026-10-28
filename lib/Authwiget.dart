import 'package:flutter/material.dart';

class AuthColors {
  static const bg = Color(0xFF080C18);
  static const bgTop = Color(0xFF0B1226);
  static const field = Color(0xFF0D1B33);
  static const fieldBorder = Color(0xFF2A5CAA);
  static const fieldFocus = Color(0xFF4DA3FF);
  static const link = Color(0xFF2FB8FF);
  static const orange = Color(0xFFFF7A1A);
  static const amber = Color(0xFFFFB347);
  static const deepOrange = Color(0xFFFF4D00);
}

bool isValidEmail(String v) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

void showAuthMessage(BuildContext context, String message, {bool error = true}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? const Color(0xFFB3261E) : const Color(0xFF1E7B4F),
    ));
}

/// Dark page with scrolling content (keyboard safe).
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AuthColors.bgTop, AuthColors.bg],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: c.maxHeight - 48),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/images/logo.png',
          height: 72,
          errorBuilder: (_, __, ___) => Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AuthColors.amber, AuthColors.deepOrange],
              ),
            ),
            child: const Icon(Icons.music_note_rounded,
                color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 8),
        const Text.rich(
          TextSpan(
            style: TextStyle(
                color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
            children: [
              TextSpan(text: 'Melody'),
              TextSpan(
                  text: 'Hub', style: TextStyle(color: AuthColors.orange)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Your Music. Anytime. Anywhere.',
          style: TextStyle(color: AuthColors.link, fontSize: 12),
        ),
      ],
    );
  }
}

class AuthField extends StatefulWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.isPassword = false,
    this.keyboardType,
    this.validator,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isPassword;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _obscure = true;

  OutlineInputBorder _border(Color c, [double w = 1.2]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: widget.isPassword && _obscure,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      autofillHints: widget.autofillHints,
      cursorColor: AuthColors.fieldFocus,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(widget.icon, color: Colors.white70),
        suffixIcon: widget.isPassword
            ? IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.white70,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
        filled: true,
        fillColor: AuthColors.field,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: _border(AuthColors.fieldBorder),
        enabledBorder: _border(AuthColors.fieldBorder),
        focusedBorder: _border(AuthColors.fieldFocus, 1.8),
        errorBorder: _border(const Color(0xFFFF8A80)),
        focusedErrorBorder: _border(const Color(0xFFFF8A80), 1.8),
        errorStyle: const TextStyle(color: Color(0xFFFF8A80)),
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(27),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF8A2A), Color(0xFFE8467C)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE8467C).withAlpha(80),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(27),
          onTap: loading ? null : onPressed,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      if (icon != null) ...[
                        const SizedBox(width: 8),
                        Icon(icon, color: Colors.white, size: 20),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// White "Continue with Google" button.
/// Optional logo: assets/images/google_logo.png (a "G" is shown if missing).
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.onPressed, this.loading = false});

  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(27),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(27),
          onTap: loading ? null : onPressed,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Color(0xFF4285F4)),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/google_logo.png',
                        height: 24,
                        errorBuilder: (_, __, ___) => const Text('G',
                            style: TextStyle(
                                color: Color(0xFF4285F4),
                                fontSize: 24,
                                fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 12),
                      const Text('Continue with Google',
                          style: TextStyle(
                              color: Color(0xFF1F1F1F),
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    const line = Expanded(child: Divider(color: Colors.white24, height: 1));
    return const Row(
      children: [
        line,
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Text('OR', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        line,
      ],
    );
  }
}