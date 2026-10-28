import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:soundclock/Player%20service%20.dart';
import 'package:soundclock/download_service.dart';
import 'package:soundclock/player_ui.dart';
import 'package:soundclock/premium_gate.dart';
import 'package:soundclock/premium_service.dart';
import 'package:soundclock/premium_sheet.dart';
import 'package:soundclock/sc_theme.dart';
import 'package:soundclock/song.dart';
import 'package:soundclock/song_actions.dart';

// -----------------------------------------------------------------------------
// Only two colors: Purple (SC.primary) and White (theme text color).
// Getters, so they update when the dark/light theme changes.
// -----------------------------------------------------------------------------
Color get _purple => SC.primary;
Color get _text => SC.text;
Color get _surface => SC.cardBg;
const Color _onPurple = Colors.white; // always white on top of purple

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  void _play(List<DownloadedSong> items, int index) {
    PlayerService.instance.playQueue(
      items.map((e) => e.playable).toList(),
      index,
    );
  }

  Future<void> _confirmDelete(BuildContext context, DownloadedSong item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _purple.withAlpha(120)),
        ),
        title: Text('Delete download?',
            style: TextStyle(color: _purple, fontWeight: FontWeight.w800)),
        content: Text('"${item.song.title}" will be removed from your device.',
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

    if (yes == true) await DownloadService.instance.remove(item.song.id);
  }

  /// Delete all downloads at once.
  Future<void> _confirmDeleteAll(BuildContext context) async {
    final count = DownloadService.instance.items.length;

    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: _purple.withAlpha(120)),
        ),
        title: Text('Delete all downloads?',
            style: TextStyle(color: _purple, fontWeight: FontWeight.w800)),
        content: Text('$count songs will be removed from your device.',
            style: TextStyle(color: _text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: _text)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Delete all', style: TextStyle(color: _purple)),
          ),
        ],
      ),
    );

    if (yes == true) await DownloadService.instance.clearAll();
  }

  Widget _storageCard(DownloadService ds) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _purple.withAlpha(120)),
        boxShadow: [
          BoxShadow(color: _purple.withAlpha(40), blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _purple.withAlpha(40),
            ),
            child: Icon(Icons.sd_storage_rounded, color: _purple),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Storage Used',
                  style: TextStyle(color: _purple, fontSize: 12),
                ),
                SizedBox(height: 2),
                Text(
                  kIsWeb
                      ? '${ds.items.length} songs'
                      : '${formatBytes(ds.totalBytes)} • ${ds.items.length} songs',
                  style: TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          if (ds.items.isNotEmpty)
            TextButton.icon(
              onPressed: () => _play(ds.items, 0),
              style: TextButton.styleFrom(
                backgroundColor: _purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              icon: Icon(Icons.play_arrow_rounded, color: _onPurple),
              label: Text('Play all', style: TextStyle(color: _onPurple)),
            ),
        ],
      ),
    );
  }

  /// Friendly banner shown on web only.
  Widget _webInfoBanner() {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _purple.withAlpha(30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _purple.withAlpha(120)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _purple,
            ),
            child: Icon(Icons.headphones_rounded, color: _onPurple, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Listen offline anytime',
                  style: TextStyle(
                    color: _purple,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your downloads list is ready. Get SoundClock on Android '
                  'or iOS to play your downloaded songs without internet.',
                  style: TextStyle(color: _text, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activeTile(Song song, double progress) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SongCover(url: song.imageUrl, size: 52),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _text, fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: EdgeInsets.only(top: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            minHeight: 3,
            color: _purple,
            backgroundColor: _purple.withAlpha(50),
          ),
        ),
      ),
      trailing: Text('Downloading',
          style: TextStyle(color: _purple, fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SC.pageBg,
      child: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: DownloadService.instance,
          builder: (context, _) {
            final ds = DownloadService.instance;
            final items = ds.items;
            final active = ds.active;

            return ListView(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                // Title + delete-all button
                Padding(
                  padding: EdgeInsets.only(left: 2, bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Downloads',
                          style: TextStyle(
                            color: _purple,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (items.isNotEmpty)
                        IconButton(
                          tooltip: 'Delete all',
                          onPressed: () => _confirmDeleteAll(context),
                          icon: Icon(Icons.delete_sweep_rounded,
                              color: _purple),
                        ),
                    ],
                  ),
                ),
                _storageCard(ds),

                // Free users see an "x / limit" meter (premium users don't)
                SizedBox(height: 10),
                UsageMeter(
                  icon: Icons.download_done_rounded,
                  label: 'Downloads',
                  used: items.length,
                  limit: PremiumService.freeDownloadLimit,
                  reason: PremiumReason.downloads,
                ),

                if (kIsWeb)
                  Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: _webInfoBanner(),
                  ),
                SizedBox(height: 10),
                for (final entry in active.entries)
                  if (ds.activeSong(entry.key) != null)
                    _activeTile(ds.activeSong(entry.key)!, entry.value),
                if (items.isEmpty && active.isEmpty)
                  Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Column(
                      children: [
                        Icon(Icons.download_for_offline_rounded,
                            color: _purple.withAlpha(150), size: 72),
                        SizedBox(height: 12),
                        Text(
                          'No downloads yet.\nTap the download button on any song to get started.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _text, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                for (var i = 0; i < items.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.symmetric(vertical: 2),
                    onTap: () => _play(items, i),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SongCover(url: items[i].song.imageUrl, size: 52),
                    ),
                    title: Text(
                      items[i].song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    // Artist name: purple
                    subtitle: Text(
                      kIsWeb
                          ? items[i].song.artist
                          : '${items[i].song.artist} • ${formatBytes(items[i].bytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _purple),
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(context, items[i]),
                      icon: Icon(Icons.delete_outline_rounded, color: _purple),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}