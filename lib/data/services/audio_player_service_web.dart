import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'audio_player_service.dart';

class _WebAudioPlayerService implements AudioPlayerService {
  web.HTMLAudioElement? _audio;

  @override
  bool get isPlaybackSupported => true;

  @override
  Future<bool> play(String source, {VoidCallback? onCompleted}) async {
    await stop();
    if (source.isEmpty) return false;
    try {
      final audio = web.HTMLAudioElement()..src = source;
      audio.onended = (web.Event _) {
        if (identical(_audio, audio)) {
          _audio = null;
        }
        onCompleted?.call();
      }.toJS;
      audio.onerror = (web.Event _) {
        if (identical(_audio, audio)) {
          _audio = null;
        }
        onCompleted?.call();
      }.toJS;
      _audio = audio;
      await audio.play().toDart;
      return true;
    } catch (_) {
      _audio = null;
      return false;
    }
  }

  @override
  Future<void> stop() async {
    final current = _audio;
    _audio = null;
    if (current != null) {
      try {
        current.pause();
        current.currentTime = 0;
      } catch (_) {}
    }
  }

  @override
  Future<void> dispose() => stop();
}

AudioPlayerService createPlatformAudioPlayer() => _WebAudioPlayerService();
