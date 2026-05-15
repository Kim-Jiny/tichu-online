import 'package:audioplayers/audioplayers.dart';

class SfxService {
  static final SfxService _instance = SfxService._();
  factory SfxService() => _instance;
  SfxService._();

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

  // One persistent player per SFX key. Each player is preloaded once with
  // PlayerMode.lowLatency so Android keeps the source in SoundPool and iOS
  // keeps the prepared AVAudioPlayer alive — no MediaPlayer destroy/recreate
  // cycle on every play() call.
  final Map<String, AudioPlayer> _players = {};
  Future<void>? _initFuture;
  double _volume = 0.7;

  double get volume => _volume;

  Future<void> _ensureInitialized() => _initFuture ??= _init();

  Future<void> _init() async {
    // Preload all players in parallel — each is independent, and serial
    // awaits would stack up to several hundred ms before the very first
    // SFX could play.
    await Future.wait(_assetMap.entries.map((entry) async {
      final p = AudioPlayer();
      try {
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setVolume(_volume);
        await p.setSource(AssetSource(entry.value));
        _players[entry.key] = p;
      } catch (_) {
        // key stays absent — play() will silently no-op for it
      }
    }));
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    for (final p in _players.values) {
      try {
        await p.setVolume(_volume);
      } catch (_) {}
    }
  }

  Future<void> play(String key) async {
    if (_volume <= 0 || !_assetMap.containsKey(key)) return;
    await _ensureInitialized();
    final player = _players[key];
    if (player == null) return;
    try {
      await player.stop();
      await player.resume();
    } catch (_) {}
  }
}
