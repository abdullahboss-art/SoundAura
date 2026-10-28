import 'package:flutter/material.dart';
import 'package:soundclock/checkout_page.dart'; // use the correct name of your checkout file
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/sc_theme.dart';

Color get _bg => SC.isDark ? Color(0xFF080D1C) : SC.pageBg;
Color get _surface => SC.isDark ? Color(0xFF0F1A33) : SC.cardBg;
Color get _line => SC.isDark ? Color(0xFF1E3A5F) : SC.line;
Color get _cyan => SC.isDark ? Color(0xFF22C7E8) : SC.accentText;
const Color _orange = Color(0xFFFF9A3D);
const Color _gold = Color(0xFFFFC043);

/// Why the sheet was opened: it changes the headline and highlights the
/// matching row in the table. Opening it in context converts more users.
enum PremiumReason { general, downloads, playlists, quality }

/// (icon, feature, free value, premium value, reason that highlights the row)
/// A value can be a String or a bool.
List<(IconData, String, Object, Object, PremiumReason?)> get _rows => [
      (
        Icons.download_done_rounded,
        'Downloads',
        '${PremiumService.freeDownloadLimit} songs',
        'Unlimited',
        PremiumReason.downloads
      ),
      (
        Icons.queue_music_rounded,
        'Playlists',
        '${PremiumService.freePlaylistLimit}',
        'Unlimited',
        PremiumReason.playlists
      ),
      (
        Icons.high_quality_rounded,
        'Offline quality',
        '160 kbps',
        '320 kbps',
        PremiumReason.quality
      ),
      (Icons.block_rounded, 'Ads', 'Yes', 'No', null),
      (Icons.skip_next_rounded, 'Skips', 'Limited', 'Unlimited', null),
      (Icons.bedtime_rounded, 'Sleep timer & equalizer', false, true, null),
      (Icons.workspace_premium_rounded, 'Gold PRO badge', false, true, null),
    ];

/// Open the plans sheet: showPremiumSheet(context);
/// When a limit is hit: showPremiumSheet(context, reason: PremiumReason.downloads);
Future<void> showPremiumSheet(
  BuildContext context, {
  PremiumReason reason = PremiumReason.general,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PremiumSheet(reason: reason),
  );
}

class _PremiumSheet extends StatefulWidget {
  const _PremiumSheet({required this.reason});

  final PremiumReason reason;

  @override
  State<_PremiumSheet> createState() => _PremiumSheetState();
}

class _PremiumSheetState extends State<_PremiumSheet> {
  PremiumPlan _selected = PremiumPlan.yearly;
  bool _busy = false;

  // Trial is off: every button now opens CheckoutPage directly.
  // To bring the trial back, set this to `PremiumService.instance.canStartTrial`.
  bool get _trial => false;

  (String, String) get _headline {
    switch (widget.reason) {
      case PremiumReason.downloads:
        return (
          'You\u2019ve hit your download limit',
          'Free accounts can download up to ${PremiumService.freeDownloadLimit} '
              'songs. Upgrade to Premium for unlimited downloads.'
        );
      case PremiumReason.playlists:
        return (
          'Playlist limit reached',
          'Free accounts can create up to ${PremiumService.freePlaylistLimit} '
              'playlists. Upgrade to Premium to create as many as you like.'
        );
      case PremiumReason.quality:
        return (
          'Unlock high-quality audio',
          'Listen to your offline songs in crisp 320 kbps sound.'
        );
      case PremiumReason.general:
        return ('SoundClock Premium', 'Your music. Anytime. Anywhere.');
    }
  }

  /// Floating, rounded alert with a title and a subtitle.
  /// Sits above the mini player.
  void _showWelcomeAlert(
    ScaffoldMessengerState messenger, {
    required String title,
    required String message,
  }) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(16, 0, 16, 90),
          backgroundColor: SC.primary,
          elevation: 6,
          duration: Duration(seconds: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [_gold, _orange]),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.black87,
                  size: 22,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      message,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _start({required bool useTrial}) async {
    // The free trial needs no payment, so checkout is skipped.
    if (useTrial) {
      // Grab these before the sheet closes (its context gets disposed).
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);

      setState(() => _busy = true);
      await PremiumService.instance.startTrial();
      if (!mounted) return;
      nav.pop();
      _showWelcomeAlert(
        messenger,
        title: 'Welcome to Premium 🎉',
        message:
            'Your ${PremiumService.trialDays}-day free trial has started. Enjoy!',
      );
      return;
    }

    // Paid plan: close the sheet and open CheckoutPage.
    // The sheet's context is disposed after pop(), so save these first.
    final nav = Navigator.of(context);
    final plan = _selected;

    nav.pop();

    await nav.push<bool>(
      MaterialPageRoute(builder: (_) => CheckoutPage(plan: plan)),
    );
    // CheckoutPage handles activate() and the success message itself.
  }

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------

  Widget _planCard({
    required PremiumPlan plan,
    required String title,
    required String price,
    String? sub,
    String? badge,
  }) {
    final on = _selected == plan;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selected = plan),
        child: Container(
          padding: EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: on ? _gold.withValues(alpha: 0.10) : _bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: on ? _gold : _line,
              width: on ? 1.6 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: SC.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(
                    on
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: on ? _gold : SC.textHint,
                    size: 20,
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(price, style: TextStyle(color: _cyan, fontSize: 13)),
              if (sub != null) ...[
                SizedBox(height: 2),
                Text(sub,
                    style:
                        TextStyle(color: SC.textFaint, fontSize: 11)),
              ],
              if (badge != null) ...[
                SizedBox(height: 8),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: _orange,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _valueCell(Object v, {required bool premium}) {
    if (v is bool) {
      return Icon(
        v ? Icons.check_circle_rounded : Icons.cancel_rounded,
        size: 18,
        color: v ? Colors.greenAccent : SC.stroke,
      );
    }
    return Text(
      v.toString(),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: premium ? _gold : SC.textFaint,
        fontSize: 12,
        fontWeight: premium ? FontWeight.w800 : FontWeight.w500,
      ),
    );
  }

  Widget _table() {
    final rows = _rows;
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                Expanded(flex: 6, child: SizedBox()),
                Expanded(
                  flex: 3,
                  child: Center(
                    child: Text('Free',
                        style: TextStyle(
                            color: SC.textFaint,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Center(
                    child: Text('Premium',
                        style: TextStyle(
                            color: _gold,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          for (final r in rows) ...[
            Divider(height: 1, thickness: 1, color: _line),
            Container(
              color: r.$5 != null && r.$5 == widget.reason
                  ? _gold.withValues(alpha: 0.12)
                  : Colors.transparent,
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Expanded(
                    flex: 6,
                    child: Row(
                      children: [
                        Icon(r.$1, color: _cyan, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            r.$2,
                            style: TextStyle(
                                color: SC.text, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                      flex: 3,
                      child: Center(child: _valueCell(r.$3, premium: false))),
                  Expanded(
                      flex: 3,
                      child: Center(child: _valueCell(r.$4, premium: true))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final head = _headline;
    final yearly = _selected == PremiumPlan.yearly;
    final planPrice =
        yearly ? PremiumService.yearlyPrice : PremiumService.monthlyPrice;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: SC.stroke,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            SizedBox(height: 18),

            // Header
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [_gold, _orange]),
                    boxShadow: [
                      BoxShadow(
                        color: _gold.withValues(alpha: 0.45),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Icon(Icons.workspace_premium_rounded,
                      color: Colors.black87, size: 28),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        head.$1,
                        style: TextStyle(
                          color: SC.text,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        head.$2,
                        style: TextStyle(
                            color: SC.textMid, fontSize: 12.5, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),

            _table(),
            SizedBox(height: 18),

            // Plans
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _planCard(
                  plan: PremiumPlan.monthly,
                  title: 'Monthly',
                  price: PremiumService.monthlyPrice,
                ),
                SizedBox(width: 12),
                _planCard(
                  plan: PremiumPlan.yearly,
                  title: 'Yearly',
                  price: PremiumService.yearlyPrice,
                  sub: 'Only Rs ${PremiumService.yearlyPerMonth} / month',
                  badge: 'SAVE ${PremiumService.yearlySavingsPercent}%',
                ),
              ],
            ),
            SizedBox(height: 18),

            // Main button
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _busy ? null : () => _start(useTrial: _trial),
                child: _busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(
                        _trial
                            ? 'Start ${PremiumService.trialDays}-day free trial'
                            : 'Go Premium',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16),
                      ),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                _trial
                    ? '$planPrice after the trial. Cancel anytime.'
                    : 'Cancel anytime.',
                textAlign: TextAlign.center,
                style: TextStyle(color: SC.textHint, fontSize: 12),
              ),
            ),
            if (_trial)
              Center(
                child: TextButton(
                  onPressed: _busy ? null : () => _start(useTrial: false),
                  child: Text(
                    'Subscribe now without a trial',
                    style: TextStyle(color: SC.textFaint, fontSize: 12.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}