import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/sc_theme.dart';

Color get _bg => SC.isDark ? Color(0xFF080D1C) : SC.pageBg;
Color get _surface => SC.isDark ? Color(0xFF0F1A33) : SC.cardBg;
Color get _line => SC.isDark ? Color(0xFF1E3A5F) : SC.line;
Color get _cyan => SC.isDark ? Color(0xFF22C7E8) : SC.accentText;
const Color _orange = Color(0xFFFF9A3D);
const Color _gold = Color(0xFFFFC043);

// -----------------------------------------------------------------------------
// Payment gateway (yahan apna asli gateway lagana hai)
// -----------------------------------------------------------------------------

class PaymentResult {
  final bool ok;
  final String message;
  const PaymentResult(this.ok, this.message);
}

enum WalletProvider { jazzcash, easypaisa }

/// Asli gateway (JazzCash, Easypaisa, Safepay, PayFast, Stripe...) isi ko implement
/// karega. ZAROORI: card ka data seedha gateway ke SDK / hosted fields ko jana
/// chahiye (tokenization). Apne server par raw card number kabhi na bhejein.
abstract class PaymentGateway {
  Future<PaymentResult> payWithCard({
    required int amountPkr,
    required String name,
    required String number,
    required String expiry,
    required String cvc,
  });

  Future<PaymentResult> payWithWallet({
    required int amountPkr,
    required String name,
    required String mobile,
    required WalletProvider provider,
  });
}

/// TEST MODE: koi asli paisa nahi katta.
/// - Card 4242 4242 4242 4242 -> success
/// - Aise card jo 0000 par khatam hon -> decline (failure test karne ke liye)
/// - Wallet: hamesha success
class MockPaymentGateway implements PaymentGateway {
  @override
  Future<PaymentResult> payWithCard({
    required int amountPkr,
    required String name,
    required String number,
    required String expiry,
    required String cvc,
  }) async {
    await Future<void>.delayed(Duration(seconds: 2));
    if (number.endsWith('0000')) {
      return PaymentResult(false, 'Card decline ho gaya (test).');
    }
    return PaymentResult(true, 'Payment successful (test).');
  }

  @override
  Future<PaymentResult> payWithWallet({
    required int amountPkr,
    required String name,
    required String mobile,
    required WalletProvider provider,
  }) async {
    await Future<void>.delayed(Duration(seconds: 2));
    return PaymentResult(true, 'Payment successful (test).');
  }
}

class PaymentConfig {
  PaymentConfig._();

  /// Asli gateway tayyar hone par yahan badal dein:
  ///   PaymentConfig.gateway = MyRealGateway();
  static PaymentGateway gateway = MockPaymentGateway();
}

// -----------------------------------------------------------------------------
// Input formatters / validators
// -----------------------------------------------------------------------------

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 19) digits = digits.substring(0, 19);
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) b.write(' ');
      b.write(digits[i]);
    }
    final s = b.toString();
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 4) digits = digits.substring(0, 4);
    final s = digits.length >= 3
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}

bool _luhn(String number) {
  var sum = 0;
  var alt = false;
  for (var i = number.length - 1; i >= 0; i--) {
    var n = int.parse(number[i]);
    if (alt) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alt = !alt;
  }
  return sum % 10 == 0;
}

// -----------------------------------------------------------------------------
// Checkout screen
// -----------------------------------------------------------------------------

enum _Method { wallet, card }

/// Premium sheet se kholein:
///   Navigator.of(context).push(MaterialPageRoute(
///     builder: (_) => CheckoutPage(plan: PremiumPlan.yearly)));
/// Kamyab payment par true return hota hai.
class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key, required this.plan});

  final PremiumPlan plan;

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _card = TextEditingController();
  final _expiry = TextEditingController();
  final _cvc = TextEditingController();

  _Method _method = _Method.wallet;
  WalletProvider _wallet = WalletProvider.jazzcash;
  bool _busy = false;

  int get _amount => widget.plan == PremiumPlan.yearly
      ? PremiumService.yearlyAmount
      : PremiumService.monthlyAmount;

  String get _planName =>
      widget.plan == PremiumPlan.yearly ? 'Yearly' : 'Monthly';

  @override
  void dispose() {
    // Card ka data memory se saaf.
    _card.clear();
    _cvc.clear();
    _expiry.clear();
    _name.dispose();
    _mobile.dispose();
    _card.dispose();
    _expiry.dispose();
    _cvc.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _busy = true);

    PaymentResult res;
    try {
      if (_method == _Method.card) {
        res = await PaymentConfig.gateway.payWithCard(
          amountPkr: _amount,
          name: _name.text.trim(),
          number: _card.text.replaceAll(' ', ''),
          expiry: _expiry.text,
          cvc: _cvc.text,
        );
      } else {
        res = await PaymentConfig.gateway.payWithWallet(
          amountPkr: _amount,
          name: _name.text.trim(),
          mobile: _mobile.text.trim(),
          provider: _wallet,
        );
      }
    } catch (_) {
      res = PaymentResult(
          false, 'Payment nahi ho saki. Dobara koshish karein.');
    }

    // Card data foran saaf.
    _card.clear();
    _cvc.clear();
    _expiry.clear();

    if (!mounted) return;

    if (res.ok) {
      // NOTE: Asli app mein premium server se verify hone ke baad hi activate karein.
      await PremiumService.instance.activate(widget.plan);
      navigator.pop(true);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Premium activate ho gaya! Enjoy.')),
        );
    } else {
      setState(() => _busy = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(res.message)));
    }
  }

  InputDecoration _dec(String hint, IconData icon) {
    OutlineInputBorder b(Color c, [double w = 1.2]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: SC.textHint),
      prefixIcon: Icon(icon, color: SC.textSoft, size: 20),
      filled: true,
      fillColor: _surface,
      contentPadding: EdgeInsets.symmetric(vertical: 15),
      enabledBorder: b(_line),
      border: b(_line),
      focusedBorder: b(_gold, 1.6),
      errorBorder: b(Colors.redAccent),
      focusedErrorBorder: b(Colors.redAccent, 1.6),
    );
  }

  Widget _methodTab(_Method m, IconData icon, String label) {
    final on = _method == m;
    return Expanded(
      child: GestureDetector(
        onTap: _busy ? null : () => setState(() => _method = m),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            color: on ? _gold.withValues(alpha: 0.12) : _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? _gold : _line, width: on ? 1.6 : 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: on ? _gold : SC.textFaint, size: 20),
              SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: on ? SC.text : SC.textMid,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _providerChip(WalletProvider p, String label) {
    final on = _wallet == p;
    return Padding(
      padding: EdgeInsets.only(right: 10),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        onSelected: _busy ? null : (_) => setState(() => _wallet = p),
        selectedColor: _orange.withValues(alpha: 0.25),
        backgroundColor: _surface,
        labelStyle: TextStyle(
          color: on ? _orange : SC.textSoft,
          fontWeight: FontWeight.w700,
        ),
        side: BorderSide(color: on ? _orange : _line),
      ),
    );
  }

  Widget _summary() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gold.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [_gold, _orange]),
            ),
            child: Icon(Icons.workspace_premium_rounded,
                color: Colors.black87),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MelodyHub Premium · $_planName',
                  style: TextStyle(
                    color: SC.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 2),
                Text('Kabhi bhi cancel karein',
                    style: TextStyle(color: SC.textFaint, fontSize: 12)),
              ],
            ),
          ),
          Text(
            'Rs $_amount',
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTest = PaymentConfig.gateway is MockPaymentGateway;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: SC.text,
        title: Text('Checkout',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isTest)
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: 12),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      'TEST MODE: asli paisa nahi katega. Card 4242 4242 4242 4242 '
                      'chalega; 0000 par khatam hone wala card decline hoga.',
                      style: TextStyle(color: Colors.amber, fontSize: 12),
                    ),
                  ),
                _summary(),
                SizedBox(height: 20),
                Text('Payment method',
                    style: TextStyle(
                        color: SC.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
                SizedBox(height: 10),
                Row(
                  children: [
                    _methodTab(_Method.wallet,
                        Icons.phone_android_rounded, 'Mobile wallet'),
                    // Asli JazzCash mein card band hai (sirf test mode mein dikhta hai).
                    if (isTest) ...[
                      SizedBox(width: 10),
                      _methodTab(
                          _Method.card, Icons.credit_card_rounded, 'Card'),
                    ],
                  ],
                ),
                SizedBox(height: 16),

                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  style: TextStyle(color: SC.text),
                  cursorColor: _gold,
                  decoration: _dec('Naam', Icons.person_outline_rounded),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'Poora naam likhein'
                      : null,
                ),
                SizedBox(height: 12),

                if (_method == _Method.wallet) ...[
                  Row(
                    children: [
                      if (isTest)
                        _providerChip(WalletProvider.easypaisa, 'Easypaisa'),
                      _providerChip(WalletProvider.jazzcash, 'JazzCash'),
                    ],
                  ),
                  SizedBox(height: 12),
                  TextFormField(
                    controller: _mobile,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(11),
                    ],
                    style: TextStyle(color: SC.text),
                    cursorColor: _gold,
                    decoration: _dec(
                        'Wallet number (03XXXXXXXXX)', Icons.phone_outlined),
                    validator: (v) =>
                        RegExp(r'^03\d{9}$').hasMatch(v ?? '')
                            ? null
                            : '03 se shuru hone wala 11 digit number likhein',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Aap ke wallet par payment ki manzoori ka message aayega.',
                    style: TextStyle(color: SC.textFaint, fontSize: 12),
                  ),
                ] else ...[
                  TextFormField(
                    controller: _card,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_CardNumberFormatter()],
                    style: TextStyle(color: SC.text),
                    cursorColor: _gold,
                    decoration:
                        _dec('Card number', Icons.credit_card_rounded),
                    validator: (v) {
                      final d = (v ?? '').replaceAll(' ', '');
                      if (d.length < 13 || !_luhn(d)) {
                        return 'Sahi card number likhein';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _expiry,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [_ExpiryFormatter()],
                          style: TextStyle(color: SC.text),
                          cursorColor: _gold,
                          decoration:
                              _dec('MM/YY', Icons.calendar_today_rounded),
                          validator: (v) {
                            final m =
                                RegExp(r'^(\d{2})/(\d{2})$').firstMatch(v ?? '');
                            if (m == null) return 'MM/YY';
                            final month = int.parse(m.group(1)!);
                            final year = 2000 + int.parse(m.group(2)!);
                            if (month < 1 || month > 12) return 'Ghalat mahina';
                            final now = DateTime.now();
                            final end = DateTime(year, month + 1);
                            if (!end.isAfter(now)) return 'Card expire hai';
                            return null;
                          },
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _cvc,
                          enabled: !_busy,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          style: TextStyle(color: SC.text),
                          cursorColor: _gold,
                          decoration: _dec('CVC', Icons.lock_outline_rounded),
                          validator: (v) => RegExp(r'^\d{3,4}$')
                                  .hasMatch(v ?? '')
                              ? null
                              : '3 ya 4 digit',
                        ),
                      ),
                    ],
                  ),
                ],

                SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _pay,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: _gold.withValues(alpha: 0.5),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _busy
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.black),
                          )
                        : Text(
                            'Pay Rs $_amount',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_rounded, size: 14, color: SC.textHint),
                    SizedBox(width: 6),
                    Text(
                      'Aap ki details hamare paas save nahi hotin.',
                      style: TextStyle(color: SC.textHint, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}