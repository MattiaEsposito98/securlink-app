import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:securlink/api/api_client.dart';
import 'package:securlink/api/models.dart';
import 'package:securlink/config.dart';

/// The contract of the SecurGest check calls with the server (D-204): paths,
/// multipart field names and the way the validation errors come back.
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

  final modulo = ModuloCheck(
    pianificazioneId: 2,
    sede: 'Sede',
    modello: 'Check',
    versioneId: 7,
    sezioni: const [],
    fotoMb: 10,
    fotoPerDomanda: 5,
  );

  test(
    'the check is sent as multipart with the names the server expects',
    () async {
      late http.BaseRequest visto;
      late String corpo;
      final client = MockClient((req) async {
        visto = req;
        corpo = latin1.decode(req.bodyBytes);
        return http.Response(
          jsonEncode({'message': 'Check inviato, con 1 non conformità.'}),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final foto = File('${Directory.systemTemp.path}/check-prova.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final messaggio = await (await api(client)).inviaCheck(
        modulo: modulo,
        risposte: {
          'd_abc': RispostaDaInviare(
            risposta: 'No',
            nota: ' Scarico ',
            foto: [foto],
          ),
          'd_vuota': RispostaDaInviare(),
        },
        lat: 40.85,
        lon: 14.27,
        accuratezza: 12,
      );

      expect(messaggio, 'Check inviato, con 1 non conformità.');
      expect(visto.method, 'POST');
      expect(visto.url.path, '$prefisso/api/v1/preposto/check/2');
      expect(visto.headers['Authorization'], 'Bearer tok');
      expect(corpo, contains('name="versione_id"'));
      expect(corpo, contains('name="risposte[d_abc][risposta]"'));
      expect(corpo, contains('name="risposte[d_abc][nota]"'));
      expect(corpo, contains('Scarico'));
      expect(corpo, contains('name="foto[d_abc][]"'));
      expect(corpo, contains('name="gps_lat"'));
      expect(corpo, isNot(contains('d_vuota'))); // an empty answer is not sent
    },
  );

  test('without a position the check goes without the GPS fields', () async {
    late String corpo;
    final client = MockClient((req) async {
      corpo = latin1.decode(req.bodyBytes);
      return http.Response(
        '{"message":"ok"}',
        201,
        headers: {'content-type': 'application/json'},
      );
    });
    await (await api(client)).inviaCheck(
      modulo: modulo,
      risposte: {'d_abc': RispostaDaInviare(risposta: 'Sì')},
    );
    expect(corpo, isNot(contains('gps_lat')));
    expect(corpo, contains('risposte[d_abc][risposta]'));
  });

  test('every validation message reaches the screen', () async {
    final client = MockClient(
      (req) async => http.Response(
        jsonEncode({
          'message': 'x',
          'errors': {
            'note.d_abc': [
              'Domanda 1: risposta non conforme, scrivi una nota.',
            ],
            'foto.d_abc': [
              'Domanda 1: risposta non conforme, aggiungi una foto.',
            ],
            'risposte.d_xyz': ['Domanda 2: scegli una risposta.'],
          },
        }),
        422,
        headers: {'content-type': 'application/json'},
      ),
    );
    try {
      await (await api(client)).inviaCheck(modulo: modulo, risposte: {});
      fail('it had to be refused');
    } on ApiException catch (e) {
      expect(e.message, 'Domanda 1: risposta non conforme, scrivi una nota.');
      expect(e.dettagli.length, 3);
      expect(e.dettagli.last, 'Domanda 2: scegli una risposta.');
    }
  });

  test(
    'the list of the checks and the history come from the right paths',
    () async {
      final percorsi = <String>[];
      final client = MockClient((req) async {
        percorsi.add(req.url.path);
        final corpo = req.url.path.endsWith('storico')
            ? {'data': []}
            : {
                'data': {
                  'check': [
                    {
                      'pianificazione_id': 1,
                      'sede': {'nome': 'A'},
                      'modello': {'nome': 'M', 'domande': 3},
                      'frequenza': 'giornaliera',
                      'in_pausa': false,
                      'stato': 'da_fare',
                    },
                  ],
                  'collegato': true,
                },
              };
        return http.Response(
          jsonEncode(corpo),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final a = await api(client);
      final check = await a.check();
      await a.storicoCheck();
      expect(check.single.daFare, isTrue);
      expect(percorsi, [
        '$prefisso/api/v1/preposto/check',
        '$prefisso/api/v1/preposto/check/storico',
      ]);
    },
  );

  test('the paths of the API are built on the base address', () async {
    final percorsi = <Uri>[];
    final client = MockClient((req) async {
      percorsi.add(req.url);
      return http.Response(
        '{"data":{"check":[]}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await (await api(client)).check();
    expect(percorsi.single.path, '$prefisso/api/v1/preposto/check');
    expect(percorsi.single.host, Uri.parse(kBaseUrl).host);
  });
}
