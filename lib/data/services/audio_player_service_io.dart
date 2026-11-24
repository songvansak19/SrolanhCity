import 'package:flutter/foundation.dart';

import 'audio_player_service.dart';

class _IoAudioPlayerService implements AudioPlayerService {
  @override
  bool get isPlaybackSupported => false;

  @override
  Future<bool> play(String source, {VoidCallback? onCompleted}) async {
    return false;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

AudioPlayerService createPlatformAudioPlayer() => _IoAudioPlayerService();
