import 'package:flutter_test/flutter_test.dart';
import 'package:securlink/api/api_client.dart';
import 'package:securlink/api/models.dart';
import 'package:securlink/config.dart';
import 'package:securlink/utils.dart';

void main() {
  group('SecurGest checks (D-204)', () {
    test('a template is read with questions, answers and rules', () {
      final modulo = ModuloCheck.fromJson({
        'pianificazione_id': 2,
        'sede': {'nome': 'Sede Napoli'},
        'modello': {'nome': 'Controllo del mattino'},
        'versione_id': 7,
        'struttura': {
          'sezioni': [
            {
              'titolo': 'Antincendio',
              'domande': [
                {
                  'chiave': 'd_abc',
                  'testo': 'Estintori a posto?',
                  'tipo': 'scelta',
                  'obbligatoria': true,
                  'opzioni': [
                    {'testo': 'Sì', 'non_conforme': false},
                    {'testo': 'No', 'non_conforme': true},
                  ],
                  'nota': 'se_nc',
                  'foto': 'se_nc',
                },
                {
                  'chiave': 'd_note',
                  'testo': 'Note',
                  'tipo': 'testo',
                  'righe': 3,
                },
              ],
            },
          ],
        },
        'limiti': {'foto_mb': 10, 'foto_per_domanda': 5},
      });
      expect(modulo.versioneId, 7);
      expect(modulo.totaleDomande, 2);
      final d = modulo.sezioni.first.domande.first;
      expect(d.opzioni.map((o) => o.nonConforme), [false, true]);
      expect(modulo.sezioni.first.domande.last.righe, 3);
    });

    test(
      'note and photo are required only when the answer is non-conforming',
      () {
        expect(DomandaCheck.serve('no', true), 'no');
        expect(DomandaCheck.serve('se_nc', false), 'no');
        expect(DomandaCheck.serve('se_nc', true), 'obbligatoria');
        expect(DomandaCheck.serve('sempre', false), 'obbligatoria');
        expect(DomandaCheck.serve('facoltativa', true), 'facoltativa');
      },
    );

    test('a to-do check and a done one', () {
      final fare = CheckDelGiorno.fromJson({
        'pianificazione_id': 1,
        'sede': {'nome': 'A'},
        'modello': {'nome': 'M', 'domande': 9},
        'frequenza': 'giornaliera',
        'in_pausa': false,
        'stato': 'da_fare',
      });
      expect(fare.daFare, isTrue);
      final fatto = CheckDelGiorno.fromJson({
        'pianificazione_id': 1,
        'sede': {'nome': 'A'},
        'modello': {'nome': 'M'},
        'in_pausa': false,
        'stato': 'fatto',
        'ultimo': {'non_conformita': 2},
      });
      expect(fatto.daFare, isFalse);
      expect(fatto.ultimoNonConformita, 2);
    });

    test('a sent check keeps the photo ids of each answer', () {
      final d = DettaglioCheck.fromJson({
        'id': 5,
        'compilato_il': '2026-11-16T14:57:00+01:00',
        'sede': {'nome': 'A'},
        'modello': {'nome': 'M'},
        'domande': 2,
        'non_conformita': 1,
        'risposte': [
          {
            'domanda': 'Estintori?',
            'tipo': 'scelta',
            'risposta': 'No',
            'non_conforme': true,
            'nota': 'Scarico',
            'foto': [
              {'id': 11, 'nome': 'a.png'},
            ],
          },
        ],
      });
      expect(d.riepilogo.nonConformita, 1);
      expect(d.risposte.first.foto, [11]);
      expect(d.risposte.first.nonConforme, isTrue);
    });

    test('the validation errors are all kept', () {
      final e = ApiException('uno', dettagli: ['uno', 'due']);
      expect(e.dettagli.length, 2);
      expect(ApiException('solo').dettagli, isEmpty);
    });
  });

  group('plugin of the family (D-204)', () {
    test('only the active plugins are read', () {
      final u = Utente.fromJson({
        'id': 1,
        'plugin': ['securgest'],
      });
      expect(u.haCertificazione, isFalse);
      expect(u.haSecurgest, isTrue);
    });

    test('profiles without the field keep the certification', () {
      final u = Utente.fromJson({'id': 1});
      expect(u.haCertificazione, isTrue);
      expect(u.haSecurgest, isFalse);
    });

    test('the saved profile keeps the plugins', () {
      final u = Utente.fromJson(
        Utente.fromJson({
          'id': 1,
          'plugin': ['preposto', 'securgest'],
        }).toJson(),
      );
      expect(u.plugin, ['preposto', 'securgest']);
    });
  });

  group('login response', () {
    test('reads the token from data', () {
      expect(
        tokenDaRisposta({
          'data': {'token': '12|abc', 'utente': {}},
        }),
        '12|abc',
      );
      expect(tokenDaRisposta({'message': 'Errore'}), isNull);
      expect(tokenDaRisposta({'data': []}), isNull);
    });

    test('Laravel validation errors show the first message', () {
      final json = {
        'message': 'Email o password non corretti.',
        'errors': {
          'email': ['Email o password non corretti.'],
        },
      };
      expect(messaggioLoginFallito(json), 'Email o password non corretti.');
    });

    test('other server messages are shown without HTML', () {
      expect(
        messaggioLoginFallito({
          'message': '<b>Troppi tentativi</b>, riprova più tardi.',
        }),
        'Troppi tentativi, riprova più tardi.',
      );
      expect(messaggioLoginFallito({}), 'Accesso non riuscito.');
    });
  });

  group('conformita', () {
    test('maps the server values and tolerates old evidences without one', () {
      expect(Conformita.daApi('conforme'), Conformita.conforme);
      expect(Conformita.daApi('non_conforme'), Conformita.nonConforme);
      expect(Conformita.daApi(''), isNull);
      expect(Conformita.daApi(null), isNull);
    });

    test(
      'evidence reads the new description and falls back to the old note',
      () {
        final nuova = Evidenza.fromJson({
          'id': 7,
          'codice': 'EV-1',
          'descrizione': 'Ponteggio ok',
          'nota': 'Ponteggio ok',
          'esito': 'conforme',
        });
        expect(nuova.descrizione, 'Ponteggio ok');
        expect(nuova.conformita, Conformita.conforme);

        final vecchia = Evidenza.fromJson({
          'id': 8,
          'nota': 'Foto',
          'esito': '',
        });
        expect(vecchia.descrizione, 'Foto');
        expect(vecchia.conformita, isNull);
      },
    );
  });

  group('area and non-conformity', () {
    test('lists are read from the server and updated per type', () {
      final elenchi = ElenchiVoci.fromJson({
        'area': [
          {'id': 1, 'nome': 'Magazzino'},
          {'id': 2, 'nome': 'Ponte'},
        ],
        'non_conformita': [
          {'id': 3, 'nome': 'Parapetto mancante'},
        ],
      });
      expect(elenchi.di(TipoVoce.area), ['Magazzino', 'Ponte']);
      expect(elenchi.di(TipoVoce.nonConformita), ['Parapetto mancante']);

      final aggiornati = elenchi.con(TipoVoce.area, [
        'Magazzino',
        'Ponte',
        'Tetto',
      ]);
      expect(aggiornati.aree, hasLength(3));
      expect(aggiornati.nonConformita, ['Parapetto mancante']);
      expect(const ElenchiVoci().aree, isEmpty);
    });

    test('evidence carries area and non-conformity, empty for old ones', () {
      final nuova = Evidenza.fromJson({
        'id': 1,
        'esito': 'non_conforme',
        'area': 'Magazzino',
        'non_conformita': 'Parapetto mancante',
      });
      expect(nuova.area, 'Magazzino');
      expect(nuova.nonConformita, 'Parapetto mancante');
      final vecchia = Evidenza.fromJson({'id': 2});
      expect(vecchia.area, isEmpty);
      expect(vecchia.nonConformita, isEmpty);
    });
  });

  group('server 2.0 responses', () {
    test('evidence page reads data and meta', () {
      final pagina = PaginaEvidenze.fromJson({
        'data': [
          {
            'id': 1,
            'codice': 'EV-2026-000001',
            'esito': 'conforme',
            'mime': 'image/jpeg',
          },
        ],
        'meta': {'totale': 41, 'pagina': 2, 'pagine': 3},
      });
      expect(pagina.evidenze.single.codice, 'EV-2026-000001');
      expect((pagina.totale, pagina.pagina, pagina.pagine), (41, 2, 3));
    });

    test(
      'verification is intact only if the hash and the marked manifest agree',
      () {
        final integra = EsitoVerifica.fromJson({
          'integro': true,
          'manifest_coerente': true,
          'hash_certificato': 'a',
          'hash_calcolato': 'a',
        });
        expect(integra.integra, isTrue);
        final manomessa = EsitoVerifica.fromJson({
          'integro': false,
          'manifest_coerente': true,
          'hash_certificato': 'a',
          'hash_calcolato': 'b',
        });
        expect(manomessa.integra, isFalse);
        final senzaFile = EsitoVerifica.fromJson({
          'integro': false,
          'manifest_coerente': true,
          'hash_certificato': 'a',
          'hash_calcolato': null,
        });
        expect((senzaFile.integra, senzaFile.hashAttuale), (false, ''));
      },
    );

    test('certification outcome and voci names', () {
      final esito = EsitoCertificazione.fromJson({
        'codice': 'EV-2026-000009',
        'ambiente': 'sandbox',
      });
      expect((esito.codice, esito.ambiente), ('EV-2026-000009', 'sandbox'));
      expect(
        nomiVoci([
          {'id': 1, 'nome': 'A'},
          {'id': 2, 'nome': 'B'},
        ]),
        ['A', 'B'],
      );
      expect(nomiVoci(null), isEmpty);
    });
  });

  test('nomeDaContentDisposition extracts a safe file name', () {
    expect(
      nomeDaContentDisposition('attachment; filename="EV-2026-000123.pdf"'),
      'EV-2026-000123.pdf',
    );
    expect(
      nomeDaContentDisposition('attachment; filename="a b/c.zip"'),
      'a_b_c.zip',
    );
    expect(nomeDaContentDisposition(null), isNull);
  });

  test('nomeEvidenza matches the web dashboard naming', () {
    expect(
      nomeEvidenza(DateTime(2026, 9, 28, 15, 2, 9), 'jpg'),
      'evidenza-20260928-150209.jpg',
    );
  });

  test('video limit keeps a clip under the upload cap', () {
    const maxBytes = 10 * 1024 * 1024;
    final durata = durataMassimaVideo(maxBytes, kVideoBitrate, kAudioBitrate);
    final byteStimati = durata.inSeconds * (kVideoBitrate + kAudioBitrate) / 8;
    expect(byteStimati, lessThan(maxBytes));
    expect(durata.inSeconds, greaterThan(40));
  });
}
