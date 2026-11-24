import 'dart:async';

import 'file_helper.dart';
import 'web_audio_memo_recorder.dart';

/// Injectable microphone audio recorder contract for capturing short ephemeral
/// clips for Tier 1 backend AI voice-to-text transcription (`hackathonshow.md §5`).
/// Temporary clips are always deleted immediately after transcription.
abstract class AudioRecorderService {
  Future<bool> hasPermission();

  /// Starts recording into a temporary clip for backend AI transcription.
  Future<bool> startRecording();

  /// Returns current microphone input loudness normalized to `0.0..1.0`.
  Future<double> getNormalizedAmplitude();

  /// Stops recording and returns the path/data-URI to the temporary clip.
  Future<String?> stopRecording();

  /// Cancels any active recording and deletes any temporary audio file.
  Future<void> cancelAndDelete();

  /// Deletes a recorded temporary audio file safely.
  Future<void> deleteFile(String? path);

  Future<void> dispose();
}

/// Real device microphone implementation supporting both Native (`record`) and
/// Web PWA (`MediaRecorder` + `AnalyserNode`) for ephemeral AI transcription.
class RecordAudioRecorderService implements AudioRecorderService {
  PlatformAudioMemoRecorder? _platform;

  PlatformAudioMemoRecorder _ensurePlatform() =>
      _platform ??= PlatformAudioMemoRecorder();

  @override
  Future<bool> hasPermission() => _ensurePlatform().hasPermission();

  @override
  Future<bool> startRecording() => _ensurePlatform().start();

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
