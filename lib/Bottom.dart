import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:soundclock/DownloadsPage.dart';
import 'package:soundclock/Home.dart';
import 'package:soundclock/LibraryPage.dart';
import 'package:soundclock/ProfilePage.dart';
import 'package:soundclock/player_ui.dart';
import 'package:soundclock/sc_theme.dart';
import 'package:soundclock/user_avatar.dart';
import 'package:flutter/services.dart';

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _NavItem(this.icon, this.activeIcon, this.label);
}

const List<_NavItem> _items = [
  _NavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
  _NavItem(
    Icons.library_music_outlined,
    Icons.library_music_rounded,
    'Library',
  ),
  _NavItem(
    Icons.file_download_outlined,
    Icons.file_download_rounded,
    'Downloads',
  ),
  _NavItem(Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
];

/// Aakhri tab (Profile) ka icon.
/// Login ho to user ki photo (ya naam ka pehla harf), warna purana person icon.
class _ProfileNavIcon extends StatelessWidget {
  final _NavItem item;
  final bool selected;
  final Color color;

  const _ProfileNavIcon({
    required this.item,
    required this.selected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final plainIcon = Icon(
      selected ? item.activeIcon : item.icon,
      size: 24,
      color: color,
    );

    // userChanges: login / logout / profile update par khud badal jata hai.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) return plainIcon;

        double size = 26;

        final name = (user.displayName?.trim().isNotEmpty ?? false)
            ? user.displayName!.trim()
            : (user.email ?? '');

        return AnimatedContainer(
          duration: Duration(milliseconds: 220),
          padding: EdgeInsets.all(1.6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? SC.violet : SC.stroke,
              width: 1.6,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: SC.primary.withAlpha(110),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          // Profile page ke saath same size (300) taake ek hi save ki hui photo dono jagah chale.
          child: UserAvatar(
            photoUrl: userPhotoUrl(user),
            name: name,
            size: size,
          ),
        );
      },
    );
  }
}

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: SC.pageBgAlt,
        border: Border(top: BorderSide(color: SC.line)),
        boxShadow: [
          BoxShadow(
            color: SC.primary.withAlpha(40),
            blurRadius: 18,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final selected = i == currentIndex;
              final color = selected ? SC.violet : SC.textFaint;
              final isProfile = i == _items.length - 1;

              return Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: Duration(milliseconds: 220),
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: selected
                              ? SC.primary.withAlpha(46)
                              : Colors.transparent,
                        ),
                        child: isProfile
                            ? _ProfileNavIcon(
                                item: item,
                                selected: selected,
                                color: color,
                              )
                            : Icon(
                                selected ? item.activeIcon : item.icon,
                                size: 24,
                                color: color,
                              ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  late final List<Widget> _pages = [
    HomeScreen(),
    LibraryPage(),
    DownloadsPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SC.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: SC.pageBg,
        body: IndexedStack(
          index: _index,
          children: _pages,
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MiniPlayer(),
            AppBottomNav(
              currentIndex: _index,
              onTap: (i) => setState(() => _index = i),
            ),
          ],
        ),
      ),
    );
  }
}