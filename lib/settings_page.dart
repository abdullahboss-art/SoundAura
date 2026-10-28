import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:soundclock/Authservice.dart';
import 'package:soundclock/Library%20service%20.dart';
import 'package:soundclock/Login.dart';
import 'package:soundclock/Player%20service%20.dart';
import 'package:soundclock/download_service.dart';
import 'package:soundclock/player_ui.dart';
import 'package:soundclock/song_actions.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  String _name(User? user) {
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;

    final email = user?.email;
    if (email != null && email.contains('@')) return email.split('@').first;

    return 'Music Lover';
  }

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String message,
    String action,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MelodyColors.surface,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content:
            Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action,
                style: const TextStyle(color: MelodyColors.orange)),
          ),
        ],
      ),
    );
    return yes == true;
  }

  Future<void> _logout(BuildContext context) async {
    final navigator = Navigator.of(context);

    await PlayerService.instance.stop();
    await AuthService.instance.signOut();

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Widget _item({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    Color iconColor = Colors.white70,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(color: Colors.white54)),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = _name(user);

    return Container(
      color: MelodyColors.background,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 16),
              child: Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: MelodyColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MelodyColors.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: MelodyColors.orange,
                    backgroundImage: (user?.photoURL ?? '').isNotEmpty
                        ? NetworkImage(user!.photoURL!)
                        : null,
                    child: (user?.photoURL ?? '').isNotEmpty
                        ? null
                        : Text(
                            name[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? 'Guest',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ListenableBuilder(
              listenable: DownloadService.instance,
              builder: (context, _) {
                final ds = DownloadService.instance;
                return _item(
                  icon: Icons.download_for_offline_rounded,
                  title: 'Clear downloads',
                  subtitle:
                      '${ds.items.length} songs • ${formatBytes(ds.totalBytes)}',
                  onTap: () async {
                    if (ds.items.isEmpty) {
                      _toast(context, 'Koi download nahi hai.');
                      return;
                    }
                    final ok = await _confirm(
                      context,
                      'Saare downloads hatayein?',
                      'Device se sab downloaded gaane delete ho jayenge.',
                      'Delete',
                    );
                    if (!ok) return;
                    await ds.clearAll();
                    if (context.mounted) _toast(context, 'Downloads saaf ho gaye.');
                  },
                );
              },
            ),
            _item(
              icon: Icons.history_rounded,
              title: 'Clear search history',
              onTap: () {
                LibraryService.instance.clearRecentSearches();
                _toast(context, 'Search history saaf ho gayi.');
              },
            ),
            _item(
              icon: Icons.restore_rounded,
              title: 'Clear recently played',
              onTap: () {
                PlayerService.instance.recent.value = [];
                _toast(context, 'Recently played saaf ho gaya.');
              },
            ),
            _item(
              icon: Icons.info_outline_rounded,
              title: 'About MelodyHub',
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'MelodyHub',
                applicationVersion: '1.0.0',
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Your Music. Anytime. Anywhere.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _item(
              icon: Icons.logout_rounded,
              iconColor: MelodyColors.orange,
              title: 'Logout',
              onTap: () => _logout(context),
            ),
          ],
        ),
      ),
    );
  }
}
