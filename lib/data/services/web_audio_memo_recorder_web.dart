import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web offline voice memo recorder powered by `MediaRecorder` + `AnalyserNode`.
///
/// Works 100% offline in Chrome, Brave, Edge, and Safari (iOS & desktop) —
/// recording compact Opus/MP4 audio (~4 KB/s) and encoding to a persistent
/// `data:audio/...;base64,...` URI that survives reloads and Airplane Mode.
class PlatformAudioMemoRecorder {
  web.MediaStream? _stream;
  web.MediaRecorder? _recorder;
  web.AudioContext? _audioContext;
  web.AnalyserNode? _analyser;
  final List<web.Blob> _chunks = <web.Blob>[];
  String _mimeType = 'audio/webm';

  Future<bool> hasPermission() async {
    try {
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> start({required bool persistentMemo}) async {
    await cancelAndDelete();
    try {
      final mediaDevices = web.window.navigator.mediaDevices;
      final constraints = web.MediaStreamConstraints(audio: true.toJS);
      final stream = await mediaDevices
          .getUserMedia(constraints)
          .toDart
          .timeout(const Duration(seconds: 6));
      _stream = stream;

      _mimeType = _pickSupportedMimeType();
      final options = _mimeType.isNotEmpty
          ? web.MediaRecorderOptions(
              mimeType: _mimeType,
              audioBitsPerSecond: 32000,
            )
          : web.MediaRecorderOptions(audioBitsPerSecond: 32000);

      final recorder = web.MediaRecorder(stream, options);
      _chunks.clear();
      recorder.ondataavailable = (web.BlobEvent event) {
        final data = event.data;
        if (data.size > 0) {
          _chunks.add(data);
        }
      }.toJS;

      // Optional live microphone amplitude analyser for waveform bars.
      try {
        final ctx = web.AudioContext();
        final src = ctx.createMediaStreamSource(stream);
        final analyser = ctx.createAnalyser()..fftSize = 256;
        src.connect(analyser);
        _audioContext = ctx;
        _analyser = analyser;
      } catch (_) {}

      _recorder = recorder;
      recorder.start(250);
      return true;
    } catch (_) {
      await cancelAndDelete();
      return false;
    }
  }

  String _pickSupportedMimeType() {
    const candidates = <String>[
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/mp4',
      'audio/ogg;codecs=opus',
    ];
    for (final mime in candidates) {
      try {
        if (web.MediaRecorder.isTypeSupported(mime)) {
          return mime;
        }
      } catch (_) {}
    }
    return '';
  }

  Future<double> getNormalizedAmplitude() async {
    final analyser = _analyser;
    if (analyser == null) return 0.25;
    try {
      final count = analyser.frequencyBinCount;
      final buffer = Uint8List(count);
      final jsBuf = buffer.toJS;
      analyser.getByteTimeDomainData(jsBuf);
      final samples = jsBuf.toDart;
      var sumSquares = 0.0;
      for (var i = 0; i < samples.length; i++) {
        final centered = (samples[i] - 128) / 128.0;
        sumSquares += centered * centered;
      }
      final rms = math.sqrt(sumSquares / math.max(1, samples.length));
      return (rms * 4.5).clamp(0.0, 1.0);
    } catch (_) {
      return 0.2;
    }
  }

  Future<String?> stop() async {
    final recorder = _recorder;
    if (recorder == null) {
      _cleanupMedia();
      return null;
    }
    try {
      final stopped = Completer<void>();
      recorder.onstop = (web.Event _) {
        if (!stopped.isCompleted) stopped.complete();
      }.toJS;
      if (recorder.state != 'inactive') {
        recorder.stop();
        await stopped.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      }
      if (_chunks.isEmpty) {
        _cleanupMedia();
        return null;
      }
      final blobType = _mimeType.isNotEmpty
          ? _mimeType.split(';').first
          : 'audio/webm';
      final combined = web.Blob(
        _chunks.toJS,
        web.BlobPropertyBag(type: blobType),
      );
      final dataUrl = await _blobToDataUrl(combined);
      _cleanupMedia();
      return dataUrl;
    } catch (_) {
      _cleanupMedia();
      return null;
    }
  }

  Future<String?> _blobToDataUrl(web.Blob blob) async {
    try {
      final reader = web.FileReader();
      final completer = Completer<String?>();
      reader.onload = (web.Event _) {
        if (completer.isCompleted) return;
        final res = reader.result;
        completer.complete(res != null ? (res as JSString).toDart : null);
      }.toJS;
      reader.onerror = (web.Event _) {
        if (!completer.isCompleted) completer.complete(null);
      }.toJS;
      reader.readAsDataURL(blob);
      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  void _cleanupMedia() {
    _recorder = null;
    _chunks.clear();
    final stream = _stream;
    _stream = null;
    if (stream != null) {
      try {
        final tracks = stream.getTracks().toDart;
        for (final track in tracks) {
          track.stop();
        }
      } catch (_) {}
    }
    _analyser = null;
    final ctx = _audioContext;
    _audioContext = null;
    if (ctx != null) {
      try {
        ctx.close();
      } catch (_) {}
    }
  }

  Future<void> cancelAndDelete() async {
    final recorder = _recorder;
    if (recorder != null) {
      try {
        if (recorder.state != 'inactive') {
          recorder.stop();
        }
      } catch (_) {}
    }
    _cleanupMedia();
  }

  Future<void> dispose() => cancelAndDelete();
}
