import 'package:flutter/material.dart';
import 'package:soundclock/Player%20controller.dart';
import 'package:soundclock/song.dart';


/// Home page ka horizontal card
class SongCard extends StatelessWidget {
  final List<Song> songs;
  final int index;
  const SongCard({super.key, required this.songs, required this.index});

  @override
  Widget build(BuildContext context) {
    final song = songs[index];
    return GestureDetector(
      onTap: () => player.playQueue(songs, index),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                song.imageUrl,
                width: 140,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 140,
                  height: 140,
                  color: Colors.white12,
                  child: const Icon(Icons.music_note, size: 40),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            Text(song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Search results ki list row
class SongTile extends StatelessWidget {
  final List<Song> songs;
  final int index;
  const SongTile({super.key, required this.songs, required this.index});

  @override
  Widget build(BuildContext context) {
    final song = songs[index];
    return ListTile(
      onTap: () => player.playQueue(songs, index),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          song.imageUrl,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.music_note),
        ),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.play_arrow),
    );
  }
}