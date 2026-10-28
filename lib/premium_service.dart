import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PremiumPlan { monthly, yearly }

/// Premium ki halat yahan rehti hai. Abhi local (SharedPreferences) me save
/// hoti hai taake bina payment ke poora flow test ho sake.
/// Baad me activate() / startTrial() ko RevenueCat / Firestore se jod dena.
class PremiumService extends ChangeNotifier {
  PremiumService._();
  static final PremiumService instance = PremiumService._();

  // Free plan ki hadein
  static const int freeDownloadLimit = 10;
  static const int freePlaylistLimit = 3;

  // Prices (apni marzi se badal lo). Baqi sab kuch inse khud calculate hota hai.
  static const int monthlyAmount = 299;
  static const int yearlyAmount = 2499;
  static const int trialDays = 7;

  static String get monthlyPrice => 'Rs $monthlyAmount / month';
  static String get yearlyPrice => 'Rs $yearlyAmount / year';

  /// Yearly lene par har mahine ka kharcha.
  static int get yearlyPerMonth => (yearlyAmount / 12).round();

  /// Yearly lene par monthly ke muqable mein kitni bachat (percent).
  static int get yearlySavingsPercent =>
      ((1 - yearlyAmount / (monthlyAmount * 12)) * 100).round();

  bool _isPremium = false;
  bool _isTrial = false;
  bool _trialUsed = false;
  PremiumPlan? _plan;
  DateTime? _expiry;

  bool get isPremium => _isPremium;

  /// True jab user free trial par ho.
  bool get isTrial => _isTrial;

  /// Free trial sirf ek baar milta hai.
  bool get canStartTrial => !_isPremium && !_trialUsed;

  PremiumPlan? get plan => _plan;
  DateTime? get expiry => _expiry;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? 'guest';
  String get _key => 'premium_$_uid';
  String get _trialKey => 'trial_used_$_uid';

  bool _inited = false;

  /// App shuru hote hi ek baar call karo (main.dart me ya PlayerService se).
  /// Login/logout badalne par premium ki halat khud dobara load hoti hai.
  void init() {
    if (_inited) return;
    _inited = true;
    load();
    FirebaseAuth.instance.authStateChanges().listen((_) => load());
  }

  /// Login ke baad ya profile khulte waqt call karo.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      _trialUsed = prefs.getBool(_trialKey) ?? false;
      _isPremium = false;
      _isTrial = false;
      _plan = null;
      _expiry = null;

      if (raw != null) {
        final parts = raw.split('|');
        if (parts.length == 2) {
          final exp = DateTime.tryParse(parts[1]);
          if (exp != null && exp.isAfter(DateTime.now())) {
            _isPremium = true;
            _isTrial = parts[0] == 'trial';
            _plan = parts[0] == 'yearly'
                ? PremiumPlan.yearly
                : PremiumPlan.monthly;
            _expiry = exp;
          } else {
            await prefs.remove(_key);
          }
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> activate(PremiumPlan plan) async {
    final now = DateTime.now();
    final exp = plan == PremiumPlan.yearly
        ? DateTime(now.year + 1, now.month, now.day)
        : DateTime(now.year, now.month + 1, now.day);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        '${plan == PremiumPlan.yearly ? 'yearly' : 'monthly'}|${exp.toIso8601String()}',
      );
    } catch (_) {}
    _isPremium = true;
    _isTrial = false;
    _plan = plan;
    _expiry = exp;
    notifyListeners();
  }

  /// Free trial shuru karta hai (trialDays tak poora premium).
  /// NOTE: Abhi ye sirf phone par save hota hai, to app dobara install karke
  /// trial dobara liya ja sakta hai. Real app mein ise RevenueCat / Google Play
  /// / App Store ke trial ya Firestore se control karein.
  Future<void> startTrial() async {
    if (!canStartTrial) return;
    final exp = DateTime.now().add(const Duration(days: trialDays));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, 'trial|${exp.toIso8601String()}');
      await prefs.setBool(_trialKey, true);
    } catch (_) {}
    _isPremium = true;
    _isTrial = true;
    _trialUsed = true;
    _plan = PremiumPlan.monthly;
    _expiry = exp;
    notifyListeners();
  }

  Future<void> cancel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
    _isPremium = false;
    _isTrial = false;
    _plan = null;
    _expiry = null;
    notifyListeners();
  }

  // ---- Limit checks (kahin bhi use karo) ----
  bool canDownload(int currentCount) =>
      _isPremium || currentCount < freeDownloadLimit;

  bool canCreatePlaylist(int currentCount) =>
      _isPremium || currentCount < freePlaylistLimit;

  bool canUseQuality(String quality) =>
      _isPremium || !quality.startsWith('High');
}