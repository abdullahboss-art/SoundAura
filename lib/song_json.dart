import 'package:soundclock/song.dart';

/// Song ko save karne (SharedPreferences) ke liye Map mein badalta hai.
Map<String, dynamic> songToMap(Song s) => <String, dynamic>{
      'id': s.id,
      'title': s.title,
      'artist': s.artist,
      'imageUrl': s.imageUrl,
      'audioUrl': s.audioUrl,
      'durationSec': s.durationSec,
    };

Song songFromMap(Map<dynamic, dynamic> m) {
  final dur = m['durationSec'];
  return Song(
    id: (m['id'] ?? '').toString(),
    title: (m['title'] ?? '').toString(),
    artist: (m['artist'] ?? '').toString(),
    imageUrl: (m['imageUrl'] ?? '').toString(),
    audioUrl: (m['audioUrl'] ?? '').toString(),
    durationSec: dur is num ? dur.toInt() : 0,
  );
}
