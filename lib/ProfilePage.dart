import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundclock/Authservice.dart';
import 'package:soundclock/DownloadsPage.dart';
import 'package:soundclock/Library%20service%20.dart';
import 'package:soundclock/LibraryPage.dart';
import 'package:soundclock/Login.dart';
import 'package:soundclock/Player%20service%20.dart';
import 'package:soundclock/download_service.dart';
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/premium_sheet.dart';
import 'package:soundclock/user_avatar.dart';
import 'package:soundclock/sc_theme.dart';
import 'package:soundclock/theme_controller.dart';

// -----------------------------------------------------------------------------
// SIRF DO COLOR: Purple (SC.primary) aur White (theme ka text color).
// Getter hain, taake dark/light theme badalne par ye bhi badlein.
// -----------------------------------------------------------------------------
Color get _purple => SC.primary;
Color get _text => SC.text;
Color get _bg => SC.pageBg;
Color get _surface => SC.cardBg;
Color get _line => SC.primary.withAlpha(90);
const Color _onPurple = Colors.white; // purple ke upar hamesha white
// Safed text (dark theme me safed, light theme me gehra dark taake ghaib na ho).
Color get _white => SC.isDark ? Colors.white : Color(0xFF1B0F4D);

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const String _kQuality = 'pref_offline_quality';
  static const String _kNotif = 'pref_notifications';

  static const List<String> _qualities = [
    'Low (96 kbps)',
    'Normal (160 kbps)',
    'High (320 kbps)',
  ];

  String _quality = 'Normal (160 kbps)';
  bool _notifications = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await PremiumService.instance.load();
    await _loadPrefs();
  }

  // ---------------------------------------------------------------------------
  // Saved settings
  // ---------------------------------------------------------------------------

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final q = prefs.getString(_kQuality);
      final n = prefs.getBool(_kNotif);

      if (!mounted) return;
      setState(() {
        if (q != null && _qualities.contains(q)) _quality = q;
        if (n != null) _notifications = n;
      });
    } catch (_) {}
    _enforceQuality();
  }

  /// Free user ki quality agar High hai to Normal par le aao.
  void _enforceQuality() {
    if (!mounted) return;
    if (!PremiumService.instance.canUseQuality(_quality)) {
      final fallback = 'Normal (160 kbps)';
      setState(() => _quality = fallback);
      _saveString(_kQuality, fallback);
    }
  }

  Future<void> _saveString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }

  Future<void> _saveBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // User info
  // ---------------------------------------------------------------------------

  bool _isGoogle(User? user) =>
      user?.providerData.any((p) => p.providerId == 'google.com') ?? false;

  String _displayName(User? user) {
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return 'Unknown User';
  }

  String _providerLabel(User? user) {
    if (user == null || user.isAnonymous) return 'Guest';
    if (_isGoogle(user)) return 'Google Account';
    return 'Email Account';
  }

  String _date(DateTime? d) {
    if (d == null) return '';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final local = d.toLocal();
    return '${months[local.month - 1]} ${local.year}';
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _pickQuality() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'Offline Quality',
                style: TextStyle(
                  color: _purple,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            for (final q in _qualities)
              ListTile(
                title: Text(q, style: TextStyle(color: _text)),
                trailing: q == _quality
                    ? Icon(Icons.check_rounded, color: _white)
                    : (!PremiumService.instance.canUseQuality(q)
                        ? Icon(Icons.lock_rounded, color: _white, size: 20)
                        : null),
                onTap: () {
                  if (!PremiumService.instance.canUseQuality(q)) {
                    Navigator.of(ctx).pop();
                    showPremiumSheet(context);
                    return;
                  }
                  setState(() => _quality = q);
                  _saveString(_kQuality, q);
                  Navigator.of(ctx).pop();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: Text(title,
            style: TextStyle(color: _purple, fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Text(
            message,
            style: TextStyle(color: _text, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: TextStyle(color: _purple)),
          ),
        ],
      ),
    );
  }

  void _confirmCancel() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: Text('Premium cancel karein?',
            style: TextStyle(color: _purple, fontWeight: FontWeight.w800)),
        content: Text(
          'Aap Free plan par wapas chale jayenge.',
          style: TextStyle(color: _text, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Rehne do', style: TextStyle(color: _text)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await PremiumService.instance.cancel();
              _enforceQuality();
              _toast('Premium cancel ho gaya.');
            },
            child: Text('Cancel Plan', style: TextStyle(color: _purple)),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);

    await PlayerService.instance.stop();
    await AuthService.instance.signOut();

    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => LoginPage()),
      (route) => false,
    );
  }

  // ---------------------------------------------------------------------------
  // Widgets
  // ---------------------------------------------------------------------------

  /// Gol avatar: save ki hui photo ya harf. Purple ring.
  Widget _avatar(User? user, String name) {
    double size = 96;

    return Container(
      padding: EdgeInsets.all(3.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [_purple, _purple.withAlpha(110)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Container(
        padding: EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _bg,
        ),
        child: UserAvatar(
          photoUrl: userPhotoUrl(user),
          name: name,
          size: size,
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _purple.withAlpha(160)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _purple),
          SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: _purple,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(User? user) {
    final name = _displayName(user);
    final email = (user?.email ?? '').isNotEmpty
        ? user!.email!
        : (user == null || user.isAnonymous ? 'Guest account' : 'No email');
    final joined = _date(user?.metadata.creationTime);
    final pro = PremiumService.instance.isPremium;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 24, 16, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _purple.withAlpha(pro ? 200 : 110)),
        boxShadow: [
          BoxShadow(color: _purple.withAlpha(40), blurRadius: 20),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _purple.withAlpha(46),
            _surface,
          ],
        ),
      ),
      child: Column(
        children: [
          _avatar(user, name),
          SizedBox(height: 14),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4),
          Text(
            email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: _white, fontSize: 14),
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (pro) _chip(Icons.workspace_premium_rounded, 'PRO'),
              _chip(
                _isGoogle(user)
                    ? Icons.verified_rounded
                    : Icons.mail_outline_rounded,
                _providerLabel(user),
              ),
              if (joined.isNotEmpty)
                _chip(Icons.calendar_today_rounded, 'Joined $joined'),
            ],
          ),
        ],
      ),
    );
  }

 Widget _stat(IconData icon, int value, String label, VoidCallback onTap) {
  return Expanded(
    child: Material(
      color: _surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Icon(icon, color: _white, size: 22),
              SizedBox(height: 6),
              Text(
                '$value',
                style: TextStyle(
                  color: _text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(color: _purple, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void _open(Widget page) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

Widget _stats() {
  return ListenableBuilder(
    listenable: Listenable.merge([
      DownloadService.instance,
      LibraryService.instance,
    ]),
    builder: (context, _) {
      return Row(
        children: [
          _stat(
            Icons.download_done_rounded,
            DownloadService.instance.items.length,
            'Downloads',
            () => _open(const DownloadsPage()),
          ),
          SizedBox(width: 10),
          _stat(
            Icons.favorite_rounded,
            LibraryService.instance.liked.length,
            'Liked',
            () => _open(const LibraryPage()),
          ),
          SizedBox(width: 10),
          _stat(
            Icons.queue_music_rounded,
            LibraryService.instance.playlists.length,
            'Playlists',
            () => _open(const LibraryPage()),
          ),
        ],
      );
    },
  );
}

  Widget _sectionTitle(String text) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: _purple,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(height: 1, thickness: 1, color: _line);

  Widget _premiumRow() {
    final ps = PremiumService.instance;
    final sub = ps.isPremium
        ? '${ps.plan == PremiumPlan.yearly ? 'Yearly' : 'Monthly'} · Renews ${_date(ps.expiry)}'
        : 'Free plan';

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _purple.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.workspace_premium_rounded, color: _white),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ps.isPremium ? 'Premium Active' : 'Premium',
                  style: TextStyle(
                    color: _text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(color: _purple, fontSize: 12),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () {
              if (ps.isPremium) {
                _confirmCancel();
              } else {
                showPremiumSheet(context);
              }
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: _purple,
              side: BorderSide(color: _purple),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              ps.isPremium ? 'Manage' : 'Upgrade',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    String? value,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _purple.withAlpha(36),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: _white, size: 21),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: _text, fontSize: 15),
              ),
            ),
            if (value != null)
              Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text(
                  value,
                  style: TextStyle(color: _white, fontSize: 13),
                ),
              ),
            trailing ?? Icon(Icons.chevron_right_rounded, color: _white),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PremiumService.instance,
      builder: (context, _) {
        final user = FirebaseAuth.instance.currentUser;

        return Scaffold(
          backgroundColor: _bg,
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _header(user),
                SizedBox(height: 14),
                _stats(),
                _sectionTitle('Account'),
                _card([_premiumRow()]),
                _sectionTitle('Preferences'),
                _card([
                  _row(
                    icon: Icons.speed_rounded,
                    title: 'Offline Quality',
                    value: _quality,
                    onTap: _pickQuality,
                  ),
                  _divider(),
                  _row(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    trailing: Switch(
                      value: _notifications,
                      activeThumbColor: _onPurple,
                      activeTrackColor: _purple,
                      onChanged: (v) {
                        setState(() => _notifications = v);
                        _saveBool(_kNotif, v);
                      },
                    ),
                    onTap: () {
                      setState(() => _notifications = !_notifications);
                      _saveBool(_kNotif, _notifications);
                    },
                  ),
                  _divider(),
                  _row(
                    icon: SC.isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    title: 'Dark Theme',
                    trailing: Switch(
                      value: SC.isDark,
                      activeThumbColor: _onPurple,
                      activeTrackColor: _purple,
                      onChanged: (v) => v
                          ? AppThemeController.setDark()
                          : AppThemeController.setLight(),
                    ),
                    onTap: AppThemeController.toggle,
                  ),
                ]),
                _sectionTitle('Support'),
                _card([
                  _row(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    onTap: () => _showInfo(
                      'Help & Support',
                      'Koi masla ho to apna sawal humein bhejein, hum jald jawab denge.',
                    ),
                  ),
                  _divider(),
                  _row(
                    icon: Icons.info_outline_rounded,
                    title: 'About MelodyHub',
                    onTap: () => showAboutDialog(
                      context: context,
                      applicationName: 'MelodyHub',
                      applicationVersion: '1.0.0',
                      children: [
                        Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('Your Music. Anytime. Anywhere.'),
                        ),
                      ],
                    ),
                  ),
                  _divider(),
                  _row(
                    icon: Icons.shield_outlined,
                    title: 'Privacy Policy',
                    onTap: () => _showInfo(
                      'Privacy Policy',
                      'MelodyHub aapki email aur profile sirf login ke liye istemal karta hai. '
                          'Aapka data kisi aur ko nahi becha jata.',
                    ),
                  ),
                  _divider(),
                  _row(
                    icon: Icons.cancel_outlined,
                    title: 'Terms & Conditions',
                    onTap: () => _showInfo(
                      'Terms & Conditions',
                      'MelodyHub istemal karke aap in shartein se ittefaq karte hain: '
                          'music sirf zaati istemal ke liye hai aur dobara taqseem nahi kiya ja sakta.',
                    ),
                  ),
                ]),
                SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: _onPurple,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _logout,
                    icon: Icon(Icons.logout_rounded),
                    label: Text(
                      'Log Out',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}