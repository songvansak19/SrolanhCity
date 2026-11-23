import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'file_helper.dart';

/// Injectable microphone audio recorder contract for capturing short citizen
/// voice reports (`hackathonshow.md §5`) as universally accepted 16 kHz mono WAV
/// files for Free-Tier Gemini multimodal transcription.
abstract class AudioRecorderService {
  Future<bool> hasPermission();

  /// Starts recording into a temporary `.wav` file and returns `true` on success.
  Future<bool> startRecording();

  /// Returns current microphone input loudness normalized to `0.0..1.0`.
  Future<double> getNormalizedAmplitude();

  /// Stops recording and returns the path to the recorded `.wav` file (or `null`).
  Future<String?> stopRecording();

  /// Cancels any active recording and deletes the temporary audio file.
  Future<void> cancelAndDelete();

  /// Deletes a recorded temporary audio file safely after transcription.
  Future<void> deleteFile(String? path);

  Future<void> dispose();
}

/// Real device microphone implementation backed by `package:record`.
///
/// Instantiates [AudioRecorder] lazily so constructing a ViewModel in widget
/// tests or screens that never tap the mic never touches platform channels.
class RecordAudioRecorderService implements AudioRecorderService {
  AudioRecorder? _recorder;
  String? _currentPath;

  AudioRecorder _ensureRecorder() => _recorder ??= AudioRecorder();

  @override
  Future<bool> hasPermission() async {
    try {
      return await _ensureRecorder().hasPermission().timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> startRecording() async {
    if (kIsWeb) return false;
    try {
      final permitted = await hasPermission();
      if (!permitted) return false;

      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/srolanh_voice_${DateTime.now().microsecondsSinceEpoch}.wav';
      _currentPath = path;

      await _ensureRecorder().start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      return true;
    } catch (_) {
      await deleteFile(_currentPath);
      _currentPath = null;
      return false;
    }
  }

  @override
  Future<double> getNormalizedAmplitude() async {
    final rec = _recorder;
    if (rec == null) return 0.0;
    try {
      final amp = await rec.getAmplitude();
      // dBFS typically ranges from -60 (digital silence) to 0 (clipping).
      final db = amp.current;
      if (!db.isFinite || db <= -55.0) return 0.0;
      return ((db + 55.0) / 55.0).clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  @override
  Future<String?> stopRecording() async {
    final rec = _recorder;
    if (rec == null) return null;
    try {
      final path = await rec.stop();
      final resolved = (path != null && path.isNotEmpty) ? path : _currentPath;
      _currentPath = null;
      return resolved;
    } catch (_) {
      await deleteFile(_currentPath);
      _currentPath = null;
      return null;
    }
  }

  @override
  Future<void> cancelAndDelete() async {
    final rec = _recorder;
    final path = _currentPath;
    _currentPath = null;
    try {
      if (rec != null && await rec.isRecording()) {
        await rec.cancel();
      }
    } catch (_) {}
    await deleteFile(path);
  }

  @override
  Future<void> deleteFile(String? path) => deleteLocalFile(path);

  @override
  Future<void> dispose() async {
    await cancelAndDelete();
    final rec = _recorder;
    _recorder = null;
    if (rec != null) {
      try {
        await rec.dispose();
      } catch (_) {}
    }
  }
}
