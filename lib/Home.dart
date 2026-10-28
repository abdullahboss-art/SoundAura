import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:soundclock/Library%20service%20.dart';
import 'package:soundclock/latest_audio.dart';
import 'package:soundclock/song_actions.dart';
import 'package:soundclock/youtube_music_service.dart';

import 'package:soundclock/Authservice.dart';
import 'package:soundclock/catalog_service.dart';
import 'package:soundclock/download_service.dart';

import 'package:soundclock/Login.dart';
import 'package:soundclock/Player%20service%20.dart';
import 'package:soundclock/audius_service.dart';
import 'package:soundclock/youtube_player_page.dart';
import 'package:soundclock/player_ui.dart';
import 'package:soundclock/sc_theme.dart';
import 'package:soundclock/song.dart';
import 'package:soundclock/user_avatar.dart';

// -----------------------------------------------------------------------------
// SIRF DO COLOR: Purple (SC.primary) aur White.
// -----------------------------------------------------------------------------
// _white = theme ka text color (dark me safed, light me dark).
// _onPurple = purple/dark image ke upar hamesha safed.
Color get _white => SC.isDark ? Colors.white : Color(0xFF1B0F4D);
const Color _onPurple = Colors.white;
Color get _purple => SC.primary;

class _PlaylistDef {
  final String title;
  final String subtitle;
  final String? tags;
  final String order;
  final int limit;

  const _PlaylistDef({
    required this.title,
    required this.subtitle,
    required this.order,
    required this.limit,
    this.tags,
  });
}

// NOTE: Index 0 (Top 50) = Bollywood + Pakistani artists (Deezer/iTunes), Audius se nahi.
const List<_PlaylistDef> _playlists = [
  _PlaylistDef(
    title: 'Top 50',
    subtitle: 'Bollywood • Pakistani',
    order: 'month',
    limit: 50,
  ),
  _PlaylistDef(
    title: 'Workout',
    subtitle: 'Motivation',
    tags: 'Electronic',
    order: 'week',
    limit: 20,
  ),
  _PlaylistDef(
    title: 'Chill Hits',
    subtitle: 'Relaxing',
    tags: 'Lo-Fi',
    order: 'week',
    limit: 20,
  ),
  _PlaylistDef(
    title: 'World Beats',
    subtitle: 'Global Vibes',
    tags: 'World',
    order: 'week',
    limit: 20,
  ),
];

const int _chillIndex = 2;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> _popular = [];
  List<Song> _indian = [];
  List<List<Song>> _lists = [];

  // Latest audio songs (Bollywood / Pakistani / English tabs)
  LatestAudio? _latestAudio;
  bool _latestAudioLoading = false;
  int _audioTab = 0; // 0 = Bollywood, 1 = Pakistani, 2 = English

  // YouTube search results
  List<YouTubeSong> _youtubeResults = [];
  bool _ytSearching = false;
  String? _ytSearchError;

  bool _loading = true;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  int _reqId = 0;
  String _query = '';
  List<Song> _results = [];
  bool _searching = false;
  String? _searchError;
  int _searchTab = 0; // 0 = Audio, 1 = Video

  @override
  void initState() {
    super.initState();
    PlayerService.instance.error.addListener(_onPlayerError);
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    PlayerService.instance.error.removeListener(_onPlayerError);
    super.dispose();
  }

  void _onPlayerError() {
    final msg = PlayerService.instance.error.value;
    if (msg == null || !mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
    PlayerService.instance.error.value = null;
  }

  // ---------------------------------------------------------------------------
  // DATA LOADING (logic pehle jaisa)
  // ---------------------------------------------------------------------------

  Future<List<Song>> _buildTop50() => CatalogService.instance.buildTop50();

  /// Audius se trending + Workout / Chill / World playlists.
  /// Return: [trending, workout, chill, world]. Fail ho to khali lists.
  Future<List<List<Song>>> _loadAudius() async {
    final emptyResult = List<List<Song>>.generate(
      _playlists.length,
      (_) => <Song>[],
    );

    if (!AudiusService.instance.hasKey) {
      debugPrint('Audius key configure nahi hai.');
      return emptyResult;
    }

    try {
      final results = await Future.wait<List<Song>>([
        AudiusService.instance.fetchTrending(time: 'week', limit: 30),
        // Top 50 (index 0) skip: wo ab iTunes se aata hai.
        ..._playlists.skip(1).map(
              (p) => AudiusService.instance.fetchTrending(
                genre: p.tags,
                time: p.order,
                limit: p.limit,
              ),
            ),
      ]);
      return results;
    } catch (e) {
      debugPrint('Audius load failed: $e');
      return emptyResult;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    _loadLatestAudio();

    try {
      final top50Future = _buildTop50();
      final audiusFuture = _loadAudius();

      final top50 = await top50Future;
      final audius = await audiusFuture; // [trending, workout, chill, world]

      if (top50.isEmpty && audius.every((l) => l.isEmpty)) {
        throw Exception('Koi bhi source se gaane nahi mile.');
      }

      if (!mounted) return;

      setState(() {
        _popular = top50.isNotEmpty ? top50 : audius.first;
        // 0 = Top 50 (iTunes/Deezer), 1..3 = Audius playlists.
        _lists = [top50, ...audius.skip(1)];
        _indian = [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'Music load nahi hua.\n$e';
      });
    }
  }

  Future<void> _loadLatestAudio() async {
    if (mounted) setState(() => _latestAudioLoading = true);

    try {
      final data = await LatestAudioService.instance.fetch(force: true);
      if (!mounted) return;
      setState(() {
        _latestAudio = data;
        _latestAudioLoading = false;
      });
    } catch (e) {
      debugPrint('Latest audio error: $e');
      if (!mounted) return;
      setState(() => _latestAudioLoading = false);
    }
  }

  Widget _audioTabChip(String label, int tab) {
    final selected = _audioTab == tab;

    return Padding(
      padding: EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => setState(() => _audioTab = tab),
        selectedColor: _purple,
        backgroundColor: SC.cardBg,
        side: BorderSide(color: _purple),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: TextStyle(
          color: selected ? _onPurple : _white,
          fontWeight: FontWeight.w700,
        ),
        showCheckmark: false,
      ),
    );
  }

  Widget _latestAudioSection() {
    final songs = switch (_audioTab) {
      0 => _latestAudio?.bollywood ?? <Song>[],
      1 => _latestAudio?.pakistani ?? <Song>[],
      _ => _latestAudio?.english ?? <Song>[],
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'Latest Songs',
                  style: TextStyle(
                    color: _purple,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Latest songs refresh karein',
              onPressed: _latestAudioLoading ? null : _loadLatestAudio,
              icon: Icon(Icons.refresh_rounded, color: _purple, size: 22),
            ),
          ],
        ),
        Row(
          children: [
            _audioTabChip('Bollywood', 0),
            _audioTabChip('Pakistani', 1),
            _audioTabChip('English', 2),
          ],
        ),
        SizedBox(height: 14),
        if (_latestAudioLoading)
          Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: _purple),
            ),
          )
        else if (songs.isEmpty)
          Text(
            LatestAudioService.instance.lastError ??
                'Abhi koi naya gaana nahi mila.',
            style: TextStyle(color: _white, height: 1.4),
          )
        else
          _horizontal(
            count: songs.length,
            item: (context, i) => _songCard(songs, i),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH (logic pehle jaisa)
  // ---------------------------------------------------------------------------

  void _onSearchChanged(String text) {
    _debounce?.cancel();

    if (text.trim().isEmpty) {
      _search('');
      return;
    }

    _debounce = Timer(
      Duration(milliseconds: 900),
      () => _search(text),
    );
  }

  /// Playable songs: iTunes (India + US store). Khali/rate-limit ho to Deezer.
  Future<List<Song>> _searchPlayable(String q) =>
      CatalogService.instance.searchPlayable(q);

  Future<void> _search(String text) async {
    final q = text.trim();
    final id = ++_reqId;

    if (q.isEmpty) {
      if (!mounted) return;

      setState(() {
        _query = '';
        _results = [];
        _youtubeResults = [];
        _searching = false;
        _ytSearching = false;
        _searchError = null;
        _ytSearchError = null;
      });
      return;
    }

    setState(() {
      _query = q;
      _searching = true;
      _ytSearching = true;
      _searchError = null;
      _ytSearchError = null;
    });

    Future<void> songsTask() async {
      try {
        final songs = await _searchPlayable(q);
        if (!mounted || id != _reqId) return;

        setState(() {
          _results = songs;
          _searching = false;
        });
      } catch (e) {
        if (!mounted || id != _reqId) return;

        setState(() {
          _results = [];
          _searching = false;
          _searchError = 'Songs search nahi ho saka.';
        });
      }
    }

    Future<void> videosTask() async {
      try {
        final videos = await YouTubeMusicService.instance.searchSongs(q);
        if (!mounted || id != _reqId) return;

        setState(() {
          _youtubeResults = videos;
          _ytSearching = false;
        });
      } catch (e) {
        if (!mounted || id != _reqId) return;

        setState(() {
          _youtubeResults = [];
          _ytSearching = false;
          _ytSearchError = e is YouTubeApiException
              ? e.message
              : 'YouTube search fail hui.';
        });

        debugPrint('YouTube search error: $e');
      }
    }

    // Dono ek saath chalte hain, ek doosre ko block nahi karte.
    await Future.wait([songsTask(), videosTask()]);

    // Agar audio catalog mein gaana nahi mila magar video mil gayi, to video
    // ke naam se audio dobara dhoondo (taake audio aur video dono aayen).
    if (mounted &&
        id == _reqId &&
        _results.isEmpty &&
        _youtubeResults.isNotEmpty) {
      try {
        final alt =
            await _searchPlayable(_cleanTitle(_youtubeResults.first.title));
        if (!mounted || id != _reqId) return;
        if (alt.isNotEmpty) setState(() => _results = alt);
      } catch (_) {}
    }
  }

  /// YouTube title se "(Official Video)", "Lyrics" jaisa kachra hata kar
  /// audio search ke liye saaf naam banata hai.
  String _cleanTitle(String t) {
    return t
        .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
        .replaceAll(
          RegExp(
            r'\b(official|video|audio|lyrics?|lyrical|full song|hd|4k|music|song)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'[|\-\u2013:]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Video wale gaane ka audio dhoond kar download karta hai.
  Future<void> _downloadAudioFor(YouTubeSong video) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Audio dhoond rahe hain...'),
        duration: Duration(seconds: 1),
      ),
    );

    try {
      final matches = await _searchPlayable(_cleanTitle(video.title));
      if (!mounted) return;

      if (matches.isEmpty) {
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(content: Text('Is video ka audio nahi mila.')),
        );
        return;
      }

      await startDownload(context, matches.first);
    } catch (_) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Audio download nahi ho saka.')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good Morning,';
    if (h < 17) return 'Good Afternoon,';
    return 'Good Evening,';
  }

  String _userName() {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim();

    if (name != null && name.isNotEmpty) return name;

    final email = user?.email;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }

    return 'Music Lover';
  }

  void _openYouTubeVideo(List<YouTubeSong> videos, int index) {
    FocusScope.of(context).unfocus();

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => YouTubePlayerPage(videos: videos, index: index),
      ),
    );
  }

  void _openMenu() {
    final user = FirebaseAuth.instance.currentUser;

    showModalBottomSheet(
      context: context,
      backgroundColor: SC.cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.person_outline, color: _purple),
              title: Text(
                user?.email ?? 'Guest',
                style: TextStyle(color: _white),
              ),
            ),
            ListTile(
              leading: Icon(Icons.logout, color: _purple),
              title: Text(
                'Logout',
                style: TextStyle(color: _white),
              ),
              onTap: () async {
                Navigator.of(ctx).pop();

                await PlayerService.instance.stop();
                await AuthService.instance.signOut();

                if (!mounted) return;

                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => LoginPage()),
                  (_) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openPlaylist(String title, List<Song> songs) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistPage(title: title, songs: songs),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HEADER  (logo left, actions right)
  // ---------------------------------------------------------------------------

  Widget _roundIcon(IconData icon, String tip, VoidCallback onTap) {
    return Container(
      margin: EdgeInsets.only(left: 8),
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SC.cardBg,
        border: Border.all(color: _purple),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: tip,
        onPressed: onTap,
        icon: Icon(icon, color: _white, size: 20),
      ),
    );
  }

  /// Top-right par user ki profile photo (Profile page jaisi).
  /// Photo na ho to naam ka pehla harf dikhta hai. Tap par menu khulta hai.
  Widget _profileButton() {
    final user = FirebaseAuth.instance.currentUser;

    return GestureDetector(
      onTap: _openMenu,
      child: Container(
        margin: EdgeInsets.only(left: 8),
        padding: EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _purple, width: 1.6),
          boxShadow: [
            BoxShadow(color: _purple.withAlpha(90), blurRadius: 10),
          ],
        ),
        child: UserAvatar(
          photoUrl: userPhotoUrl(user),
          name: _userName(),
          size: 34,
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Image.asset(
          'assets/images/Logo.png',
          height: 100,
          width: 100,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Sound', style: TextStyle(color: _white)),
                TextSpan(text: 'Clock', style: TextStyle(color: _purple)),
              ],
            ),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),
        Spacer(),
        _roundIcon(Icons.refresh_rounded, 'Refresh music', _load),
        _profileButton(),
      ],
    );
  }

  Widget _greetingBlock() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _greeting(),
            style: TextStyle(color: _purple, fontSize: 14),
          ),
          SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${_userName()} '),
                TextSpan(text: '👑', style: TextStyle(fontSize: 20)),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH BAR
  // ---------------------------------------------------------------------------

  Widget _searchBar() {
    return Container(
      height: 50,
      padding: EdgeInsets.symmetric(horizontal: 14),
      decoration: SC.themedCard(radius: 16),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: _purple),
          SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (t) {
                setState(() {});
                _onSearchChanged(t);
              },
              onSubmitted: (t) {
                LibraryService.instance.addRecentSearch(t);
                _search(t);
              },
              textInputAction: TextInputAction.search,
              style: TextStyle(color: _white),
              cursorColor: _purple,
              decoration: InputDecoration(
                hintText: 'Search songs, artists, albums...',
                hintStyle: TextStyle(color: _white.withAlpha(150)),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                FocusScope.of(context).unfocus();
                _search('');
                setState(() {});
              },
              child: Icon(Icons.close_rounded, color: _white),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SEARCH RESULTS
  // ---------------------------------------------------------------------------

  Widget _searchResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Results for "$_query"',
          style: TextStyle(
            color: _purple,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 14),

        // ---- Audio / Video switch ----
        Row(
          children: [
            _searchTabChip('Audio', 0, _searching ? null : _results.length),
            SizedBox(width: 10),
            _searchTabChip(
                'Video', 1, _ytSearching ? null : _youtubeResults.length),
          ],
        ),
        SizedBox(height: 16),

        // ---- Audio (playable, download ke saath) ----
        if (_searchTab == 0) ...[
          if (_searching)
            Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: _purple),
              ),
            )
          else if (_searchError != null)
            Text(_searchError!, style: TextStyle(color: _white))
          else if (_results.isEmpty)
            Text(
              'Koi playable song nahi mila.',
              style: TextStyle(color: _white),
            )
          else
            ...List.generate(_results.length, (i) {
              final song = _results[i];

              return ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  FocusScope.of(context).unfocus();
                  PlayerService.instance.playQueue(_results, i);
                },
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SongCover(url: song.imageUrl, size: 52),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _purple),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DownloadButton(song: song),
                    Icon(Icons.play_arrow_rounded, color: _purple),
                  ],
                ),
              );
            }),
        ],

        // ---- Video (YouTube, app ke andar chalti hain) ----
        if (_searchTab == 1) ...[
          if (_ytSearching)
            Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(color: _purple),
              ),
            )
          else if (_ytSearchError != null)
            Text(_ytSearchError!, style: TextStyle(color: _white))
          else if (_youtubeResults.isEmpty)
            Text(
              'YouTube par koi video nahi mili.',
              style: TextStyle(color: _white),
            )
          else
            ...List.generate(_youtubeResults.length, (i) {
              final video = _youtubeResults[i];

              return ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => _openYouTubeVideo(_youtubeResults, i),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    video.thumbnailUrl,
                    width: 88,
                    height: 54,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => SizedBox(
                      width: 88,
                      height: 54,
                      child: Icon(Icons.music_video, color: _purple),
                    ),
                  ),
                ),
                title: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  video.channel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _purple),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Audio download',
                      onPressed: () => _downloadAudioFor(video),
                      icon: Icon(
                        Icons.download_rounded,
                        color: _purple,
                      ),
                    ),
                    Icon(Icons.play_circle_outline_rounded, color: _purple),
                  ],
                ),
              );
            }),
        ],
      ],
    );
  }

  Widget _searchTabChip(String label, int tab, int? count) {
    final selected = _searchTab == tab;
    final text = count == null ? label : '$label ($count)';

    return GestureDetector(
      onTap: () => setState(() => _searchTab = tab),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _purple : SC.cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _purple),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: selected ? _onPurple : _white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HERO BANNER  (Chill Vibes + Play Now)
  // ---------------------------------------------------------------------------

  Widget _banner() {
    final chill =
        _lists.length > _chillIndex ? _lists[_chillIndex] : <Song>[];

    return GestureDetector(
      onTap: chill.isEmpty
          ? null
          : () => PlayerService.instance.playQueue(chill, 0),
      child: Container(
        height: 176,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: _purple.withAlpha(90), blurRadius: 22),
          ],
          color: SC.cardBg,
        ),
        // Border image ke UPAR banta hai (foreground), warna image us ko
        // dhak leti thi aur kinaare/radius ghaib nazar aate thay.
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _purple, width: 1.6),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Banner image: poore section par (upar-neeche koi khali patti nahi)
            // Bina cut ke poori image chahiye to cover ki jagah BoxFit.fill likhein.
            Image.asset(
              'assets/images/chillVip.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => SizedBox.shrink(),
            ),
            // Left side halka dark purple, taake text saaf padha jaye
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0xFF1B0F4D).withAlpha(190),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Text + Play Now button
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: _purple,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'New',
                            style: TextStyle(
                              color: _onPurple,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Chill Vibes',
                          style: TextStyle(
                            color: _onPurple,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Relax • Focus • Feel Good',
                          style: TextStyle(color: _onPurple, fontSize: 13),
                        ),
                        SizedBox(height: 12),
                        // Tap poore banner par handle hota hai, ye sirf dikhawat hai.
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _purple,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: _purple.withAlpha(110),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: _onPurple, size: 20),
                              SizedBox(width: 4),
                              Text(
                                'Play Now',
                                style: TextStyle(
                                  color: _onPurple,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, VoidCallback onSeeAll) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _purple,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          GestureDetector(
            onTap: onSeeAll,
            child: Text(
              'See All',
              style: TextStyle(
                color: _purple,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _songCard(List<Song> list, int i) {
    final song = list[i];

    return GestureDetector(
      onTap: () => PlayerService.instance.playQueue(list, i),
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _purple.withAlpha(120)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(15),
                    child: SongCover(url: song.imageUrl, size: 110),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: DownloadButton(song: song, compact: true),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _purple, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playlistCard(int i) {
    final def = _playlists[i];
    final songs = i < _lists.length ? _lists[i] : <Song>[];
    final cover = songs.isNotEmpty ? songs.first.imageUrl : '';
    final isTop = def.title == 'Top 50';

    return GestureDetector(
      onTap: songs.isEmpty ? null : () => _openPlaylist(def.title, songs),
      child: SizedBox(
        width: 112,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _purple.withAlpha(120)),
                boxShadow: [
                  BoxShadow(
                    color: _purple.withAlpha(60),
                    blurRadius: 14,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [_purple, _purple.withAlpha(150)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: isTop || cover.isEmpty
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              def.title,
                              style: TextStyle(
                                color: _onPurple,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              def.subtitle,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _onPurple,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        )
                      : SongCover(url: cover, size: 110),
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              def.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              def.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _purple, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _horizontal({
    required int count,
    required IndexedWidgetBuilder item,
  }) {
    return SizedBox(
      height: 184,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 4),
        itemCount: count,
        separatorBuilder: (_, __) => SizedBox(width: 14),
        itemBuilder: item,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HOME CONTENT
  // ---------------------------------------------------------------------------

  Widget _content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loading)
          Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(color: _purple),
            ),
          )
        else if (_error != null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _white, height: 1.4),
                ),
                TextButton(
                  onPressed: _load,
                  child: Text(
                    'Dobara try karein',
                    style: TextStyle(color: _purple),
                  ),
                ),
              ],
            ),
          )
        else ...[
          _banner(),
          SizedBox(height: 26),
          ValueListenableBuilder<List<Song>>(
            valueListenable: PlayerService.instance.recent,
            builder: (context, recent, _) {
              final list = recent.isNotEmpty
                  ? recent
                  : (_popular.isNotEmpty
                      ? _popular.take(15).toList()
                      : _indian);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeader(
                    'Recently Played',
                    () => _openPlaylist('Recently Played', list),
                  ),
                  SizedBox(height: 14),
                  _horizontal(
                    count: list.length,
                    item: (context, i) => _songCard(list, i),
                  ),
                ],
              );
            },
          ),
          SizedBox(height: 24),
          _sectionHeader(
            'Trending Playlists',
            () => _openPlaylist(
              'Top 50',
              _lists.isNotEmpty ? _lists.first : <Song>[],
            ),
          ),
          SizedBox(height: 14),
          _horizontal(
            count: _playlists.length,
            item: (context, i) => _playlistCard(i),
          ),
          SizedBox(height: 28),
        ],

        // Latest audio, Audius/iTunes loading se independent.
        _latestAudioSection(),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SC.pageBg,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: _purple,
          backgroundColor: SC.cardBg,
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 8, 14, 24),
            children: [
              _header(),
              SizedBox(height: 16),
              _greetingBlock(),
              SizedBox(height: 14),
              _searchBar(),
              SizedBox(height: 22),
              if (_query.isNotEmpty) _searchResults() else _content(),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PLAYLIST PAGE  (design ka "Playlist Screen")
// -----------------------------------------------------------------------------

class PlaylistPage extends StatelessWidget {
  final String title;
  final List<Song> songs;

  const PlaylistPage({
    super.key,
    required this.title,
    required this.songs,
  });

  String _fmt(int sec) {
    final m = (sec ~/ 60).toString();
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _cover() {
    final url = songs.isNotEmpty ? songs.first.imageUrl : '';

    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _purple.withAlpha(120)),
        color: _purple,
        boxShadow: [
          BoxShadow(color: _purple.withAlpha(110), blurRadius: 30),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: url.isEmpty
            ? Icon(Icons.queue_music_rounded, color: _onPurple, size: 64)
            : SongCover(url: url, size: 178),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 6),
        Center(child: _cover()),
        SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _purple,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 4),
        Text(
          '${songs.length} Songs',
          style: TextStyle(color: _white, fontSize: 13),
        ),
        SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () => PlayerService.instance.playQueue(songs, 0),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: _onPurple,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: Icon(Icons.play_arrow_rounded, size: 22),
                  label: Text(
                    'Play',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final shuffled = [...songs]..shuffle();
                    PlayerService.instance.playQueue(shuffled, 0);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _white,
                    side: BorderSide(color: _purple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: Icon(Icons.shuffle_rounded, size: 20),
                  label: Text(
                    'Shuffle',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SC.pageBg,
      appBar: AppBar(
        backgroundColor: SC.pageBg,
        foregroundColor: _white,
        elevation: 0,
        actions: [
          if (songs.isNotEmpty)
            IconButton(
              tooltip: 'Download all',
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                messenger.showSnackBar(
                  SnackBar(
                    content:
                        Text('${songs.length} gaane download ho rahe hain...'),
                  ),
                );
                final ok = await DownloadService.instance.downloadAll(songs);
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(content: Text('$ok gaane download ho gaye')),
                );
              },
              icon: Icon(
                Icons.download_for_offline_rounded,
                color: _purple,
                size: 26,
              ),
            ),
        ],
      ),
      body: songs.isEmpty
          ? Center(
              child: Text(
                'Is playlist mein abhi koi gaana nahi',
                style: TextStyle(color: _white),
              ),
            )
          : ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: songs.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _header(context);

                final i = index - 1;
                final song = songs[i];

                return ListTile(
                  contentPadding: EdgeInsets.symmetric(vertical: 2),
                  onTap: () => PlayerService.instance.playQueue(songs, i),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SongCover(url: song.imageUrl, size: 52),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _purple),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _fmt(song.durationSec),
                        style: TextStyle(color: _white),
                      ),
                      DownloadButton(song: song),
                    ],
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: MiniPlayer(),
      ),
    );
  }
}