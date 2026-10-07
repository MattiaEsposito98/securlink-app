import 'dart:async';

import 'package:geolocator/geolocator.dart';

class PosizioneException implements Exception {
  PosizioneException(this.message, {this.apriImpostazioni = false});
  final String message;
  final bool apriImpostazioni;

  @override
  String toString() => message;
}

/// GPS is mandatory for certification: every failure becomes a clear message.
Future<Position> rilevaPosizione() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw PosizioneException(
      'La localizzazione del telefono è spenta: attivala per certificare.',
    );
  }
  var permesso = await Geolocator.checkPermission();
  if (permesso == LocationPermission.denied) {
    permesso = await Geolocator.requestPermission();
  }
  if (permesso == LocationPermission.deniedForever) {
    throw PosizioneException(
      'Accesso alla posizione negato. Abilitalo nelle impostazioni dell\'app per certificare.',
      apriImpostazioni: true,
    );
  }
  if (permesso == LocationPermission.denied ||
      permesso == LocationPermission.unableToDetermine) {
    throw PosizioneException(
      'Senza posizione GPS non è possibile certificare.',
    );
  }
  try {
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  } on TimeoutException {
    throw PosizioneException(
      'Posizione non rilevata in tempo. Riprova, possibilmente all\'aperto.',
    );
  }
}

String nomeEvidenza(DateTime d, String estensione) {
  String due(int n) => n.toString().padLeft(2, '0');
  return 'evidenza-${d.year}${due(d.month)}${due(d.day)}-${due(d.hour)}${due(d.minute)}${due(d.second)}.$estensione';
}

String formattaMb(int byte) => '${(byte / 1024 / 1024).toStringAsFixed(1)} MB';

/// Longest recording that stays under [maxBytes] at the target bitrates,
/// with a safety margin because the real bitrate fluctuates.
Duration durataMassimaVideo(int maxBytes, int videoBitrate, int audioBitrate) {
  final secondi = (maxBytes * 8 * 0.85) / (videoBitrate + audioBitrate);
  return Duration(seconds: secondi.floor());
}

String formattaDurata(Duration d) {
  final m = d.inMinutes.toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}
