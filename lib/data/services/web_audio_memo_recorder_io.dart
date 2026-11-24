import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'file_helper.dart';

/// Native mobile/desktop audio memo recorder backed by `package:record`.
class PlatformAudioMemoRecorder {
  AudioRecorder? _recorder;
  String? _currentPath;

  AudioRecorder _ensureRecorder() => _recorder ??= AudioRecorder();

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

  Future<bool> start({required bool persistentMemo}) async {
    try {
      final permitted = await hasPermission();
      if (!permitted) return false;

      if (persistentMemo) {
        final docsDir = await getApplicationDocumentsDirectory();
        final audioDir = Directory('${docsDir.path}/report_audio');
        if (!audioDir.existsSync()) {
          await audioDir.create(recursive: true);
        }
        final path =
            '${audioDir.path}/memo_${DateTime.now().microsecondsSinceEpoch}.m4a';
        _currentPath = path;
        try {
          await _ensureRecorder().start(
            const RecordConfig(
              encoder: AudioEncoder.aacLc,
              bitRate: 32000,
              sampleRate: 16000,
              numChannels: 1,
            ),
            path: path,
          );
          return true;
        } catch (_) {
          // Fallback to universal 16 kHz mono WAV if AAC is unavailable.
          final wavPath = path.replaceAll('.m4a', '.wav');
          _currentPath = wavPath;
          await _ensureRecorder().start(
            const RecordConfig(
              encoder: AudioEncoder.wav,
              sampleRate: 16000,
              numChannels: 1,
            ),
            path: wavPath,
          );
          return true;
        }
      }

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
      await deleteLocalFile(_currentPath);
      _currentPath = null;
      return false;
    }
  }

  Future<double> getNormalizedAmplitude() async {
    final rec = _recorder;
    if (rec == null) return 0.0;
    try {
      final amp = await rec.getAmplitude();
      final db = amp.current;
      if (!db.isFinite || db <= -55.0) return 0.0;
      return ((db + 55.0) / 55.0).clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  Future<String?> stop() async {
    final rec = _recorder;
    if (rec == null) return null;
    try {
      final path = await rec.stop();
      final resolved = (path != null && path.isNotEmpty) ? path : _currentPath;
      _currentPath = null;
      return resolved;
    } catch (_) {
      await deleteLocalFile(_currentPath);
      _currentPath = null;
      return null;
    }
  }

  Future<void> cancelAndDelete() async {
    final rec = _recorder;
    final path = _currentPath;
    _currentPath = null;
    try {
      if (rec != null && await rec.isRecording()) {
        await rec.cancel();
      }
    } catch (_) {}
    await deleteLocalFile(path);
  }

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
