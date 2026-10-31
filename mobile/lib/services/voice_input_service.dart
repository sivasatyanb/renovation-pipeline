import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Service managing speech-to-text dictation in English (en-US).
class VoiceInputService {
  final SpeechToText? _speech;
  bool _isAvailable = false;
  bool _isInitialized = false;
  bool _isListening = false;
  String _currentTranscript = '';

  VoiceInputService({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;
  String get currentTranscript => _currentTranscript;

  /// Initializes the speech recognition engine.
  /// Returns false if microphone or speech engine is unavailable.
  Future<bool> initialize() async {
    if (_isInitialized) return _isAvailable;
    if (_speech == null) {
      _isAvailable = false;
      _isInitialized = true;
      return false;
    }

    try {
      _isAvailable = await _speech.initialize(
        onError: (val) {
          debugPrint('Speech recognition error: ${val.errorMsg}');
          _isListening = false;
        },
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            _isListening = false;
          }
        },
      );
    } catch (e) {
      debugPrint('Speech recognition init failed: $e');
      _isAvailable = false;
    }
    _isInitialized = true;
    return _isAvailable;
  }

  /// Start dictating in en-US.
  Future<bool> startListening({
    required void Function(String text) onResult,
    void Function(String finalTranscript)? onDone,
  }) async {
    final available = await initialize();
    if (!available || _speech == null) {
      return false;
    }

    _currentTranscript = '';
    _isListening = true;

    try {
      await _speech.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'en_US',
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          _currentTranscript = result.recognizedWords;
          onResult(result.recognizedWords);
          if (result.finalResult && onDone != null) {
            onDone(result.recognizedWords);
          }
        },
      );
      return true;
    } catch (e) {
      debugPrint('Speech listen failed: $e');
      _isListening = false;
      return false;
    }
  }

  /// Stop dictation and trigger [onStopped] with the captured transcript.
  Future<void> stopListening({
    void Function(String transcript)? onStopped,
  }) async {
    if (!_isListening) return;
    _isListening = false;
    try {
      if (_speech != null) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint('Speech stop failed: $e');
    }
    if (onStopped != null) {
      onStopped(_currentTranscript);
    }
  }

  Future<void> cancel() async {
    _isListening = false;
    try {
      if (_speech != null) {
        await _speech.cancel();
      }
    } catch (_) {}
  }
}
