import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Which voice recognition engine is active during citizen voice reporting.
enum VoiceCaptureMode { backendAudio, deviceSpeech, demoFallback }

/// Resolved device speech locale plus whether the requested language pack
/// (e.g., `km_KH` vs `en_US`) is actually installed on the device.
class VoiceLocaleResolution {
  const VoiceLocaleResolution({
    required this.localeId,
    required this.exactLanguageAvailable,
  });

  final String? localeId;
  final bool exactLanguageAvailable;
}

/// Injectable on-device speech-to-text contract so [ReportWizardViewModel]
/// stays decoupled from platform channels and 100% unit-testable.
abstract class VoiceInputService {
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  });

  Future<VoiceLocaleResolution> resolveLocale({required bool preferEnglish});

  Future<void> startListening({
    required String? localeId,
    required void Function(String text, bool isFinal) onResult,
    required void Function(double normalizedLevel) onSoundLevel,
  });

  Future<void> stopListening();

  Future<void> cancel();
}

/// Real device microphone speech recognizer backed by `package:speech_to_text`.
class SpeechToTextVoiceInputService implements VoiceInputService {
  SpeechToTextVoiceInputService({SpeechToText? speechToText})
    : _speech = speechToText ?? SpeechToText();

  final SpeechToText _speech;
  bool _initialized = false;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  }) async {
    try {
      final available = await _speech
          .initialize(
            onStatus: onStatus,
            onError: (err) => onError(err.errorMsg),
            finalTimeout: const Duration(seconds: 4),
          )
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      _initialized = available;
      return available;
    } catch (_) {
      _initialized = false;
      return false;
    }
  }

  @override
  Future<VoiceLocaleResolution> resolveLocale({
    required bool preferEnglish,
  }) async {
    try {
      if (!_initialized && !_speech.isAvailable) {
        return VoiceLocaleResolution(
          localeId: preferEnglish ? 'en_US' : 'km_KH',
          exactLanguageAvailable: false,
        );
      }
      final locales = await _speech.locales().timeout(
        const Duration(seconds: 2),
        onTimeout: () => const <LocaleName>[],
      );
      if (locales.isEmpty) {
        return VoiceLocaleResolution(
          localeId: preferEnglish ? 'en_US' : 'km_KH',
          exactLanguageAvailable: false,
        );
      }

      final preferred = preferEnglish ? 'en' : 'km';
      final exact = preferEnglish ? 'en_us' : 'km_kh';

      for (final loc in locales) {
        if (loc.localeId.toLowerCase().replaceAll('-', '_') == exact) {
          return VoiceLocaleResolution(
            localeId: loc.localeId,
            exactLanguageAvailable: true,
          );
        }
      }
      for (final loc in locales) {
        if (loc.localeId.toLowerCase().startsWith(preferred)) {
          return VoiceLocaleResolution(
            localeId: loc.localeId,
            exactLanguageAvailable: true,
          );
        }
      }
      final sys = await _speech.systemLocale();
      return VoiceLocaleResolution(
        localeId: sys?.localeId ?? locales.first.localeId,
        exactLanguageAvailable: false,
      );
    } catch (_) {
      return VoiceLocaleResolution(
        localeId: preferEnglish ? 'en_US' : 'km_KH',
        exactLanguageAvailable: false,
      );
    }
  }

  @override
  Future<void> startListening({
    required String? localeId,
    required void Function(String text, bool isFinal) onResult,
    required void Function(double normalizedLevel) onSoundLevel,
  }) async {
    await _speech.listen(
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
      onResult: (result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      onSoundLevelChange: (level) {
        final normalized = ((level + 2.0) / 12.0).clamp(0.0, 1.0);
        onSoundLevel(normalized);
      },
    );
  }

  @override
  Future<void> stopListening() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}
  }

  @override
  Future<void> cancel() async {
    try {
      if (_speech.isListening) {
        await _speech.cancel();
      }
    } catch (_) {}
  }
}
