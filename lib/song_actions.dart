import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:soundclock/Library%20service%20.dart';
import 'package:soundclock/download_service.dart';
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/premium_sheet.dart';

import 'package:soundclock/player_ui.dart';
import 'package:soundclock/song.dart';
import 'package:soundclock/sc_theme.dart';

// -----------------------------------------------------------------------------
// Only two colors: Purple (SC.primary) and White.
// -----------------------------------------------------------------------------
// _white = theme text color (white in dark mode, dark navy in light mode).
Color get _white => SC.isDark ? Colors.white : Color(0xFF1B0F4D);
const Color _onPurple = Colors.white;
Color get _purple => SC.primary;
// Accent that stays visible on the purple Now Playing background
// (white in dark mode, purple in light mode).
Color get _accent => SC.isDark ? Colors.white : SC.primary;

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) {
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

// -----------------------------------------------------------------------------
// Styled snackbar (floating, purple, rounded)
// -----------------------------------------------------------------------------

void showAppSnack(
  ScaffoldMessengerState messenger,
  String text, {
  IconData icon = Icons.check_circle_rounded,
  Duration duration = const Duration(seconds: 3),
}) {
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      // Bottom margin keeps it above the mini player.
      margin: EdgeInsets.fromLTRB(16, 0, 16, 90),
      backgroundColor: SC.primary,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      duration: duration,
      content: Row(
        children: [
          Icon(icon, color: _onPurple, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: _onPurple,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Starts a download and shows status messages.
/// Free users are limited to PremiumService.freeDownloadLimit songs.
Future<void> startDownload(BuildContext context, Song song) async {
  final messenger = ScaffoldMessenger.of(context);
  final ds = DownloadService.instance;

  if (ds.isDownloaded(song.id)) {
    showAppSnack(
      messenger,
      '"${song.title}" is already in your Downloads',
      icon: Icons.download_done_rounded,
    );
    return;
  }

  // Premium limit
  if (!PremiumService.instance.canDownload(ds.items.length)) {
    showAppSnack(
      messenger,
      'Free plan includes ${PremiumService.freeDownloadLimit} downloads. '
      'Go Premium for unlimited downloads.',
      icon: Icons.workspace_premium_rounded,
    );
    showPremiumSheet(context);
    return;
  }

  showAppSnack(
    messenger,
    'Downloading: ${song.title}',
    icon: Icons.downloading_rounded,
    duration: Duration(seconds: 1),
  );

  final ok = await ds.download(song);

  if (ok) {
    showAppSnack(
      messenger,
      kIsWeb ? 'Added to your Downloads 🎶' : 'Downloaded: ${song.title}',
    );
  } else {
    showAppSnack(
      messenger,
      'Download failed. Please check your internet connection.',
      icon: Icons.error_outline_rounded,
    );
  }
}

/// Download button shown with every song.
/// compact = true: small round button on top of the cover.
class DownloadButton extends StatelessWidget {
  final Song song;
  final bool compact;

  const DownloadButton({super.key, required this.song, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadService.instance,
      builder: (context, _) {
        final ds = DownloadService.instance;
        final done = ds.isDownloaded(song.id);
        final progress = ds.progressOf(song.id);
        final double s = compact ? 17 : 24;

        final Widget icon;
        if (done) {
          // Tick after download: PURPLE
          icon = Icon(Icons.download_done_rounded, color: _purple, size: s);
        } else if (progress != null) {
          icon = SizedBox(
            width: s - 2,
            height: s - 2,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              value: progress > 0 ? progress : null,
              color: _purple,
            ),
          );
        } else {
          icon = Icon(Icons.download_rounded,
              color: compact ? _onPurple : _purple, size: s);
        }

        final VoidCallback? onTap =
            progress != null ? null : () => startDownload(context, song);

        if (compact) {
          return GestureDetector(
            onTap: onTap,
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: icon,
            ),
          );
        }

        return IconButton(
          onPressed: onTap,
          tooltip: done ? 'Downloaded' : 'Download',
          icon: icon,
        );
      },
    );
  }
}

/// Standard song row (cover, title, artist, download).
class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final bool showDownload;
  final Widget? extra;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.showDownload = true,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
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
          if (extra != null) extra!,
          if (showDownload) DownloadButton(song: song),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Playlist name dialog
// -----------------------------------------------------------------------------

Future<String?> askPlaylistName(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: SC.cardBg,
      title: Text(
        'New Playlist',
        style: TextStyle(color: _purple, fontWeight: FontWeight.w800),
      ),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        style: TextStyle(color: _white),
        cursorColor: _purple,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: _white.withAlpha(150)),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: _white.withAlpha(120)),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: _purple),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: _white)),
        ),
        TextButton(
          onPressed: _submit,
          child: Text('Create', style: TextStyle(color: _purple)),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Add to playlist
// -----------------------------------------------------------------------------

Future<void> showAddToPlaylistSheet(BuildContext context, Song song) {
  final messenger = ScaffoldMessenger.of(context);

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: SC.cardBg,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AddToPlaylistSheet(song: song, messenger: messenger),
  );
}

class _AddToPlaylistSheet extends StatelessWidget {
  final Song song;
  final ScaffoldMessengerState messenger;

  const _AddToPlaylistSheet({required this.song, required this.messenger});

  void _toast(String text, {IconData icon = Icons.check_circle_rounded}) {
    showAppSnack(messenger, text, icon: icon);
  }

  @override
  Widget build(BuildContext context) {
    final lib = LibraryService.instance;

    return SafeArea(
      child: ListenableBuilder(
        listenable: lib,
        builder: (ctx, _) {
          final names = lib.playlists.keys.toList();

          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Text(
                    'Add to Playlist',
                    style: TextStyle(
                      color: _purple,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.add_circle_outline_rounded,
                      color: _purple),
                  title: Text('New playlist',
                      style: TextStyle(color: _white)),
                  onTap: () async {
                    // Premium limit: free plan allows only a few playlists.
                    if (!PremiumService.instance
                        .canCreatePlaylist(lib.playlists.length)) {
                      final rootCtx =
                          Navigator.of(ctx, rootNavigator: true).context;
                      Navigator.of(ctx).pop();
                      _toast(
                        'Free plan includes ${PremiumService.freePlaylistLimit} '
                        'playlists. Go Premium for unlimited playlists.',
                        icon: Icons.workspace_premium_rounded,
                      );
                      showPremiumSheet(rootCtx);
                      return;
                    }

                    final name = await askPlaylistName(ctx);
                    if (name == null || !ctx.mounted) return;

                    if (!lib.createPlaylist(name)) {
                      _toast(
                        'A playlist with that name already exists.',
                        icon: Icons.info_outline_rounded,
                      );
                      return;
                    }
                    lib.addToPlaylist(name, song);
                    Navigator.of(ctx).pop();
                    _toast('Added to "$name"');
                  },
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final name in names)
                        ListTile(
                          leading: Icon(Icons.queue_music_rounded,
                              color: _purple),
                          title: Text(name,
                              style: TextStyle(color: _white)),
                          subtitle: Text(
                            '${lib.playlists[name]?.length ?? 0} songs',
                            style: TextStyle(color: _white.withAlpha(180)),
                          ),
                          onTap: () {
                            final added = lib.addToPlaylist(name, song);
                            Navigator.of(ctx).pop();
                            if (added) {
                              _toast('Added to "$name"');
                            } else {
                              _toast(
                                'This song is already in "$name"',
                                icon: Icons.info_outline_rounded,
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Below Now Playing: Like / Download / Add to Playlist
// -----------------------------------------------------------------------------

class SongActionsBar extends StatelessWidget {
  final Song song;

  const SongActionsBar({super.key, required this.song});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ListenableBuilder(
          listenable: LibraryService.instance,
          builder: (context, _) {
            final liked = LibraryService.instance.isLiked(song.id);
            return _ActionItem(
              icon: liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: liked ? 'Liked' : 'Like',
              color: liked ? _accent : _white,
              onTap: () => LibraryService.instance.toggleLike(song),
            );
          },
        ),
        ListenableBuilder(
          listenable: DownloadService.instance,
          builder: (context, _) {
            final ds = DownloadService.instance;
            final done = ds.isDownloaded(song.id);
            final p = ds.progressOf(song.id);

            return _ActionItem(
              icon: done ? Icons.download_done_rounded : Icons.download_rounded,
              label: done
                  ? 'Downloaded'
                  : (p != null
                      ? (p > 0 ? '${(p * 100).round()}%' : 'Wait...')
                      : 'Download'),
              color: done ? _accent : _white,
              onTap: p != null ? null : () => startDownload(context, song),
            );
          },
        ),
        _ActionItem(
          icon: Icons.playlist_add_rounded,
          label: 'Add to Playlist',
          color: _white,
          onTap: () => showAddToPlaylistSheet(context, song),
        ),
      ],
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(color: _white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}