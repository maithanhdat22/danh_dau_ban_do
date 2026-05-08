import 'package:flutter_tts/flutter_tts.dart';

class SoundService {
  static final FlutterTts _tts = FlutterTts();
  static bool _ready = false;
  static DateTime _lastSpeak = DateTime.fromMillisecondsSinceEpoch(0);

  static Future<void> init() async {
    if (_ready) return;

    await _tts.setLanguage('vi-VN');
    await _tts.setSpeechRate(0.46);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _ready = true;
  }

  static Future<void> speak(String text, {int gapSeconds = 6}) async {
    final value = text.trim();
    if (value.isEmpty) return;

    await init();

    final now = DateTime.now();
    if (now.difference(_lastSpeak).inSeconds < gapSeconds) return;

    _lastSpeak = now;
    await _tts.stop();
    await _tts.speak(value);
  }

  static Future<void> speakNow(String text) async {
    final value = text.trim();
    if (value.isEmpty) return;

    await init();

    _lastSpeak = DateTime.now();
    await _tts.stop();
    await _tts.speak(value);
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
