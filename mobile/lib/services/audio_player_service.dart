import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Small interface for audio playback so tests can substitute a fake player.
abstract class CallAudioPlayer {
  Future<void> playUrl(String url);
  Future<void> stop();
  Future<void> dispose();
}

/// Default implementation using `package:audioplayers/audioplayers.dart`.
class AudioplayersCallAudioPlayer implements CallAudioPlayer {
  final AudioPlayer _player;

  AudioplayersCallAudioPlayer({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  @override
  Future<void> playUrl(String url) async {
    try {
      await _player.stop();
      final completionFuture = _player.onPlayerComplete.first;
      await _player.play(UrlSource(url));
      await completionFuture.timeout(const Duration(seconds: 30));
    } catch (e) {
      debugPrint('CallAudioPlayer playback error for $url: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('CallAudioPlayer stop error: $e');
    }
  }

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (e) {
      debugPrint('CallAudioPlayer dispose error: $e');
    }
  }
}
