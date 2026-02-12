import 'package:audioplayers/audioplayers.dart';

class SfxService {
  static final SfxService _instance = SfxService._();
  factory SfxService() => _instance;
  SfxService._();

  final List<AudioPlayer> _players =
      List.generate(6, (_) => AudioPlayer());
  int _cursor = 0;
  double _volume = 0.7;

  static const Map<String, String> _assetMap = {
    'card': 'sfx/card_play.wav',
    'my_turn': 'sfx/my_turn.wav',
    'small_tichu': 'sfx/small_tichu.wav',
    'large_tichu': 'sfx/large_tichu.wav',
    'dragon': 'sfx/dragon.wav',
    'dog': 'sfx/dog.wav',
    'bird': 'sfx/bird.wav',
    'countdown_tick': 'sfx/countdown_tick.wav',
    'round_end': 'sfx/round_end.wav',
    'victory': 'sfx/victory.wav',
    'defeat': 'sfx/defeat.wav',
    'chat': 'sfx/chat.wav',
  };

  double get volume => _volume;

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    for (final p in _players) {
      try {
        await p.setVolume(_volume);
      } catch (_) {}
    }
  }

  Future<void> play(String key) async {
    final asset = _assetMap[key];
    if (asset == null || _volume <= 0) return;

    final player = _players[_cursor++ % _players.length];
    try {
      await player.setVolume(_volume);
      await player.play(AssetSource(asset));
    } catch (_) {
      // ignore missing assets or playback errors
    }
  }
}
