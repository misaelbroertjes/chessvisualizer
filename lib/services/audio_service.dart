import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _soundEnabled = true;

  void toggleSound(bool enable) {
    _soundEnabled = enable;
  }

  Future<void> playMove() async {
    HapticFeedback.selectionClick();
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('audio/move.wav'));
    } catch (_) {
      // Fallback system sound if asset not loaded
      SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> playCapture() async {
    HapticFeedback.mediumImpact();
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('audio/capture.wav'));
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> playCheck() async {
    HapticFeedback.heavyImpact();
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('audio/check.wav'));
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  Future<void> playSuccess() async {
    HapticFeedback.mediumImpact();
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('audio/success.wav'));
    } catch (_) {}
  }

  Future<void> playError() async {
    HapticFeedback.vibrate();
    if (!_soundEnabled) return;
    try {
      await _player.play(AssetSource('audio/error.wav'));
    } catch (_) {}
  }
}

