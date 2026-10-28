import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:soundclock/Player%20service%20.dart';
import 'package:soundclock/player_ui.dart';
import 'package:soundclock/youtube_music_service.dart';

class YouTubePlayerPage extends StatefulWidget {
  final List<YouTubeSong> videos;
  final int index;

  const YouTubePlayerPage({
    super.key,
    required this.videos,
    required this.index,
  });

  @override
  State<YouTubePlayerPage> createState() => _YouTubePlayerPageState();
}

class _YouTubePlayerPageState extends State<YouTubePlayerPage> {
  late final YoutubePlayerController _controller;

  StreamSubscription<YoutubePlayerValue>? _stateSub;
  Timer? _skipTimer;

  late int _index;
  PlayerState? _lastState;

  // Double-tap par "10 sec" ka indicator dikhane ke liye.
  bool _skipVisible = false;
  bool _skipLeft = true;

  YouTubeSong get _current => widget.videos[_index];

  @override
  void initState() {
    super.initState();

    _index = widget.index.clamp(0, widget.videos.length - 1);

    // Audio player aur video dono ek saath na chalein.
    PlayerService.instance.player.pause();

    _controller = YoutubePlayerController.fromVideoId(
      videoId: _current.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        playsInline: true,
        strictRelatedVideos: true,
      ),
    );

    // Video khatam ho to agli video chalao.
    _stateSub = _controller.stream.listen((value) {
      final s = value.playerState;
      if (s == PlayerState.ended && _lastState != PlayerState.ended) {
        _nextVideo();
      }
      _lastState = s;
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _skipTimer?.cancel();
    _controller.close();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Controls
  // ---------------------------------------------------------------------------

  Future<void> _playIndex(int i) async {
    if (i < 0 || i >= widget.videos.length) return;

    setState(() => _index = i);
    await _controller.loadVideoById(videoId: _current.videoId);
  }

  Future<void> _nextVideo() => _playIndex(_index + 1);

  Future<void> _previousVideo() async {
    double current = 0;
    try {
      current = await _controller.currentTime;
    } catch (_) {}

    // 3 second se zyada chal chuki ho to usi video ko shuru se chalao.
    if (current > 3 || _index == 0) {
      await _controller.seekTo(seconds: 0, allowSeekAhead: true);
      return;
    }
    await _playIndex(_index - 1);
  }

  /// Position hum player se seedha poochte hain (videoStateStream use nahi
  /// karte, wo web par error deta hai aur position hamesha 0 reh jati thi).
  Future<void> _skip(double seconds) async {
    try {
      final current = await _controller.currentTime;
      final total = await _controller.duration;

      var target = current + seconds;
      if (target < 0) target = 0;
      if (total > 0 && target > total) target = total;

      await _controller.seekTo(seconds: target, allowSeekAhead: true);
    } catch (_) {}
  }

  Future<void> _togglePlayPause() async {
    if (_controller.value.playerState == PlayerState.playing) {
      await _controller.pauseVideo();
    } else {
      await _controller.playVideo();
    }
  }

  void _doubleTapSkip(bool left) {
    _skip(left ? -10 : 10);

    _skipTimer?.cancel();
    setState(() {
      _skipLeft = left;
      _skipVisible = true;
    });
    _skipTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _skipVisible = false);
    });
  }

  Future<void> _openOnYouTube() async {
    final uri = Uri.parse('https://www.youtube.com/watch?v=${_current.videoId}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  // ---------------------------------------------------------------------------
  // Video area (YouTube jaisa: double-tap left/right = 10 sec)
  // ---------------------------------------------------------------------------

  /// PointerInterceptor zaroori hai Flutter web par, warna iframe saare
  /// clicks pakad leta hai. Beech ka hissa, upar ki patti aur neeche ki
  /// control bar khali chhodi hai taake YouTube ke apne buttons chalein.
  Widget _tapZone({required bool left}) {
    final show = _skipVisible && _skipLeft == left;

    return PointerInterceptor(
      child: SizedBox.expand(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlayPause,
          onDoubleTap: () => _doubleTapSkip(left),
          child: Center(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: show ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        left
                            ? Icons.fast_rewind_rounded
                            : Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '10 sec',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoPlayer() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: LayoutBuilder(
        builder: (context, c) {
          final zoneWidth = c.maxWidth * 0.3;
          return Stack(
            children: [
              Positioned.fill(
                child: YoutubePlayer(controller: _controller),
              ),
              Positioned(
                left: 0,
                top: 48,
                bottom: 56,
                width: zoneWidth,
                child: _tapZone(left: true),
              ),
              Positioned(
                right: 0,
                top: 48,
                bottom: 56,
                width: zoneWidth,
                child: _tapZone(left: false),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Info section (title, channel, action chips)
  // ---------------------------------------------------------------------------

  Widget _chip(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: MelodyColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoSection() {
    final channel = _current.channel;
    final letter = channel.isNotEmpty ? channel[0].toUpperCase() : '?';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Text(
            _current.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: MelodyColors.orange,
                child: Text(
                  letter,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  channel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${_index + 1} / ${widget.videos.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              _chip(Icons.skip_previous_rounded, 'Previous', _previousVideo),
              _chip(Icons.skip_next_rounded, 'Next', _nextVideo),
              _chip(Icons.open_in_new_rounded, 'YouTube par', _openOnYouTube),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Divider(color: Colors.white12, height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text(
            'Up next',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Up next list
  // ---------------------------------------------------------------------------

  Widget _upNextTile(int i) {
    final v = widget.videos[i];
    final selected = i == _index;

    return InkWell(
      onTap: () => _playIndex(i),
      child: Container(
        color: selected ? MelodyColors.surface : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                v.thumbnailUrl,
                width: 160,
                height: 90,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 160,
                  height: 90,
                  child: Icon(Icons.music_video, color: Colors.white54),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    v.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? MelodyColors.orange : Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    v.channel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  if (selected) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Now playing',
                      style: TextStyle(
                        color: MelodyColors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MelodyColors.background,
      appBar: AppBar(
        backgroundColor: MelodyColors.background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Music Video',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: widget.videos.isEmpty
          ? const Center(
              child: Text(
                'Koi video nahi mili',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : Column(
              children: [
                _videoPlayer(),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.videos.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) return _infoSection();
                      return _upNextTile(i - 1);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}