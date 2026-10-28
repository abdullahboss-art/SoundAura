import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:soundclock/Player%20service%20.dart';
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/premium_sheet.dart';
import 'package:soundclock/sleep_timer_sheet.dart';

import 'package:soundclock/song.dart';
import 'package:soundclock/song_actions.dart';
import 'package:soundclock/sc_theme.dart';

// -----------------------------------------------------------------------------
// SIRF DO COLOR: Purple (SC.primary) aur White.
// Dark theme me text safed, light theme me gehra dark (taake ghaib na ho).
// -----------------------------------------------------------------------------
Color get _purple => SC.primary;
Color get _text => SC.isDark ? Colors.white : Color(0xFF1B0F4D);
const Color _onPurple = Colors.white; // purple ke upar hamesha safed

/// MelodyHub colors.
///
/// NOTE: dusri files (sleep timer, premium sheet waghera) abhi bhi
/// MelodyColors.orange / pink / cyan use kar sakti hain. Un sab ko purple
/// karne ke liye neeche ke teeno const purple kar diye hain, taake wahan bhi
/// orange/pink/cyan ki jagah purple aaye.
/// Agar aapka SC.primary is hex (0xFF7C5CFF) se alag ho to yahan wohi hex likhein.
class MelodyColors {
  static const background = Color(0xFF080D1C);
  static const surface = Color(0xFF0F1A33);
  static const border = Color(0xFF1E3A5F);
  static const cyan = Color(0xFF7C5CFF); // pehle cyan tha -> ab purple
  static const orange = Color(0xFF7C5CFF); // pehle orange tha -> ab purple
  static const pink = Color(0xFF7C5CFF); // pehle pink tha -> ab purple

  // Theme ke hisaab se badalne wale rang.
  static Color get bgT => SC.pageBg;
  static Color get surfaceT => SC.cardBg;
  static Color get borderT => SC.primary.withAlpha(90);
  static Color get cyanT => SC.primary; // artist names waghera ab purple
}

/// Gaane ka cover image (na mile to music icon dikhata hai).
class SongCover extends StatelessWidget {
  final String url;
  final double size;
  const SongCover({super.key, required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_purple, _purple.withAlpha(140)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.music_note_rounded,
          color: _onPurple, size: size * 0.4),
    );

    if (url.isEmpty) return fallback;

    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : fallback,
    );
  }
}

/// Play / Pause / Loading button.
class PlayPauseButton extends StatelessWidget {
  final double size;
  final bool filled;
  const PlayPauseButton({super.key, this.size = 40, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final ps = PlayerService.instance;

    return StreamBuilder<PlayerState>(
      stream: ps.player.playerStateStream,
      builder: (context, snap) {
        final state = snap.data;
        final busy = state?.processingState == ProcessingState.loading ||
            state?.processingState == ProcessingState.buffering;
        final playing = state?.playing ?? false;

        // Bada (filled) button: dark theme me safed circle + purple icon,
        // taake purple background par saaf nazar aaye.
        final Color fillColor = SC.isDark ? Colors.white : _purple;
        final Color iconColor = filled
            ? (SC.isDark ? _purple : _onPurple)
            : _purple;

        final Widget child = busy
            ? SizedBox(
                width: size * 0.45,
                height: size * 0.45,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: iconColor,
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: iconColor,
                size: size * 0.62,
              );

        return GestureDetector(
          onTap: busy ? null : ps.togglePlay,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: filled
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    color: fillColor,
                    boxShadow: [
                      BoxShadow(
                        color: _purple.withAlpha(120),
                        blurRadius: 22,
                      ),
                    ],
                  )
                : null,
            child: child,
          ),
        );
      },
    );
  }
}

/// Bottom bar ke upar chhota player.
///
/// Premium: skip limit khatam hone par PlayerService "upgradeRequests" badhata
/// hai, aur ye widget (jo hamesha screen par rehta hai) Premium sheet kholta hai.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  // Agar MiniPlayer kai jagah ho to sheet do baar na khule.
  static bool _upgradeOpen = false;

  @override
  void initState() {
    super.initState();
    PlayerService.instance.upgradeRequests.addListener(_onUpgrade);
  }

  @override
  void dispose() {
    PlayerService.instance.upgradeRequests.removeListener(_onUpgrade);
    super.dispose();
  }

  Future<void> _onUpgrade() async {
    if (!mounted || _upgradeOpen) return;
    _upgradeOpen = true;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(PlayerService.instance.upgradeReason)),
      );

    try {
      await showPremiumSheet(context);
    } finally {
      _upgradeOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ps = PlayerService.instance;

    return ValueListenableBuilder<Song?>(
      valueListenable: ps.current,
      builder: (context, song, _) {
        if (song == null) return SizedBox.shrink();

        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => NowPlayingPage(),
            ),
          ),
          child: Container(
            margin: EdgeInsets.fromLTRB(10, 6, 10, 6),
            decoration: BoxDecoration(
              color: SC.cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _purple.withAlpha(120)),
              boxShadow: [
                BoxShadow(color: _purple.withAlpha(40), blurRadius: 14),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.all(8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SongCover(url: song.imageUrl, size: 44),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              song.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _purple,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PlayPauseButton(size: 40),
                      IconButton(
                        onPressed: ps.next,
                        icon: Icon(Icons.skip_next_rounded, color: _text),
                      ),
                    ],
                  ),
                ),
                StreamBuilder<Duration>(
                  stream: ps.player.positionStream,
                  builder: (context, snap) {
                    final pos = snap.data ?? Duration.zero;
                    final totalMs = ps.player.duration?.inMilliseconds ??
                        song.durationSec * 1000;
                    final value = totalMs > 0
                        ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0)
                        : 0.0;
                    return LinearProgressIndicator(
                      value: value.toDouble(),
                      minHeight: 2.5,
                      backgroundColor: _purple.withAlpha(50),
                      color: _purple,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Poori screen wala player (seek bar, next / previous, sleep timer).
class NowPlayingPage extends StatelessWidget {
  const NowPlayingPage({super.key});

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ps = PlayerService.instance;
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final coverSize = (width - 64 < height * 0.34 ? width - 64 : height * 0.34)
        .clamp(160.0, 340.0)
        .toDouble();

    return Scaffold(
      backgroundColor: SC.isDark ? Color(0xFF3B2A9E) : SC.pageBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _text,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Now Playing',
            style: TextStyle(
              color: _text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            )),
        actions: [
          // Sleep timer: timer chal raha ho to purple + bacha hua waqt.
          ListenableBuilder(
            listenable: Listenable.merge([
              ps.sleepRemaining,
              PremiumService.instance,
            ]),
            builder: (context, _) {
              final left = ps.sleepRemaining.value;
              final isPro = PremiumService.instance.isPremium;
              final active = left != null && isPro;
              return IconButton(
                tooltip: 'Sleep timer',
                onPressed: () => showSleepTimerSheet(context),
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bedtime_rounded,
                      color: _text,
                      size: 24,
                    ),
                    if (!isPro)
                      Padding(
                        padding: EdgeInsets.only(left: 2),
                        child:
                            Icon(Icons.lock_rounded, color: _text, size: 14),
                      ),
                    if (active)
                      Padding(
                        padding: EdgeInsets.only(left: 3),
                        child: Text(
                          '${left!.inMinutes + 1}m',
                          style: TextStyle(
                            color: _text,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        // Poori screen par purple gradient (black nahi)
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: SC.isDark
                ? [Color(0xFF3B2A9E), Color(0xFF1E1259), Color(0xFF120A38)]
                : [_purple.withAlpha(70), _purple.withAlpha(24), SC.pageBg],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: ValueListenableBuilder<Song?>(
          valueListenable: ps.current,
          builder: (context, song, _) {
            if (song == null) {
              return Center(
                child: Text('Koi gaana nahi chal raha',
                    style: TextStyle(color: _text)),
              );
            }

            return Padding(
              padding: EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  Spacer(),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: _purple.withAlpha(110),
                          blurRadius: 36,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SongCover(url: song.imageUrl, size: coverSize),
                    ),
                  ),
                  SizedBox(height: 28),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      song.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _text,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      song.artist,
                      style: TextStyle(color: _text, fontSize: 15),
                    ),
                  ),
                  // Gaana device ki file se chal raha ho to ye chip dikhta hai.
                  ValueListenableBuilder<bool>(
                    valueListenable: ps.isOffline,
                    builder: (context, offline, _) {
                      if (!offline) return SizedBox(height: 14);
                      return Padding(
                        padding: EdgeInsets.only(top: 8, bottom: 14),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: _text.withAlpha(30),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _text.withAlpha(120),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download_done_rounded,
                                    size: 14, color: _text),
                                SizedBox(width: 5),
                                Text(
                                  'Offline (device se chal raha hai)',
                                  style: TextStyle(
                                    color: _text,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // Seek bar
                  StreamBuilder<Duration?>(
                    stream: ps.player.durationStream,
                    builder: (context, dSnap) {
                      final total =
                          dSnap.data ?? Duration(seconds: song.durationSec);
                      return StreamBuilder<Duration>(
                        stream: ps.player.positionStream,
                        builder: (context, pSnap) {
                          final pos = pSnap.data ?? Duration.zero;
                          final double maxMs = total.inMilliseconds > 0
                              ? total.inMilliseconds.toDouble()
                              : 1.0;
                          final double val = pos.inMilliseconds
                              .toDouble()
                              .clamp(0.0, maxMs)
                              .toDouble();

                          return Column(
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3.5,
                                  activeTrackColor: _text,
                                  inactiveTrackColor: _text.withAlpha(70),
                                  thumbColor: _text,
                                  overlayColor: _text.withAlpha(50),
                                ),
                                child: Slider(
                                  value: val,
                                  max: maxMs,
                                  onChanged: total.inMilliseconds > 0
                                      ? (v) => ps.seek(
                                          Duration(milliseconds: v.round()))
                                      : null,
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_fmt(pos),
                                        style: TextStyle(
                                            color: _text, fontSize: 12)),
                                    Text(_fmt(total),
                                        style: TextStyle(
                                            color: _text, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        iconSize: 42,
                        onPressed: ps.previous,
                        icon: Icon(Icons.skip_previous_rounded, color: _text),
                      ),
                      SizedBox(width: 18),
                      PlayPauseButton(size: 72, filled: true),
                      SizedBox(width: 18),
                      IconButton(
                        iconSize: 42,
                        onPressed: ps.next,
                        icon: Icon(Icons.skip_next_rounded, color: _text),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),

                  // Like / Download / Add to Playlist
                  SongActionsBar(song: song),
                  Spacer(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}