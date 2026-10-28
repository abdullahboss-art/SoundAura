import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:soundclock/Splash.dart';
import 'package:soundclock/theme_controller.dart';
import 'package:soundclock/checkout_page.dart';
import 'package:soundclock/jazzcash_gateway.dart';
import 'package:soundclock/premium_service.dart';

import 'firebase_options.dart';

/// true  = asli JazzCash payment (Cloud Function deploy honi chahiye, billing chahiye).
/// false = TEST MODE (koi asli paisa nahi katta).
///         Wallet: hamesha success. Card 4242 4242 4242 4242 = success,
///         jo card 0000 par khatam ho = decline.
const bool _useJazzCash = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Pichla chunna hua theme (Dark / Light) wapas lao.
  await AppThemeController.load();

  // Premium ki halat load karo (dobara call karne se koi masla nahi, ek hi baar chalta hai).
  PremiumService.instance.init();

  // Payment gateway: checkout page isi ko call karta hai.
  // _useJazzCash false ho to MockPaymentGateway (default) chalta hai.
  if (_useJazzCash) {
    PaymentConfig.gateway = JazzCashGateway();
  }

  // Google Sign-In ek hi baar yahan initialize hota hai.
  // Web par ye zaroori nahi (web par Google login is app me supported nahi).
  if (!kIsWeb) {
    try {
      await GoogleSignIn.instance.initialize();
    } catch (e) {
      debugPrint('GoogleSignIn init error: $e');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeController.themeMode,
      builder: (context, themeMode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,

          // ===================== LIGHT THEME =====================
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF4F2FF),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF7C5CFF),
              brightness: Brightness.light,
              surface: Colors.white,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF4F2FF),
              foregroundColor: Color(0xFF14102E),
              elevation: 0,
            ),
            cardColor: Colors.white,
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.white,
            ),
          ),

          // ===================== DARK THEME ======================
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF07131B),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF2D6A75),
              brightness: Brightness.dark,
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF07131B),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            cardColor: const Color(0xFF0D1B24),
          ),

          home: const Splash(),
        );
      },
    );
  }
}