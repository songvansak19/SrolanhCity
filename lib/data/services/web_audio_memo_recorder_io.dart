import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'file_helper.dart';

/// Native mobile/desktop ephemeral audio recorder backed by `package:record`
/// for Tier 1 backend AI voice-to-text transcription.
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

  Future<bool> start() async {
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
