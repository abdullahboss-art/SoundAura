import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:soundclock/song.dart';


class PlayerController extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  List<Song> _queue = [];
  int _index = -1;

  PlayerController() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        next();
      }
      notifyListeners();
    });
  }

  Song? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  bool get isPlaying => _player.playing;
  bool get isLoading =>
      _player.processingState == ProcessingState.loading ||
      _player.processingState == ProcessingState.buffering;
  Stream<Duration> get positionStream => _player.positionStream;
  Duration get duration => _player.duration ?? const Duration(seconds: 30);

  Future<void> playQueue(List<Song> queue, int index) async {
    _queue = queue;
    _index = index;
    await _load();
  }

  Future<void> _load() async {
    final song = current;
    if (song == null) return;
    notifyListeners();
    try {
      await _player.setUrl(song.audioUrl);
      _player.play();
    } catch (e) {
      debugPrint('Play error: $e');
    }
    notifyListeners();
  }

  Future<void> toggle() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    notifyListeners();
  }

  Future<void> next() async {
    if (_index + 1 < _queue.length) {
      _index++;
      await _load();
    } else {
      await _player.pause();
      await _player.seek(Duration.zero);
      notifyListeners();
    }
  }

  Future<void> previous() async {
    if (_index > 0) {
      _index--;
      await _load();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

/// Poori app me ek hi player
final player = PlayerController();