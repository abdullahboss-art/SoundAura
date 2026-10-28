import 'package:flutter/material.dart';
import 'package:soundclock/Home.dart' show PlaylistPage;
import 'package:soundclock/Library%20service%20.dart';
import 'package:soundclock/player_ui.dart';
import 'package:soundclock/sc_theme.dart';
import 'package:soundclock/song.dart';
import 'package:soundclock/song_actions.dart';

// -----------------------------------------------------------------------------
// Sirf purple + white. Sab colors GETTER hain (const nahi), taake theme
// badalte hi Library bhi badal jaye.
// -----------------------------------------------------------------------------
Color get _purple => SC.primary;
Color get _text => SC.text; // dark theme me white, light theme me dark
Color get _bg => SC.pageBg;
Color get _surface => SC.cardBg;
Color get _line => SC.line;
const Color _onPurple = Colors.white; // purple ke upar hamesha white

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  int _tab = 0; // 0 = Playlists, 1 = Artists

  void _open(String title, List<Song> songs) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistPage(title: title, songs: songs),
      ),
    );
  }

  Future<void> _create() async {
    final name = await askPlaylistName(context);
    if (name == null || !mounted) return;

    final ok = LibraryService.instance.createPlaylist(name);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Playlist "$name" ban gayi' : 'Ye naam pehle se maujood hai.',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String name) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _line),
        ),
        title: Text('Delete playlist?',
            style: TextStyle(color: _purple, fontWeight: FontWeight.w800)),
        content: Text('"$name" hamesha ke liye hat jayegi.',
            style: TextStyle(color: _text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: _text)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete', style: TextStyle(color: _purple)),
          ),
        ],
      ),
    );

    if (yes == true) LibraryService.instance.deletePlaylist(name);
  }

  Widget _chip(String label, int value) {
    final selected = _tab == value;
    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _tab = value),
        selectedColor: _purple,
        backgroundColor: _surface,
        side: BorderSide(color: _purple),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(
          color: selected ? _onPurple : _text,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _iconBox(IconData icon) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [_purple, _purple.withAlpha(150)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(icon, color: _onPurple, size: 26),
    );
  }

  Widget _tile({
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.symmetric(vertical: 2),
      onTap: onTap,
      leading: leading,
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _text,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(subtitle, style: TextStyle(color: _purple)),
      trailing: trailing,
    );
  }

  Widget _playlistsTab(LibraryService lib) {
    final liked = lib.liked;
    final names = lib.playlists.keys.toList();

    return Column(
      children: [
        InkWell(
          onTap: _create,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 50,
            margin: EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: _purple.withAlpha(24),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _purple.withAlpha(140)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_rounded, color: _purple),
                SizedBox(width: 8),
                Text(
                  'Create Playlist',
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        _tile(
          leading: _iconBox(Icons.favorite_rounded),
          title: 'Liked Songs',
          subtitle: '${liked.length} songs',
          onTap: () => _open('Liked Songs', liked),
        ),
        for (final name in names)
          _tile(
            leading: () {
              final songs = lib.playlists[name] ?? <Song>[];
              if (songs.isNotEmpty && songs.first.imageUrl.isNotEmpty) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SongCover(url: songs.first.imageUrl, size: 52),
                );
              }
              return _iconBox(Icons.queue_music_rounded);
            }(),
            title: name,
            subtitle: '${lib.playlists[name]?.length ?? 0} songs',
            onTap: () => _open(name, lib.playlists[name] ?? <Song>[]),
            trailing: PopupMenuButton<String>(
              color: _surface,
              icon: Icon(Icons.more_vert_rounded, color: _purple),
              onSelected: (v) {
                if (v == 'delete') _confirmDelete(name);
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete playlist',
                      style: TextStyle(color: _text)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _artistsTab(LibraryService lib) {
    // Liked songs + playlists ke gaane artist ke hisaab se.
    final byArtist = <String, Map<String, Song>>{};

    void add(Song s) {
      final artist = s.artist.split(' • ').first.trim();
      if (artist.isEmpty) return;
      byArtist.putIfAbsent(artist, () => <String, Song>{})[s.id] = s;
    }

    lib.liked.forEach(add);
    for (final list in lib.playlists.values) {
      list.forEach(add);
    }

    if (byArtist.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: 40),
        child: Center(
          child: Text(
            'Gaane like karein ya playlist mein add karein,\nartists yahan nazar aayenge.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _text, height: 1.4),
          ),
        ),
      );
    }

    final names = byArtist.keys.toList()..sort();

    return Column(
      children: [
        for (final name in names)
          _tile(
            leading: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _purple,
              ),
              child: Text(
                name[0].toUpperCase(),
                style: TextStyle(
                  color: _onPurple,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ),
            title: name,
            subtitle: '${byArtist[name]!.length} songs',
            onTap: () => _open(name, byArtist[name]!.values.toList()),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: LibraryService.instance,
          builder: (context, _) {
            final lib = LibraryService.instance;

            return ListView(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: 2),
                        child: Text(
                          'My Library',
                          style: TextStyle(
                            color: _purple,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _purple.withAlpha(40),
                        border: Border.all(color: _purple.withAlpha(120)),
                      ),
                      child: IconButton(
                        tooltip: 'New playlist',
                        onPressed: _create,
                        icon: Icon(Icons.add_rounded,
                            color: _purple, size: 26),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14),
                Row(
                  children: [
                    _chip('Playlists', 0),
                    _chip('Artists', 1),
                  ],
                ),
                SizedBox(height: 14),
                if (_tab == 0) _playlistsTab(lib) else _artistsTab(lib),
              ],
            );
          },
        ),
      ),
    );
  }
}