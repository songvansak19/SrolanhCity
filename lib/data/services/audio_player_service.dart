import 'package:flutter/foundation.dart';

import 'audio_player_service_io.dart'
    if (dart.library.js_interop) 'audio_player_service_web.dart'
    as impl;

/// Lightweight injectable audio memo playback service.
///
/// Plays offline `data:audio/...` memos natively on Web (`HTMLAudioElement`)
/// without requiring extra third-party audio plugins.
abstract class AudioPlayerService {
  bool get isPlaybackSupported;

  Future<bool> play(String source, {VoidCallback? onCompleted});

  Future<void> stop();

  Future<void> dispose();

  static AudioPlayerService createDefault() => impl.createPlatformAudioPlayer();
}
