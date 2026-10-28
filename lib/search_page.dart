import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soundclock/Library%20service%20.dart';
import 'package:soundclock/Player%20service%20.dart';
import 'package:soundclock/catalog_service.dart';
import 'package:soundclock/player_ui.dart';
import 'package:soundclock/song.dart';
import 'package:soundclock/song_actions.dart';
import 'package:soundclock/youtube_music_service.dart';
import 'package:soundclock/youtube_player_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const List<String> _trending = [
    'Atif Aslam',
    'Arijit Singh',
    'Asim Azhar',
    'Hasan Raheem',
    'Rahat Fateh Ali Khan',
    'Jubin Nautiyal',
    'Ali Sethi',
    'Shae Gill',
  ];

  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;
  int _reqId = 0;

  String _query = '';
  int _filter = 0; // 0 = All, 1 = Songs, 2 = Videos

  List<Song> _songs = [];
  List<YouTubeSong> _videos = [];
  bool _loadingSongs = false;
  bool _loadingVideos = false;
  String? _songsError;
  String? _videosError;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() {});
    _debounce?.cancel();

    if (text.trim().isEmpty) {
      _run('');
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 900), () => _run(text));
  }

  void _submit(String text) {
    _debounce?.cancel();
    LibraryService.instance.addRecentSearch(text);
    _run(text);
  }

  void _pick(String term) {
    _debounce?.cancel();
    _ctrl.text = term;
    _ctrl.selection = TextSelection.collapsed(offset: term.length);
    FocusScope.of(context).unfocus();
    LibraryService.instance.addRecentSearch(term);
    setState(() {});
    _run(term);
  }

  Future<void> _run(String text) async {
    final q = text.trim();
    final id = ++_reqId;

    if (q.isEmpty) {
      if (!mounted) return;
      setState(() {
        _query = '';
        _songs = [];
        _videos = [];
        _loadingSongs = false;
        _loadingVideos = false;
        _songsError = null;
        _videosError = null;
      });
      return;
    }

    setState(() {
      _query = q;
      _loadingSongs = true;
      _loadingVideos = true;
      _songsError = null;
      _videosError = null;
    });

    Future<void> songsTask() async {
      try {
        final songs = await CatalogService.instance.searchPlayable(q);
        if (!mounted || id != _reqId) return;
        setState(() {
          _songs = songs;
          _loadingSongs = false;
        });
      } catch (_) {
        if (!mounted || id != _reqId) return;
        setState(() {
          _songs = [];
          _loadingSongs = false;
          _songsError = 'Songs search nahi ho saka.';
        });
      }
    }

    Future<void> videosTask() async {
      try {
        final videos = await YouTubeMusicService.instance.searchSongs(q);
        if (!mounted || id != _reqId) return;
        setState(() {
          _videos = videos;
          _loadingVideos = false;
        });
      } catch (e) {
        if (!mounted || id != _reqId) return;
        setState(() {
          _videos = [];
          _loadingVideos = false;
          _videosError =
              e is YouTubeApiException ? e.message : 'YouTube search fail hui.';
        });
      }
    }

    await Future.wait([songsTask(), videosTask()]);
  }

  // ---------------------------------------------------------------------------
  // UI pieces
  // ---------------------------------------------------------------------------

  Widget _searchBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: MelodyColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MelodyColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Colors.white54),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              onSubmitted: _submit,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Colors.white),
              cursorColor: MelodyColors.orange,
              decoration: const InputDecoration(
                hintText: 'Search songs, artists...',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_ctrl.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _debounce?.cancel();
                _ctrl.clear();
                FocusScope.of(context).unfocus();
                setState(() {});
                _run('');
              },
              child: const Icon(Icons.close_rounded, color: Colors.white54),
            ),
        ],
      ),
    );
  }

  Widget _chip(String label, int value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _filter = value),
        selectedColor: MelodyColors.orange,
        backgroundColor: MelodyColors.surface,
        side: const BorderSide(color: MelodyColors.border),
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _title(String text, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _termRow(String term, IconData icon, {VoidCallback? onRemove}) {
    return InkWell(
      onTap: () => _pick(term),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.white54, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                term,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            if (onRemove != null)
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close_rounded,
                    color: Colors.white38, size: 20),
              )
            else
              const Icon(Icons.north_west_rounded,
                  color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _idle() {
    return ListenableBuilder(
      listenable: LibraryService.instance,
      builder: (context, _) {
        final recent = LibraryService.instance.recentSearches;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Trending Searches'),
            for (final t in _trending)
              _termRow(t, Icons.trending_up_rounded),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 16),
              _title(
                'Recent Searches',
                action: GestureDetector(
                  onTap: LibraryService.instance.clearRecentSearches,
                  child: const Text(
                    'Clear',
                    style: TextStyle(
                      color: MelodyColors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              for (final r in recent)
                _termRow(
                  r,
                  Icons.history_rounded,
                  onRemove: () => LibraryService.instance.removeRecentSearch(r),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _loader() => const Center(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: CircularProgressIndicator(color: MelodyColors.orange),
        ),
      );

  Widget _songsSection() {
    final Widget body;

    if (_loadingSongs) {
      body = _loader();
    } else if (_songsError != null) {
      body = Text(_songsError!, style: const TextStyle(color: Colors.white70));
    } else if (_songs.isEmpty) {
      body = const Text('Koi playable song nahi mila.',
          style: TextStyle(color: Colors.white54));
    } else {
      body = Column(
        children: [
          for (var i = 0; i < _songs.length; i++)
            SongTile(
              song: _songs[i],
              onTap: () {
                FocusScope.of(context).unfocus();
                PlayerService.instance.playQueue(_songs, i);
              },
              extra: const Icon(Icons.play_arrow_rounded,
                  color: MelodyColors.orange),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_title('Songs'), body],
    );
  }

  Widget _videosSection() {
    final Widget body;

    if (_loadingVideos) {
      body = _loader();
    } else if (_videosError != null) {
      body =
          Text(_videosError!, style: const TextStyle(color: Colors.white70));
    } else if (_videos.isEmpty) {
      body = const Text('YouTube par koi video nahi mili.',
          style: TextStyle(color: Colors.white54));
    } else {
      body = Column(
        children: [
          for (var i = 0; i < _videos.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () {
                FocusScope.of(context).unfocus();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        YouTubePlayerPage(videos: _videos, index: i),
                  ),
                );
              },
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _videos[i].thumbnailUrl,
                  width: 88,
                  height: 54,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 88,
                    height: 54,
                    child: Icon(Icons.music_video, color: Colors.white54),
                  ),
                ),
              ),
              title: Text(
                _videos[i].title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                _videos[i].channel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: MelodyColors.cyan),
              ),
              trailing: const Icon(Icons.play_circle_outline_rounded,
                  color: MelodyColors.orange),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_title('YouTube Videos'), body],
    );
  }

  Widget _results() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _chip('All', 0),
            _chip('Songs', 1),
            _chip('Videos', 2),
          ],
        ),
        const SizedBox(height: 10),
        if (_filter != 2) _songsSection(),
        if (_filter == 0) const SizedBox(height: 20),
        if (_filter != 1) _videosSection(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MelodyColors.background,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 2, bottom: 12),
              child: Text(
                'Search',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _searchBar(),
            const SizedBox(height: 16),
            if (_query.isEmpty) _idle() else _results(),
          ],
        ),
      ),
    );
  }
}
