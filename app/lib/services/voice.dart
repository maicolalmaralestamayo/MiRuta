import 'package:flutter_tts/flutter_tts.dart';

/// Voz del teléfono para anunciar el recorrido (docs/07-algoritmos.md §7.19).
class Voice {
  final FlutterTts _tts = FlutterTts();
  bool enabled;

  Voice({this.enabled = true}) {
    _tts.setLanguage('es-ES');
  }

  Future<void> say(String text) async {
    if (enabled) await _tts.speak(text);
  }

  Future<void> stop() => _tts.stop();
}
