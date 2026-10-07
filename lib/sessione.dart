import 'package:flutter/widgets.dart';

import 'api/api_client.dart';
import 'api/models.dart';

enum StatoSessione { avvio, anonimo, autenticato }

class Sessione extends ChangeNotifier {
  Sessione(this.api) {
    api.onSessioneScaduta = () {
      _utente = null;
      _stato = StatoSessione.anonimo;
      avviso = 'Sessione scaduta: effettua di nuovo l\'accesso.';
      notifyListeners();
    };
  }

  final SecurlinkApi api;

  StatoSessione _stato = StatoSessione.avvio;
  Utente? _utente;

  /// One-off message for the login screen (e.g. why the user was logged out).
  String? avviso;

  StatoSessione get stato => _stato;
  Utente? get utente => _utente;

  Future<void> avvia() async {
    await api.init();
    if (!api.haSessione) {
      _stato = StatoSessione.anonimo;
    } else {
      // Show the saved profile straight away (works offline too), then
      // refresh it in the background.
      _utente = await api.utenteSalvato();
      _stato = StatoSessione.autenticato;
      aggiornaUtente();
    }
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    await api.login(username, password);
    try {
      _utente = await api.me();
    } on ApiException {
      await api.logout();
      rethrow;
    }
    avviso = null;
    _stato = StatoSessione.autenticato;
    notifyListeners();
  }

  Future<void> aggiornaUtente() async {
    try {
      _utente = await api.me();
      notifyListeners();
    } on SessioneScadutaException {
      // Handled by onSessioneScaduta.
    } on ApiException {
      // Offline: keep the saved profile.
    }
  }

  Future<void> logout() async {
    await api.logout();
    _utente = null;
    _stato = StatoSessione.anonimo;
    notifyListeners();
  }
}

class SessioneScope extends InheritedNotifier<Sessione> {
  const SessioneScope({
    super.key,
    required Sessione sessione,
    required super.child,
  }) : super(notifier: sessione);

  static Sessione of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SessioneScope>()!.notifier!;

  static Sessione read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessioneScope>()!.notifier!;
}
