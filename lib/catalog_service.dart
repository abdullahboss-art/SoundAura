import 'package:flutter/foundation.dart';
import 'package:soundclock/Api%20client.dart';
import 'package:soundclock/Itunes%20service.dart';
import 'package:soundclock/audius_service.dart';
import 'package:soundclock/deezer_service.dart';
import 'package:soundclock/song.dart';

/// Home ke Top 50 aur search ke liye gaane.
///
/// Top 50 = Bollywood + Pakistani. Gaane chune hue artists se aate hain, is liye
/// English / Hollywood ya koi ajeeb gaana beech mein nahi aata.
class CatalogService {
  CatalogService._();

  static final CatalogService instance = CatalogService._();

  /// Pakistani artists. Jo gaana in mein se kisi artist ka na ho wo shamil nahi hota.
  static const List<String> pakistaniArtists = [
    'Atif Aslam',
    'Rahat Fateh Ali Khan',
    'Asim Azhar',
    'Ali Zafar',
    'Nusrat Fateh Ali Khan',
    'Abida Parveen',
    'Hasan Raheem',
    'Ali Sethi',
    'Shae Gill',
    'Talha Anjum',
    'Farhan Saeed',
    'Momina Mustehsan',
    'Bilal Saeed',
    'Junaid Jamshed',
    'Kaifi Khalil',
    'Young Stunners',
  ];

  static const List<String> bollywoodArtists = [
    'Arijit Singh',
    'Jubin Nautiyal',
    'Shreya Ghoshal',
    'Sonu Nigam',
    'Neha Kakkar',
    'Badshah',
    'Armaan Malik',
    'Darshan Raval',
    'B Praak',
    'Vishal Mishra',
    'KK',
    'Sunidhi Chauhan',
  ];

  static const List<String> _blockedWords = [
    'instrumental',
    'karaoke',
    'backing track',
    'no vocals',
    'without vocals',
    '8d audio',
    'slowed',
    'reverb',
    'sped up',
    'nightcore',
  ];

  /// Duplicate (title + artist) hata kar sirf playable songs rakhta hai.
  List<Song> mergeUnique(Iterable<Song> songs) {
    final seen = <String>{};
    final out = <Song>[];

    for (final s in songs) {
      if (s.audioUrl.trim().isEmpty || s.title.trim().isEmpty) continue;

      final artist = s.artist.split(' • ').first.trim().toLowerCase();
      final key = '${s.title.trim().toLowerCase()}|$artist';

      if (seen.add(key)) out.add(s);
    }
    return out;
  }

  bool _artistMatches(Song s, String artist) {
    final name = s.artist.split(' • ').first.toLowerCase();
    return name.contains(artist.toLowerCase());
  }

  /// Ek artist ke gaane. Deezer pehle, wo na chale to iTunes.
  Future<List<Song>> _artistSongs(
    String artist, {
    required bool allowFallback,
  }) async {
    var songs = (await DeezerService.instance
            .search('artist:"$artist"', limit: 12))
        .where((s) => _artistMatches(s, artist))
        .toList();

    if (songs.isEmpty && allowFallback) {
      final fallback = await ItunesService.instance
          .search(artist, limit: 12, country: 'US');
      songs = fallback.where((s) => _artistMatches(s, artist)).toList();
    }

    return songs;
  }

  /// Har artist ka pehla gaana, phir har artist ka doosra... (variety ke liye).
  List<Song> _roundRobin(List<List<Song>> lists) {
    final out = <Song>[];
    var i = 0;
    var added = true;

    while (added) {
      added = false;
      for (final l in lists) {
        if (i < l.length) {
          out.add(l[i]);
          added = true;
        }
      }
      i++;
    }
    return out;
  }

  Future<List<Song>> _sideSongs(List<String> artists) async {
    final lists = await Future.wait<List<Song>>([
      for (var i = 0; i < artists.length; i++)
        _artistSongs(artists[i], allowFallback: i < 5),
    ]);

    return mergeUnique(_roundRobin(lists));
  }

  /// Naye gaane (har refresh par alag artists). Backend na ho to Top 50 ko
  /// phent kar (shuffle) dikhata hai taake kam az kam har baar alag order aaye.
  Future<List<Song>> fetchFresh() async {
    if (ApiClient.instance.enabled) {
      try {
        return await ApiClient.instance.songs('/home/fresh');
      } on ApiException catch (e) {
        debugPrint('Backend fresh failed: ${e.message}');
        if (!ApiClient.directFallback) return [];
      }
    }

    final list = await _buildTop50Direct();
    list.shuffle();
    return list.take(30).toList();
  }

  /// Top 50: pehle Python backend, wo na chale to seedha tareeqa.
  Future<List<Song>> buildTop50() async {
    if (ApiClient.instance.enabled) {
      try {
        return await ApiClient.instance.songs('/top50');
      } on ApiException catch (e) {
        debugPrint('Backend top50 failed: ${e.message}');
        if (!ApiClient.directFallback) return [];
      }
    }
    return _buildTop50Direct();
  }

  /// Top 50: ek Bollywood, ek Pakistani, ek Bollywood...
  Future<List<Song>> _buildTop50Direct() async {
    final sides = await Future.wait<List<Song>>([
      _sideSongs(bollywoodArtists),
      _sideSongs(pakistaniArtists),
    ]);

    final bollywood = sides[0];
    final pakistani = sides[1];

    final output = <Song>[];
    final seenTitles = <String>{};

    void addSong(Song song) {
      if (output.length >= 50) return;

      final title = song.title.trim().toLowerCase();
      if (title.isEmpty || song.audioUrl.trim().isEmpty) return;
      if (_blockedWords.any(title.contains)) return;
      if (!seenTitles.add(title)) return;

      output.add(song);
    }

    final maxLength =
        bollywood.length > pakistani.length ? bollywood.length : pakistani.length;

    for (var i = 0; i < maxLength; i++) {
      if (i < bollywood.length) addSong(bollywood[i]);
      if (i < pakistani.length) addSong(pakistani[i]);
    }

    return output;
  }

  /// Search: pehle Python backend, wo na chale to seedha tareeqa.
  Future<List<Song>> searchPlayable(String q) async {
    if (ApiClient.instance.enabled) {
      try {
        return await ApiClient.instance.songs('/search', {'q': q});
      } on ApiException catch (e) {
        debugPrint('Backend search failed: ${e.message}');
        if (!ApiClient.directFallback) rethrow;
      }
    }
    return _searchDirect(q);
  }

  String _normalizeText(String v) => v
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Audius ke liye sakht shart: kam az kam 2 lafz aur sab gaane ke naam / artist mein.
  /// ("songs" jaise aam lafz par ajeeb gaane nahi aate.)
  bool _isRelevant(Song s, String q) {
    final tokens =
        _normalizeText(q).split(' ').where((t) => t.length > 1).toList();
    if (tokens.length < 2) {
      return _normalizeText(s.title) == _normalizeText(q);
    }

    final hay = _normalizeText('${s.title} ${s.artist}');
    return tokens.every(hay.contains);
  }

  /// Search: sabse pehle Audius (POORE gaane), phir iTunes (India + US) aur
  /// Deezer ke 30 second ke preview.
  Future<List<Song>> _searchDirect(String q) async {
    final itunes = ItunesService.instance;

    Future<List<Song>> audiusFull() async {
      try {
        final r = await AudiusService.instance.search(q, limit: 20);
        return r.where((s) => _isRelevant(s, q)).toList();
      } catch (e) {
        debugPrint('Audius search failed: $e');
        return <Song>[];
      }
    }

    final res = await Future.wait<List<Song>>([
      audiusFull(),
      itunes.search(q, limit: 15, country: 'IN'),
      itunes.search(q, limit: 15, country: 'US'),
    ]);

    var songs = mergeUnique([...res[0], ...res[1], ...res[2]]);

    if (songs.length < 5) {
      final extra = await DeezerService.instance.search(q, limit: 20);
      songs = mergeUnique([...songs, ...extra]);
    }

    return songs;
  }
}