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
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class SessioneScadutaException extends ApiException {
  SessioneScadutaException() : super('Sessione scaduta: effettua di nuovo l\'accesso.');
}

/// Client for the Securlink REST API.
///
/// Login uses the site's jwt-auth plugin: `POST /token` with credentials
/// returns a 1-day access token plus a 30-day `refresh_token` cookie. When
/// the access token expires, `POST /token` with that cookie issues a new one
/// without asking for the password again.
class SecurlinkApi {
  SecurlinkApi({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ?? const FlutterSecureStorage(),
        _http = client ?? http.Client();

  static const _kToken = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUtente = 'utente';
  // jwt-auth keeps one refresh token per "device": this app uses its own slot,
  // so logging in here never invalidates other sessions of the same user.
  static const _device = 'securlink-preposto-app';
  static const _timeoutBreve = Duration(seconds: 30);
  static const _timeoutLungo = Duration(minutes: 3);

  final FlutterSecureStorage _storage;
  final http.Client _http;

  String? _token;
  String? _refresh;
  String _userAgent = 'SecurlinkPreposto/$kAppVersion';

  void Function()? onSessioneScaduta;

  bool get haSessione => _token != null || _refresh != null;

  Future<void> init() async {
    _token = await _storage.read(key: _kToken);
    _refresh = await _storage.read(key: _kRefresh);
    _userAgent = await _costruisciUserAgent();
  }

  Future<Utente?> utenteSalvato() async {
    final json = await _storage.read(key: _kUtente);
    return json == null ? null : Utente.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  // ------------------------------------------------------------------ auth

  Future<void> login(String username, String password) async {
    final res = await _esegui(() => _http.post(
          _uri('/wp-json/jwt-auth/v1/token'),
          headers: _headersBase(),
          body: {'username': username, 'password': password, 'device': _device},
        ));
    final json = _decodifica(res);
    final token = tokenDaRisposta(json);
    if (res.statusCode != 200 || json['success'] != true || token == null) {
      throw ApiException(messaggioLoginFallito(json));
    }
    _token = token;
    _refresh = estraiRefreshToken(res.headers['set-cookie']) ?? _refresh;
    await _salvaToken();
  }

  Future<void> logout() async {
    _token = null;
    _refresh = null;
    await _storage.deleteAll();
  }

  /// Extends the 30-day refresh token while the app is in use.
  Future<void> ruotaRefreshToken() async {
    if (_refresh == null) return;
    try {
      final res = await _http
          .post(_uri('/wp-json/jwt-auth/v1/token/refresh'),
              headers: {..._headersBase(), 'Cookie': 'refresh_token=$_refresh'}, body: {'device': _device})
          .timeout(_timeoutBreve);
      final nuovo = estraiRefreshToken(res.headers['set-cookie']);
      if (res.statusCode == 200 && nuovo != null) {
        _refresh = nuovo;
        await _salvaToken();
      }
    } on Exception {
      // Best effort: the current refresh token stays valid until it expires.
    }
  }

  Future<bool> _rinnovaToken() async {
    if (_refresh == null) return false;
    final res = await _esegui(() => _http.post(
          _uri('/wp-json/jwt-auth/v1/token'),
          headers: {..._headersBase(), 'Cookie': 'refresh_token=$_refresh'},
          body: {'device': _device},
        ));
    final token = tokenDaRisposta(_decodifica(res));
    if (res.statusCode != 200 || token == null) return false;
    _token = token;
    await _salvaToken();
    return true;
  }

  // ------------------------------------------------------------ endpoints

  Future<Utente> me() async {
    final json = await _getJson('/wp-json/securlink/v1/preposto/me');
    await _storage.write(key: _kUtente, value: jsonEncode(json));
    return Utente.fromJson(json);
  }

  Future<void> cambiaPassword({required String attuale, required String nuova}) async {
    final res = await _autenticata((headers) => _http.post(
          _uri('/wp-json/securlink/v1/preposto/password'),
          headers: headers,
          body: {'password_attuale': attuale, 'nuova_password': nuova},
        ));
    _verificaOk(res);
  }

  Future<ElenchiVoci> voci() async {
    return ElenchiVoci.fromJson(await _getJson('/wp-json/securlink/v1/preposto/voci'));
  }

  /// Creates an entry (or returns the existing one with the same name) and
  /// the refreshed list.
  Future<({String valore, List<String> voci})> aggiungiVoce(TipoVoce tipo, String valore) async {
    final res = await _autenticata((headers) => _http.post(
          _uri('/wp-json/securlink/v1/preposto/voci'),
          headers: headers,
          body: {'tipo': tipo.valoreApi, 'valore': valore},
        ));
    final json = _jsonOk(res);
    return (valore: json['valore'] as String, voci: List<String>.from(json['voci'] as List));
  }

  /// Removes an entry from the family's list (any user of the group can).
  /// Already certified evidences keep their text. Returns the updated list.
  Future<List<String>> eliminaVoce(TipoVoce tipo, String valore) async {
    final res = await _autenticata((headers) => _http.post(
          _uri('/wp-json/securlink/v1/preposto/voci/elimina'),
          headers: headers,
          body: {'tipo': tipo.valoreApi, 'valore': valore},
        ));
    return List<String>.from(_jsonOk(res)['voci'] as List);
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
      final req = http.MultipartRequest('POST', _uri('/wp-json/securlink/v1/preposto/certifica'))
        ..headers.addAll(headers)
        ..fields.addAll({
          'esito_conformita': segnalazione.conformita.valoreApi,
          'area': segnalazione.area,
          if (segnalazione.nonConformita != null) 'non_conformita': segnalazione.nonConformita!,
          'descrizione': descrizione,
          'gps_lat': '$lat',
          'gps_lon': '$lon',
          'gps_accuratezza': '$accuratezza',
        })
        ..files.add(await http.MultipartFile.fromPath('foto', file.path));
      return http.Response.fromStream(await _http.send(req));
    }, timeout: _timeoutLungo);
    return EsitoCertificazione.fromJson(_jsonOk(res));
  }

  Future<PaginaEvidenze> evidenze({String cerca = '', Conformita? conformita, int pagina = 1}) async {
    final json = await _getJson('/wp-json/securlink/v1/preposto/evidenze', query: {
      's': cerca,
      if (conformita != null) 'esito': conformita.valoreApi,
      'page': '$pagina',
      'per_page': '20',
    });
    return PaginaEvidenze.fromJson(json);
  }

  Future<EsitoVerifica> verifica(int evidenzaId) async {
    final res = await _autenticata((headers) =>
        _http.post(_uri('/wp-json/securlink/v1/preposto/evidenze/$evidenzaId/verifica'), headers: headers));
    return EsitoVerifica.fromJson(_jsonOk(res));
  }

  /// Original photo/video, cached: it never changes once certified.
  Future<File> fileOriginale(Evidenza evidenza) async {
    final dir = await getApplicationCacheDirectory();
    final file = File('${dir.path}/originali/${evidenza.id}-${nomeFileSicuro(evidenza.nomeFile)}');
    if (await file.exists()) return file;
    final res = await _autenticata(
      (headers) => _http.get(_uri('/wp-json/securlink/v1/preposto/evidenze/${evidenza.id}/file'), headers: headers),
      timeout: _timeoutLungo,
    );
    _verificaOk(res);
    await file.parent.create(recursive: true);
    return file.writeAsBytes(res.bodyBytes, flush: true);
  }

  Future<File> esporta(Evidenza evidenza, FormatoReport formato) async {
    final res = await _autenticata(
      (headers) => _http.get(
        _uri('/wp-json/securlink/v1/preposto/evidenze/${evidenza.id}/export/${formato.name}'),
        headers: headers,
      ),
      timeout: _timeoutLungo,
    );
    _verificaOk(res);
    final nome = nomeDaContentDisposition(res.headers['content-disposition']) ??
        '${nomeFileSicuro(evidenza.codice)}.${formato.name}';
    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/Report');
    await dir.create(recursive: true);
    return File('${dir.path}/$nome').writeAsBytes(res.bodyBytes, flush: true);
  }

  // -------------------------------------------------------------- plumbing

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(kBaseUrl).replace(path: path, queryParameters: query);

  Map<String, String> _headersBase() => {'Accept': 'application/json', 'User-Agent': _userAgent};

  Future<Map<String, dynamic>> _getJson(String path, {Map<String, String>? query}) async {
    final res = await _autenticata((headers) => _http.get(_uri(path, query), headers: headers));
    return _jsonOk(res);
  }

  Future<http.Response> _autenticata(
    Future<http.Response> Function(Map<String, String> headers) richiesta, {
    Duration timeout = _timeoutBreve,
  }) async {
    Map<String, String> headers() => {..._headersBase(), if (_token != null) 'Authorization': 'Bearer $_token'};

    if (_token == null && !await _rinnovaToken()) throw _sessioneScaduta();
    var res = await _esegui(() => richiesta(headers()), timeout: timeout);
    if (_tokenNonValido(res)) {
      if (!await _rinnovaToken()) throw _sessioneScaduta();
      res = await _esegui(() => richiesta(headers()), timeout: timeout);
      if (_tokenNonValido(res)) throw _sessioneScaduta();
    }
    return res;
  }

  bool _tokenNonValido(http.Response res) {
    if (res.statusCode == 401) return true;
    if (res.statusCode != 403) return false;
    // A 403 from our own endpoints ("riservata ai preposti") is final; only
    // jwt-auth's 403s mean the token itself is invalid or expired.
    final codice = _decodifica(res)['code'];
    return codice is String && codice.startsWith('jwt_auth');
  }

  SessioneScadutaException _sessioneScaduta() {
    logout();
    onSessioneScaduta?.call();
    return SessioneScadutaException();
  }

  Future<http.Response> _esegui(Future<http.Response> Function() richiesta,
      {Duration timeout = _timeoutBreve}) async {
    try {
      return await richiesta().timeout(timeout);
    } on SocketException {
      throw ApiException('Nessuna connessione a Internet. Controlla la rete e riprova.');
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
    // 5xx bodies are WordPress's generic HTML "critical error" page: useless to the user.
    if (res.statusCode >= 500) {
      throw ApiException('Errore interno del server (${res.statusCode}). Riprova tra poco; se si ripete contatta Securlav.');
    }
    throw ApiException(_messaggio(_decodifica(res)) ?? 'Errore del server (${res.statusCode}).');
  }

  String? _messaggio(Map<String, dynamic> json) {
    final msg = json['message'];
    return msg is String && msg.isNotEmpty ? msg : null;
  }

  Future<void> _salvaToken() async {
    if (_token != null) await _storage.write(key: _kToken, value: _token);
    if (_refresh != null) await _storage.write(key: _kRefresh, value: _refresh);
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

/// jwt-auth sends `data` as an object on success but as an empty list on errors.
String? tokenDaRisposta(Map<String, dynamic> json) {
  final data = json['data'];
  return data is Map ? data['token'] as String? : null;
}

String messaggioLoginFallito(Map<String, dynamic> json) {
  const credenzialiErrate = {'incorrect_password', 'invalid_username', 'invalid_email', 'empty_username', 'empty_password'};
  if (credenzialiErrate.contains(json['code'])) return 'Nome utente o password non corretti.';
  final msg = json['message'];
  if (msg is String && msg.isNotEmpty) {
    // WordPress messages may carry HTML (links, <strong>) and an "ERRORE:" prefix.
    return msg.replaceAll(RegExp(r'<[^>]*>'), '').replaceFirst(RegExp(r'^\s*ERRORE:\s*', caseSensitive: false), '').trim();
  }
  return 'Accesso non riuscito.';
}

String? estraiRefreshToken(String? setCookie) {
  if (setCookie == null) return null;
  final match = RegExp(r'refresh_token=([^;,\s]+)').firstMatch(setCookie);
  final valore = match?.group(1);
  return valore == null || valore == 'deleted' ? null : Uri.decodeComponent(valore);
}

String? nomeDaContentDisposition(String? header) {
  if (header == null) return null;
  final match = RegExp(r'filename="?([^";]+)"?', caseSensitive: false).firstMatch(header);
  final nome = match?.group(1)?.trim();
  return nome == null || nome.isEmpty ? null : nomeFileSicuro(nome);
}

String nomeFileSicuro(String nome) => nome.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
