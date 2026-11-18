import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:securlink/api/api_client.dart';
import 'package:securlink/api/models.dart';
import 'package:securlink/config.dart';

/// The contract of the SecurMiss near-miss calls with the server (D-207):
/// paths, multipart field names and the plugin switch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // kBaseUrl may carry a path (the dev server behind the Funnel).
  final prefisso = Uri.parse(kBaseUrl).path.replaceAll(RegExp(r'/+$'), '');

  Future<SecurlinkApi> api(MockClient client) async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'tok'});
    final a = SecurlinkApi(client: client);
    await a.init();
    return a;
  }

  test('the form data comes from the right path and is read in full', () async {
    late http.BaseRequest visto;
    final client = MockClient((req) async {
      visto = req;
      return http.Response(
        jsonEncode({
          'data': {
            'sedi': [
              {'id': 4, 'nome': 'Cantiere Napoli', 'citta': 'Napoli'},
            ],
            'casistiche': [
              {
                'id': 9,
                'numero': 3,
                'causa': 'Scala instabile',
                'azioni_immediate': 'Discesa controllata.',
              },
            ],
            'rischi': [
              {'codice': 'persone', 'nome': 'Persone'},
            ],
            'origini': [
              {'codice': 'altro', 'nome': 'Altro'},
            ],
            'segnalatore': 'Luca Verdi',
            'oggi': '2026-11-18',
            'foto_max': 5,
            'inviate': [
              {
                'id': 1,
                'numero': 12,
                'sede': 'Cantiere Napoli',
                'data_evento': '2026-11-16',
                'causa': 'Scala instabile',
                'stato': 'in_analisi',
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final d = await (await api(client)).nearMiss();
    expect(visto.method, 'GET');
    expect(visto.url.path, '$prefisso/api/v1/preposto/near-miss');
    expect(d.sedi.single.etichetta, 'Cantiere Napoli, Napoli');
    expect(d.casistiche.single.azioniImmediate, 'Discesa controllata.');
    expect(d.segnalatore, 'Luca Verdi');
    expect(d.inviate.single.statoEtichetta, 'In analisi');
    expect(d.fotoMax, 5);
  });

  test(
    'the report is sent as multipart with the names the server expects',
    () async {
      late http.BaseRequest visto;
      late String corpo;
      final client = MockClient((req) async {
        visto = req;
        corpo = latin1.decode(req.bodyBytes);
        return http.Response(
          jsonEncode({
            'data': {'id': 5, 'numero': 12},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final foto = File('${Directory.systemTemp.path}/near-miss-prova.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final numero = await (await api(client)).inviaNearMiss(
        NearMissDaInviare(
          cantiereId: 4,
          dataEvento: '2026-11-16',
          descrizione: ' Un carico oscillava ',
          azioniImmediate: 'Fermato il sollevamento.',
          rischi: ['persone', 'ambiente'],
          origini: ['procedurale', 'altro'],
          casisticaId: 9,
          origineAltro: 'Cartelli mancanti',
          punto: 'Zona gru',
          foto: [foto],
        ),
      );
      expect(numero, 12);
      expect(visto.method, 'POST');
      expect(visto.url.path, '$prefisso/api/v1/preposto/near-miss');
      expect(visto.headers['Authorization'], 'Bearer tok');
      for (final nome in [
        'da',
        'cantiere_id',
        'data_evento',
        'descrizione',
        'azioni_immediate',
        'punto',
        'casistica_id',
        'rischi[0]',
        'rischi[1]',
        'origini[0]',
        'origini[1]',
        'origine_altro',
        'foto[]',
      ]) {
        expect(corpo, contains('name="$nome"'), reason: nome);
      }
      expect(corpo, contains('Un carico oscillava')); // trimmed
      expect(corpo, isNot(contains('causa_altro'))); // a cause from the list
    },
  );

  test(
    'a cause written by hand goes as causa_altro, without casistica_id',
    () async {
      late String corpo;
      final client = MockClient((req) async {
        corpo = latin1.decode(req.bodyBytes);
        return http.Response(
          jsonEncode({
            'data': {'numero': 1},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      await (await api(client)).inviaNearMiss(
        NearMissDaInviare(
          cantiereId: 4,
          dataEvento: '2026-11-16',
          descrizione: 'x',
          azioniImmediate: 'y',
          rischi: ['persone'],
          origini: ['procedurale'],
          causaAltro: 'Olio sul pavimento',
        ),
      );
      expect(corpo, contains('name="causa_altro"'));
      expect(corpo, contains('Olio sul pavimento'));
      expect(corpo, isNot(contains('casistica_id')));
      expect(corpo, isNot(contains('origine_altro'))); // only with «altro»
    },
  );

  test('every validation message reaches the screen', () async {
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'message': 'x',
          'errors': {
            'descrizione': [
              'Il campo descrizione dell\'evento è obbligatorio.',
            ],
            'rischi': ['Il campo potenziale rischio è obbligatorio.'],
          },
        }),
        422,
        headers: {'content-type': 'application/json'},
      ),
    );
    try {
      await (await api(client)).inviaNearMiss(
        NearMissDaInviare(
          cantiereId: 4,
          dataEvento: '2026-11-16',
          descrizione: '',
          azioniImmediate: '',
          rischi: const [],
          origini: const [],
        ),
      );
      fail('it had to be refused');
    } on ApiException catch (e) {
      expect(e.dettagli.length, 2);
      expect(e.dettagli.first, contains('descrizione'));
    }
  });

  test('the near-miss tab exists only with the SecurMiss plugin', () {
    Utente con(List<String> plugin) => Utente(
      id: 1,
      nome: 'Luca',
      email: 'l@r.test',
      ambiente: 'production',
      maxUploadMb: 50,
      plugin: plugin,
    );
    expect(con(['securmiss']).haSecurmiss, isTrue);
    expect(con(['preposto', 'securgest']).haSecurmiss, isFalse);
    expect(con(['preposto']).haCertificazione, isTrue);
  });
}
