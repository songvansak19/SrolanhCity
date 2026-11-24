import 'dart:async';

import 'file_helper.dart';
import 'web_audio_memo_recorder.dart';

/// Injectable microphone audio recorder contract for capturing short citizen
/// voice reports (`hackathonshow.md §5`) — used both for backend AI audio
/// transcription and for real offline local voice memos on Web & Mobile.
abstract class AudioRecorderService {
  Future<bool> hasPermission();

  /// Starts recording into a temporary file (for AI transcription) or a
  /// persistent offline audio memo (data URI on Web / `.m4a` on Native).
  Future<bool> startRecording({bool persistentMemo = false});

  /// Returns current microphone input loudness normalized to `0.0..1.0`.
  Future<double> getNormalizedAmplitude();

  /// Stops recording and returns the path/data-URI to the recorded clip.
  Future<String?> stopRecording();

  /// Cancels any active recording and deletes any temporary audio file.
  Future<void> cancelAndDelete();

  /// Deletes a recorded audio file safely.
  Future<void> deleteFile(String? path);

  Future<void> dispose();
}

/// Real device microphone implementation supporting both Native (`record`) and
/// Web PWA (`MediaRecorder` + `AnalyserNode`).
class RecordAudioRecorderService implements AudioRecorderService {
  PlatformAudioMemoRecorder? _platform;

  PlatformAudioMemoRecorder _ensurePlatform() =>
      _platform ??= PlatformAudioMemoRecorder();

  @override
  Future<bool> hasPermission() => _ensurePlatform().hasPermission();

  @override
  Future<bool> startRecording({bool persistentMemo = false}) =>
      _ensurePlatform().start(persistentMemo: persistentMemo);

  @override
  Future<double> getNormalizedAmplitude() async {
    final p = _platform;
    if (p == null) return 0.0;
    return p.getNormalizedAmplitude();
  }

  @override
  Future<String?> stopRecording() async {
    final p = _platform;
    if (p == null) return null;
    return p.stop();
  }

  @override
  Future<void> cancelAndDelete() async {
    final p = _platform;
    if (p == null) return;
    await p.cancelAndDelete();
  }

  @override
  Future<void> deleteFile(String? path) => deleteLocalFile(path);

  @override
  Future<void> dispose() async {
    final p = _platform;
    _platform = null;
    if (p != null) {
      await p.dispose();
    }
  }
}
