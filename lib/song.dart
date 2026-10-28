/// Gaane ka model. Poori app (Audius, Deezer, iTunes, Jamendo) yahi use karti hai.
class Song {
  final String id;
  final String title;
  final String artist;
  final String imageUrl;
  final String audioUrl;
  final int durationSec;

  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.audioUrl,
    required this.durationSec,
  });

  /// Jamendo API ke track se Song banata hai.
  factory Song.fromJson(Map<String, dynamic> json) {
    final duration = json['duration'];

    return Song(
      id: (json['id'] ?? '').toString(),
      title: (json['name'] ?? json['title'] ?? '').toString(),
      artist: (json['artist_name'] ?? json['artist'] ?? 'Unknown').toString(),
      imageUrl: (json['image'] ?? json['album_image'] ?? '').toString(),
      audioUrl: (json['audio'] ?? json['audiodownload'] ?? '').toString(),
      durationSec: duration is num
          ? duration.toInt()
          : int.tryParse(duration?.toString() ?? '') ?? 0,
    );
  }
}