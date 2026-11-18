import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.dettagli = const []});
  final String message;

  /// Every validation message, when the server sent several (e.g. one per
  /// question of a check). `message` is the first one.
  final List<String> dettagli;

  @override
  String toString() => message;
}

class SessioneScadutaException extends ApiException {
  SessioneScadutaException()
    : super('Sessione scaduta: effettua di nuovo l\'accesso.');
}

/// Client for the Securlink 2.0 REST API (`/api/v1/preposto/*`).
///
/// Login: `POST /preposto/accesso` with email and password returns a Sanctum
/// token, sent as `Authorization: Bearer`. The token does not expire by time:
/// it stops working when the password is changed (from this app too: the
/// response carries the new token) or when the account is blocked. In that
/// case the server answers 401 and the user logs in again.
class SecurlinkApi {
  SecurlinkApi({FlutterSecureStorage? storage, http.Client? client})
    : _storage = storage ?? const FlutterSecureStorage(),
      _http = client ?? http.Client();

  static const _kToken = 'access_token';
  static const _kUtente = 'utente';
  static const _timeoutBreve = Duration(seconds: 30);
  static const _timeoutLungo = Duration(minutes: 3);
  static const _base = '/api/v1/preposto';

  final FlutterSecureStorage _storage;
  final http.Client _http;

  String? _token;
  String _userAgent = 'SecurlinkPreposto/$kAppVersion';
  String _dispositivo = 'app';

  void Function()? onSessioneScaduta;

  /// Called when the server says a plugin is no longer active for the family
  /// (403 with `codice` `*_non_attivo`): the session reloads the profile so
  /// the app hides that plugin's functions.
  void Function()? onPluginCambiati;

  bool get haSessione => _token != null;

  Future<void> init() async {
    _token = await _storage.read(key: _kToken);
    _userAgent = await _costruisciUserAgent();
    _dispositivo = _userAgent.length > 100
        ? _userAgent.substring(0, 100)
        : _userAgent;
  }

  Future<Utente?> utenteSalvato() async {
    final json = await _storage.read(key: _kUtente);
    return json == null
        ? null
        : Utente.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  // ------------------------------------------------------------------ auth

  Future<void> login(String email, String password) async {
    final res = await _esegui(
      () => _http.post(
        _uri('$_base/accesso'),
        headers: _headersJson(),
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
          'dispositivo': _dispositivo,
        }),
      ),
    );
    final json = _decodifica(res);
    final token = tokenDaRisposta(json);
    if (res.statusCode != 200 || token == null) {
      throw ApiException(messaggioLoginFallito(json));
    }
    _token = token;
    await _salvaToken();
  }

  Future<void> logout() async {
    final token = _token;
    _token = null;
    await _storage.deleteAll();
    if (token == null) return;
    // Best effort: the server revokes this device's token.
    try {
      await _http
          .post(
            _uri('$_base/uscita'),
            headers: {..._headersBase(), 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
    } on Exception {
      // Offline: the token stays valid on the server until the next password change.
    }
  }

  // ------------------------------------------------------------ endpoints

  Future<Utente> me() async {
    final json = _dati(await _getJson('$_base/me'));
    await _storage.write(key: _kUtente, value: jsonEncode(json));
    return Utente.fromJson(json);
  }

  /// Changes the password. The server revokes every token (other devices must
  /// log in again) and returns a new one for this device.
  Future<void> cambiaPassword({
    required String attuale,
    required String nuova,
  }) async {
    final res = await _autenticata(
      (headers) => _http.post(
        _uri('$_base/password'),
        headers: headers,
        body: jsonEncode({
          'password_attuale': attuale,
          'nuova_password': nuova,
        }),
      ),
    );
    final nuovoToken = _jsonOk(res)['token'];
    if (nuovoToken is String && nuovoToken.isNotEmpty) {
      _token = nuovoToken;
      await _salvaToken();
    }
  }

  Future<ElenchiVoci> voci() async {
    return ElenchiVoci.fromJson(_dati(await _getJson('$_base/voci')));
  }

  /// Creates an entry (or returns the existing one with the same name) and
  /// the refreshed list.
  Future<({String valore, List<String> voci})> aggiungiVoce(
    TipoVoce tipo,
    String valore,
  ) async {
    final res = await _autenticata(
      (headers) => _http.post(
        _uri('$_base/voci'),
        headers: headers,
        body: jsonEncode({'tipo': tipo.valoreApi, 'valore': valore}),
      ),
    );
    final dati = _dati(_jsonOk(res));
    return (
      valore: (dati['voce'] as Map)['nome'] as String,
      voci: nomiVoci(dati['voci']),
    );
  }

  /// Removes an entry from the family's list (any user of the group can).
  /// Already certified evidences keep their text. Returns the updated list.
  Future<List<String>> eliminaVoce(TipoVoce tipo, String valore) async {
    // The server deletes by id: find the entry by name in the current list.
    final elenco =
        _dati(await _getJson('$_base/voci'))[tipo.valoreApi] as List? ??
        const [];
    final voce = elenco
        .cast<Map>()
        .where(
          (v) => (v['nome'] as String).toLowerCase() == valore.toLowerCase(),
        )
        .firstOrNull;
    if (voce == null) return nomiVoci(elenco);
    final res = await _autenticata(
      (headers) => _http.delete(
        _uri('$_base/voci/${tipo.valoreApi}/${voce['id']}'),
        headers: headers,
      ),
    );
    return nomiVoci(_dati(_jsonOk(res))['voci']);
  }

  Future<EsitoCertificazione> certifica({
    required File file,
    required double lat,
    required double lon,
    required double accuratezza,
    required Segnalazione segnalazione,
    required String descrizione,
  }) async {
    final res = await _autenticata((headers) async {
      final req = http.MultipartRequest('POST', _uri('$_base/certifica'))
        ..headers.addAll(headers)
        ..fields.addAll({
          'esito': segnalazione.conformita.valoreApi,
          'area': segnalazione.area,
          if (segnalazione.nonConformita != null)
            'non_conformita': segnalazione.nonConformita!,
          'descrizione': descrizione,
          'gps_lat': '$lat',
          'gps_lon': '$lon',
          'gps_accuratezza': '$accuratezza',
          'dispositivo': _dispositivo,
          'versione_app': kAppVersion,
        })
        ..files.add(await http.MultipartFile.fromPath('foto', file.path));
      return http.Response.fromStream(await _http.send(req));
    }, timeout: _timeoutLungo);
    return EsitoCertificazione.fromJson(_dati(_jsonOk(res)));
  }

  Future<PaginaEvidenze> evidenze({
    String cerca = '',
    Conformita? conformita,
    int pagina = 1,
  }) async {
    final json = await _getJson(
      '$_base/evidenze',
      query: {
        if (cerca.isNotEmpty) 's': cerca,
        if (conformita != null) 'esito': conformita.valoreApi,
        'page': '$pagina',
        'per_pagina': '20',
      },
    );
    return PaginaEvidenze.fromJson(json);
  }

  Future<EsitoVerifica> verifica(int evidenzaId) async {
    final res = await _autenticata(
      (headers) => _http.post(
        _uri('$_base/evidenze/$evidenzaId/verifica'),
        headers: headers,
      ),
    );
    return EsitoVerifica.fromJson(_dati(_jsonOk(res)));
  }

  /// Original photo/video, cached: it never changes once certified.
  Future<File> fileOriginale(Evidenza evidenza) async {
    final dir = await getApplicationCacheDirectory();
    final file = File(
      '${dir.path}/originali/${evidenza.id}-${nomeFileSicuro(evidenza.nomeFile)}',
    );
    if (await file.exists()) return file;
    final res = await _autenticata(
      (headers) => _http.get(
        _uri('$_base/evidenze/${evidenza.id}/file', {'inline': '1'}),
        headers: headers,
      ),
      timeout: _timeoutLungo,
    );
    _verificaOk(res);
    await file.parent.create(recursive: true);
    return file.writeAsBytes(res.bodyBytes, flush: true);
  }

  Future<File> esporta(Evidenza evidenza, FormatoReport formato) async {
    final res = await _autenticata(
      (headers) => _http.get(
        _uri('$_base/evidenze/${evidenza.id}/export/${formato.name}'),
        headers: headers,
      ),
      timeout: _timeoutLungo,
    );
    _verificaOk(res);
    final nome =
        nomeDaContentDisposition(res.headers['content-disposition']) ??
        '${nomeFileSicuro(evidenza.codice)}.${formato.name}';
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/Report',
    );
    await dir.create(recursive: true);
    return File('${dir.path}/$nome').writeAsBytes(res.bodyBytes, flush: true);
  }

  // ------------------------------------------------------------- SecurGest

  /// The checks of the preposto's sites (D-204): to do first, then done.
  Future<List<CheckDelGiorno>> check() async {
    final dati = _dati(await _getJson('$_base/check'));
    return [
      for (final c in dati['check'] as List? ?? const [])
        CheckDelGiorno.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<ModuloCheck> moduloCheck(int pianificazioneId) async =>
      ModuloCheck.fromJson(
        _dati(await _getJson('$_base/check/$pianificazioneId')),
      );

  /// Sends a filled check (multipart, like the certification). The position
  /// is optional: if the phone cannot give it the check goes without.
  Future<String> inviaCheck({
    required ModuloCheck modulo,
    required Map<String, RispostaDaInviare> risposte,
    double? lat,
    double? lon,
    double? accuratezza,
  }) async {
    final res = await _autenticata((headers) async {
      final req =
          http.MultipartRequest(
              'POST',
              _uri('$_base/check/${modulo.pianificazioneId}'),
            )
            ..headers.addAll(headers)
            ..fields['versione_id'] = '${modulo.versioneId}';
      if (lat != null && lon != null) {
        req.fields['gps_lat'] = '$lat';
        req.fields['gps_lon'] = '$lon';
        if (accuratezza != null) req.fields['gps_accuratezza'] = '$accuratezza';
      }
      for (final e in risposte.entries) {
        if (e.value.risposta.isNotEmpty) {
          req.fields['risposte[${e.key}][risposta]'] = e.value.risposta;
        }
        if (e.value.nota.trim().isNotEmpty) {
          req.fields['risposte[${e.key}][nota]'] = e.value.nota.trim();
        }
        for (final f in e.value.foto) {
          req.files.add(
            await http.MultipartFile.fromPath('foto[${e.key}][]', f.path),
          );
        }
      }
      return http.Response.fromStream(await _http.send(req));
    }, timeout: _timeoutLungo);
    final json = _jsonOk(res);
    return json['message'] as String? ?? 'Check inviato.';
  }

  Future<List<CheckInviato>> storicoCheck() async {
    final json = await _getJson('$_base/check/storico');
    return [
      for (final c in json['data'] as List? ?? const [])
        CheckInviato.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<DettaglioCheck> dettaglioCheck(int id) async =>
      DettaglioCheck.fromJson(
        _dati(await _getJson('$_base/check/compilati/$id')),
      );

  /// A photo of a sent check (private: it needs the token), cached.
  Future<File> fotoCheck(int id) async {
    final dir = await getApplicationCacheDirectory();
    final file = File('${dir.path}/check/$id.jpg');
    if (await file.exists()) return file;
    final res = await _autenticata(
      (headers) => _http.get(_uri('$_base/check/foto/$id'), headers: headers),
      timeout: _timeoutLungo,
    );
    _verificaOk(res);
    await file.parent.create(recursive: true);
    return file.writeAsBytes(res.bodyBytes, flush: true);
  }

  // -------------------------------------------------------------- SecurMiss

  /// The near-miss form (D-207): the preposto's sites, the causes, the choices
  /// and the last reports he sent. Same routes as the site.
  Future<DatiNearMiss> nearMiss() async =>
      DatiNearMiss.fromJson(_dati(await _getJson('$_base/near-miss')));

  /// Sends a near-miss report (multipart, up to 5 photos). The reporter is the
  /// account itself; `da=app` tells the server where it came from.
  Future<int> inviaNearMiss(NearMissDaInviare n) async {
    final res = await _autenticata((headers) async {
      final req = http.MultipartRequest('POST', _uri('$_base/near-miss'))
        ..headers.addAll(headers)
        ..fields['da'] = 'app'
        ..fields['cantiere_id'] = '${n.cantiereId}'
        ..fields['data_evento'] = n.dataEvento
        ..fields['descrizione'] = n.descrizione.trim()
        ..fields['azioni_immediate'] = n.azioniImmediate.trim();
      if (n.punto.trim().isNotEmpty) req.fields['punto'] = n.punto.trim();
      if (n.casisticaId != null) {
        req.fields['casistica_id'] = '${n.casisticaId}';
      } else {
        req.fields['causa_altro'] = n.causaAltro.trim();
      }
      // A field map cannot repeat a name: the lists go with their index.
      for (final e in n.rischi.indexed) {
        req.fields['rischi[${e.$1}]'] = e.$2;
      }
      for (final e in n.origini.indexed) {
        req.fields['origini[${e.$1}]'] = e.$2;
      }
      if (n.origini.contains('altro')) {
        req.fields['origine_altro'] = n.origineAltro.trim();
      }
      for (final f in n.foto) {
        req.files.add(await http.MultipartFile.fromPath('foto[]', f.path));
      }
      return http.Response.fromStream(await _http.send(req));
    }, timeout: _timeoutLungo);
    final json = _jsonOk(res);
    return (json['data'] as Map<String, dynamic>?)?['numero'] as int? ?? 0;
  }

  // -------------------------------------------------------------- plumbing

  /// `kBaseUrl` may carry a path (the dev server behind the Funnel lives at
  /// `https://…/securlink`): the API paths go after it. In production it has none.
  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(kBaseUrl);
    final prefisso = base.path.replaceAll(RegExp(r'/+$'), '');
    return base.replace(path: '$prefisso$path', queryParameters: query);
  }

  Map<String, String> _headersBase() => {
    'Accept': 'application/json',
    'User-Agent': _userAgent,
  };

  Map<String, String> _headersJson() => {
    ..._headersBase(),
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> _getJson(
    String path, {
    Map<String, String>? query,
  }) async {
    final res = await _autenticata(
      (headers) => _http.get(_uri(path, query), headers: headers),
    );
    return _jsonOk(res);
  }

  Future<http.Response> _autenticata(
    Future<http.Response> Function(Map<String, String> headers) richiesta, {
    Duration timeout = _timeoutBreve,
  }) async {
    if (_token == null) throw _sessioneScaduta();
    // JSON for the calls that send a body; the multipart request sets its own Content-Type.
    final res = await _esegui(
      () => richiesta({..._headersJson(), 'Authorization': 'Bearer $_token'}),
      timeout: timeout,
    );
    // 401 = token revoked (password changed elsewhere, account blocked). A 403 is final
    // and carries its own message (e.g. «funzionalità non attiva»): it is not a logout.
    if (res.statusCode == 401) throw _sessioneScaduta();
    if (res.statusCode == 403 && _pluginNonAttivo(res)) {
      onPluginCambiati?.call();
    }
    return res;
  }

  bool _pluginNonAttivo(http.Response res) {
    try {
      final codice = (jsonDecode(res.body) as Map<String, dynamic>)['codice'];
      return codice is String && codice.endsWith('_non_attivo');
    } catch (_) {
      return false;
    }
  }

  SessioneScadutaException _sessioneScaduta() {
    logout();
    onSessioneScaduta?.call();
    return SessioneScadutaException();
  }

  Future<http.Response> _esegui(
    Future<http.Response> Function() richiesta, {
    Duration timeout = _timeoutBreve,
  }) async {
    try {
      return await richiesta().timeout(timeout);
    } on SocketException {
      throw ApiException(
        'Nessuna connessione a Internet. Controlla la rete e riprova.',
      );
    } on TimeoutException {
      throw ApiException('Il server non risponde. Riprova tra poco.');
    } on http.ClientException {
      throw ApiException('Connessione interrotta. Riprova.');
    }
  }

  Map<String, dynamic> _decodifica(http.Response res) {
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      return json is Map<String, dynamic> ? json : {};
    } on FormatException {
      return {};
    }
  }

  Map<String, dynamic> _jsonOk(http.Response res) {
    _verificaOk(res);
    return _decodifica(res);
  }

  void _verificaOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    // 5xx bodies are not meant for the user.
    if (res.statusCode >= 500) {
      throw ApiException(
        'Errore interno del server (${res.statusCode}). Riprova tra poco; se si ripete contatta Securlav.',
      );
    }
    final json = _decodifica(res);
    throw ApiException(
      _messaggio(json) ?? 'Errore del server (${res.statusCode}).',
      dettagli: _tuttiIMessaggi(json),
    );
  }

  /// All the validation messages (one per field), in the server's order.
  List<String> _tuttiIMessaggi(Map<String, dynamic> json) {
    final errori = json['errors'];
    if (errori is! Map) return const [];
    return [
      for (final v in errori.values)
        if (v is List && v.isNotEmpty && v.first is String) v.first as String,
    ];
  }

  /// Laravel validation errors come as `errors: {field: [message]}`; otherwise `message`.
  String? _messaggio(Map<String, dynamic> json) {
    final errori = json['errors'];
    if (errori is Map && errori.isNotEmpty) {
      final primo = errori.values.first;
      if (primo is List && primo.isNotEmpty && primo.first is String) {
        return primo.first as String;
      }
    }
    final msg = json['message'];
    return msg is String && msg.isNotEmpty ? msg : null;
  }

  /// Responses wrap the payload in `data`.
  Map<String, dynamic> _dati(Map<String, dynamic> json) {
    final dati = json['data'];
    return dati is Map<String, dynamic> ? dati : json;
  }

  Future<void> _salvaToken() async {
    if (_token != null) await _storage.write(key: _kToken, value: _token);
  }

  /// Ends up in the evidence report as "user agent" of the capture device.
  Future<String> _costruisciUserAgent() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return 'SecurlinkPreposto/$kAppVersion (Android ${a.version.release}; ${a.manufacturer} ${a.model})';
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return 'SecurlinkPreposto/$kAppVersion (iOS ${i.systemVersion}; ${i.utsname.machine})';
      }
    } on Exception {
      // Fall back to the bare app identifier.
    }
    return 'SecurlinkPreposto/$kAppVersion';
  }
}

/// Login response: `{data: {token, utente}}`.
String? tokenDaRisposta(Map<String, dynamic> json) {
  final data = json['data'];
  return data is Map ? data['token'] as String? : null;
}

String messaggioLoginFallito(Map<String, dynamic> json) {
  final errori = json['errors'];
  if (errori is Map && errori.isNotEmpty) {
    final primo = errori.values.first;
    if (primo is List && primo.isNotEmpty && primo.first is String) {
      return primo.first as String;
    }
  }
  final msg = json['message'];
  if (msg is String && msg.isNotEmpty) {
    return msg.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }
  return 'Accesso non riuscito.';
}

String? nomeDaContentDisposition(String? header) {
  if (header == null) return null;
  final match = RegExp(
    r'filename="?([^";]+)"?',
    caseSensitive: false,
  ).firstMatch(header);
  final nome = match?.group(1)?.trim();
  return nome == null || nome.isEmpty ? null : nomeFileSicuro(nome);
}

String nomeFileSicuro(String nome) =>
    nome.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
