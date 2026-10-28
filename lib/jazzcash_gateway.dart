import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:soundclock/checkout_page.dart'; // PaymentGateway, PaymentResult, WalletProvider

/// Asli JazzCash payment.
///
/// ZAROORI: JazzCash ka secure hash (Integrity Salt ke saath) app mein kabhi
/// nahi banta, warna koi bhi app khol kar salt nikaal leta hai. Is liye app
/// sirf apne server (Firebase Cloud Function) ko bolti hai, aur server
/// JazzCash se baat karta hai.
class JazzCashGateway implements PaymentGateway {
  final FirebaseFunctions _fn = FirebaseFunctions.instance;

  @override
  Future<PaymentResult> payWithWallet({
    required int amountPkr,
    required String name,
    required String mobile,
    required WalletProvider provider,
  }) async {
    if (provider != WalletProvider.jazzcash) {
      return const PaymentResult(
          false, 'Abhi sirf JazzCash available hai. JazzCash chunein.');
    }

    try {
      final callable = _fn.httpsCallable(
        'jazzcashWalletPay',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 90)),
      );

      final res = await callable.call({
        'amountPkr': amountPkr,
        'mobile': mobile,
        'name': name,
      });

      final data = Map<String, dynamic>.from(res.data as Map);
      return PaymentResult(
        data['ok'] == true,
        (data['message'] as String?) ?? 'Payment nahi ho saki.',
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('JazzCash function error: code=${e.code} message=${e.message}');
      return PaymentResult(
        false,
        e.message ?? 'Server se rabta nahi ho saka. Dobara koshish karein.',
      );
    } catch (e) {
      debugPrint('JazzCash error: $e');
      return const PaymentResult(
          false, 'Payment nahi ho saki. Dobara koshish karein.');
    }
  }

  /// Card ka data JazzCash ke hosted page par jana chahiye, app ke form mein nahi.
  /// Isliye abhi card band hai; sirf mobile wallet chalta hai.
  @override
  Future<PaymentResult> payWithCard({
    required int amountPkr,
    required String name,
    required String number,
    required String expiry,
    required String cvc,
  }) async {
    return const PaymentResult(
        false, 'Card abhi available nahi. Mobile wallet use karein.');
  }
}