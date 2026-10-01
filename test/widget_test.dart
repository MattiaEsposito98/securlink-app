import 'package:flutter_test/flutter_test.dart';
import 'package:securlink/api/api_client.dart';
import 'package:securlink/api/models.dart';
import 'package:securlink/config.dart';
import 'package:securlink/utils.dart';

void main() {
  group('estraiRefreshToken', () {
    test('reads the jwt-auth refresh cookie among others', () {
      const header = 'wordfence_verifiedHuman=abc; path=/, '
          'refresh_token=42.9f86d081884c7d65; expires=Wed, 28-Oct-2026 10:00:00 GMT; path=/; secure; HttpOnly';
      expect(estraiRefreshToken(header), '42.9f86d081884c7d65');
    });

    test('ignores missing or deleted cookies', () {
      expect(estraiRefreshToken(null), isNull);
      expect(estraiRefreshToken('other=1; path=/'), isNull);
      expect(estraiRefreshToken('refresh_token=deleted; expires=Thu, 01-Jan-1970 00:00:01 GMT'), isNull);
    });
  });

  group('login response', () {
    test('reads the token only when data is an object', () {
      expect(tokenDaRisposta({'success': true, 'data': {'token': 'abc'}}), 'abc');
      expect(tokenDaRisposta({'success': false, 'data': []}), isNull);
    });

    test('wrong credentials give a clean Italian message', () {
      final json = {
        'success': false,
        'code': 'incorrect_password',
        'message': 'ERRORE: Nome Utente Password non corretti. Recupera Password',
        'data': [],
      };
      expect(messaggioLoginFallito(json), 'Nome utente o password non corretti.');
    });

    test('other server messages are shown without HTML or prefix', () {
      final json = {'code': 'too_many_attempts', 'message': '<strong>ERRORE:</strong> Troppi tentativi, riprova più tardi.'};
      expect(messaggioLoginFallito(json), 'Troppi tentativi, riprova più tardi.');
    });
  });

  group('conformita', () {
    test('maps the server values and tolerates old evidences without one', () {
      expect(Conformita.daApi('conforme'), Conformita.conforme);
      expect(Conformita.daApi('non_conforme'), Conformita.nonConforme);
      expect(Conformita.daApi(''), isNull);
      expect(Conformita.daApi(null), isNull);
    });

    test('evidence reads the new description and falls back to the old note', () {
      final nuova = Evidenza.fromJson({
        'id': 7, 'codice': 'EV-1', 'descrizione': 'Ponteggio ok', 'nota': 'Ponteggio ok',
        'esito_conformita': 'conforme',
      });
      expect(nuova.descrizione, 'Ponteggio ok');
      expect(nuova.conformita, Conformita.conforme);

      final vecchia = Evidenza.fromJson({'id': 8, 'nota': 'Foto', 'esito_conformita': ''});
      expect(vecchia.descrizione, 'Foto');
      expect(vecchia.conformita, isNull);
    });
  });

  test('nomeDaContentDisposition extracts a safe file name', () {
    expect(nomeDaContentDisposition('attachment; filename="EV-2026-000123.pdf"'), 'EV-2026-000123.pdf');
    expect(nomeDaContentDisposition('attachment; filename="a b/c.zip"'), 'a_b_c.zip');
    expect(nomeDaContentDisposition(null), isNull);
  });

  test('nomeEvidenza matches the web dashboard naming', () {
    expect(nomeEvidenza(DateTime(2026, 9, 28, 15, 2, 9), 'jpg'), 'evidenza-20260928-150209.jpg');
  });

  test('video limit keeps a clip under the upload cap', () {
    const maxBytes = 10 * 1024 * 1024;
    final durata = durataMassimaVideo(maxBytes, kVideoBitrate, kAudioBitrate);
    final byteStimati = durata.inSeconds * (kVideoBitrate + kAudioBitrate) / 8;
    expect(byteStimati, lessThan(maxBytes));
    expect(durata.inSeconds, greaterThan(40));
  });
}
