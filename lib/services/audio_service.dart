import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  static const String _keySoundEnabled = 'sound_enabled';
  final AudioPlayer _player = AudioPlayer();
  bool _soundEnabled = true;

  bool get isSoundEnabled => _soundEnabled;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _soundEnabled = prefs.getBool(_keySoundEnabled) ?? true;
  }

  Future<void> toggleSound(bool enable) async {
    _soundEnabled = enable;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySoundEnabled, enable);
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

