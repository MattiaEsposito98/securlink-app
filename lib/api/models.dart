import 'dart:io';

class Utente {
  Utente({
    required this.id,
    required this.nome,
    required this.email,
    required this.ambiente,
    required this.maxUploadMb,
    this.crediti,
    this.creditiRiservati = false,
    this.plugin = const ['preposto'],
  });

  factory Utente.fromJson(Map<String, dynamic> json) {
    final crediti = json['crediti'] as Map<String, dynamic>?;
    return Utente(
      id: json['id'] as int,
      nome: json['nome'] as String? ?? '',
      email: json['email'] as String? ?? '',
      ambiente: json['ambiente'] as String? ?? 'sandbox',
      maxUploadMb: json['max_upload_mb'] as int? ?? 10,
      crediti: crediti?['disponibili'] as int?,
      creditiRiservati: crediti?['riservati'] as bool? ?? false,
      // Missing on servers (and saved profiles) older than D-204: back then
      // the account existed only with the Preposto plugin.
      plugin:
          (json['plugin'] as List<dynamic>?)?.whereType<String>().toList() ??
          const ['preposto'],
    );
  }

  final int id;
  final String nome;
  final String email;
  final String ambiente;
  final int maxUploadMb;

  /// Certificazioni ancora disponibili (null = informazione assente).
  final int? crediti;
  final bool creditiRiservati;

  /// Plugins of the account family that use the preposto account (D-204):
  /// `preposto` (certified photos) and/or `securgest` (periodic checks).
  /// The app shows only the functions of the active ones.
  final List<String> plugin;

  bool get haCertificazione => plugin.contains('preposto');
  bool get haSecurgest => plugin.contains('securgest');

  bool get isTest => ambiente != 'production';
  int get maxUploadBytes => maxUploadMb * 1024 * 1024;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    'email': email,
    'ambiente': ambiente,
    'max_upload_mb': maxUploadMb,
    if (crediti != null)
      'crediti': {'disponibili': crediti, 'riservati': creditiRiservati},
    'plugin': plugin,
  };
}

/// What the preposto declares when certifying: the photo/video documents
/// something that complies with the rules, or an irregularity.
enum Conformita {
  conforme('conforme', 'Conforme', 'Conformità', 'tutto a norma'),
  nonConforme(
    'non_conforme',
    'Non conforme',
    'Non conformità',
    'irregolarità riscontrata',
  );

  const Conformita(
    this.valoreApi,
    this.etichetta,
    this.titolo,
    this.sottotitolo,
  );

  final String valoreApi;
  final String etichetta;
  final String titolo;
  final String sottotitolo;

  String get suggerimentoDescrizione => this == conforme
      ? 'Spiega perché è conforme: cosa hai verificato e rispetto a quale requisito.'
      : 'Dettagli di questa segnalazione: dove si trova, cosa hai notato, eventuali azioni prese.';

  /// Null for evidences certified before this declaration existed.
  static Conformita? daApi(String? valore) {
    for (final c in values) {
      if (c.valoreApi == valore) return c;
    }
    return null;
  }
}

class Evidenza {
  Evidenza({
    required this.id,
    required this.codice,
    required this.nomeFile,
    required this.data,
    required this.ambiente,
    required this.descrizione,
    required this.mime,
    this.conformita,
    this.area = '',
    this.nonConformita = '',
  });

  factory Evidenza.fromJson(Map<String, dynamic> json) => Evidenza(
    id: json['id'] as int,
    codice: json['codice'] as String? ?? '',
    nomeFile: json['nome_file'] as String? ?? '',
    data: json['data'] as String? ?? '',
    ambiente: json['ambiente'] as String? ?? '',
    descrizione:
        json['descrizione'] as String? ?? json['nota'] as String? ?? '',
    mime: json['mime'] as String? ?? '',
    conformita: Conformita.daApi(json['esito'] as String?),
    area: json['area'] as String? ?? '',
    nonConformita: json['non_conformita'] as String? ?? '',
  );

  final int id;
  final String codice;
  final String nomeFile;
  final String data;
  final String ambiente;
  final String descrizione;
  final String mime;
  final Conformita? conformita;
  final String area;
  final String nonConformita;

  bool get isVideo => mime.startsWith('video/');
  bool get isTest => ambiente != 'production';
}

/// The two lists the preposto picks from, shared by everyone in the same
/// account family (group) and grown by users one entry at a time.
enum TipoVoce {
  area('area', 'Area', 'l\'area', 'una nuova area', 80, '(obbligatoria)', null),
  nonConformita(
    'non_conformita',
    'Non conformità',
    'la non conformità',
    'una nuova non conformità',
    60,
    '(oggetto, obbligatorio)',
    'Il titolo in poche parole, per esempio «Parapetto mancante». I dettagli li scrivi nella descrizione.',
  );

  const TipoVoce(
    this.valoreApi,
    this.titolo,
    this.scegli,
    this.nuova,
    this.limite,
    this.obbligo,
    this.aiuto,
  );

  final String valoreApi;
  final String titolo;
  final String scegli;
  final String nuova;

  /// Max characters of an entry: the non-conformity is a short subject, so
  /// the limit itself tells users that details belong in the description.
  final int limite;
  final String obbligo;
  final String? aiuto;
}

class ElenchiVoci {
  const ElenchiVoci({this.aree = const [], this.nonConformita = const []});

  factory ElenchiVoci.fromJson(Map<String, dynamic> json) => ElenchiVoci(
    aree: nomiVoci(json['area']),
    nonConformita: nomiVoci(json['non_conformita']),
  );

  final List<String> aree;
  final List<String> nonConformita;

  List<String> di(TipoVoce tipo) =>
      tipo == TipoVoce.area ? aree : nonConformita;

  ElenchiVoci con(TipoVoce tipo, List<String> voci) => tipo == TipoVoce.area
      ? ElenchiVoci(aree: voci, nonConformita: nonConformita)
      : ElenchiVoci(aree: aree, nonConformita: voci);
}

/// Everything the preposto declares before capturing: type, area and, for a
/// non-conformity, which one.
class Segnalazione {
  const Segnalazione({
    required this.conformita,
    required this.area,
    this.nonConformita,
  });

  final Conformita conformita;
  final String area;
  final String? nonConformita;
}

class PaginaEvidenze {
  PaginaEvidenze({
    required this.evidenze,
    required this.totale,
    required this.pagina,
    required this.pagine,
  });

  factory PaginaEvidenze.fromJson(Map<String, dynamic> json) => PaginaEvidenze(
    evidenze: (json['data'] as List)
        .map((e) => Evidenza.fromJson(e as Map<String, dynamic>))
        .toList(),
    totale: (json['meta'] as Map)['totale'] as int,
    pagina: (json['meta'] as Map)['pagina'] as int,
    pagine: (json['meta'] as Map)['pagine'] as int,
  );

  final List<Evidenza> evidenze;
  final int totale;
  final int pagina;
  final int pagine;
}

class EsitoCertificazione {
  EsitoCertificazione({required this.codice, required this.ambiente});

  factory EsitoCertificazione.fromJson(Map<String, dynamic> json) =>
      EsitoCertificazione(
        codice: json['codice'] as String? ?? '',
        ambiente: json['ambiente'] as String? ?? '',
      );

  final String codice;
  final String ambiente;
}

class EsitoVerifica {
  EsitoVerifica({
    required this.integra,
    required this.hashSalvato,
    required this.hashAttuale,
  });

  factory EsitoVerifica.fromJson(Map<String, dynamic> json) => EsitoVerifica(
    // The server also checks the marked manifest against the hash.
    integra:
        (json['integro'] as bool? ?? false) &&
        (json['manifest_coerente'] as bool? ?? false),
    hashSalvato: json['hash_certificato'] as String? ?? '',
    hashAttuale: json['hash_calcolato'] as String? ?? '',
  );

  final bool integra;
  final String hashSalvato;
  final String hashAttuale;
}

enum FormatoReport {
  pdf('PDF', 'Report leggibile'),
  zip('ZIP', 'Pacchetto completo con originale'),
  json('JSON', 'Dati strutturati'),
  xml('XML', 'Dati strutturati');

  const FormatoReport(this.etichetta, this.descrizione);
  final String etichetta;
  final String descrizione;
}

/// Names of a list of `{id, nome}` entries.
List<String> nomiVoci(Object? voci) => (voci as List? ?? const [])
    .map((v) => (v as Map)['nome'] as String)
    .toList();

// ---------------------------------------------------------------- SecurGest

/// One check to do (or done) in a site of the preposto: `GET /preposto/check`.
class CheckDelGiorno {
  CheckDelGiorno({
    required this.pianificazioneId,
    required this.sede,
    this.citta,
    required this.modello,
    required this.domande,
    required this.frequenza,
    this.periodoAl,
    required this.inPausa,
    required this.stato,
    this.ultimoNonConformita,
    this.ultimoIl,
  });

  factory CheckDelGiorno.fromJson(Map<String, dynamic> json) {
    final sede = json['sede'] as Map<String, dynamic>? ?? const {};
    final modello = json['modello'] as Map<String, dynamic>? ?? const {};
    final ultimo = json['ultimo'] as Map<String, dynamic>?;
    return CheckDelGiorno(
      pianificazioneId: json['pianificazione_id'] as int,
      sede: sede['nome'] as String? ?? '',
      citta: sede['citta'] as String?,
      modello: modello['nome'] as String? ?? '',
      domande: modello['domande'] as int? ?? 0,
      frequenza: json['frequenza'] as String? ?? 'giornaliera',
      periodoAl: (json['periodo'] as Map<String, dynamic>?)?['al'] as String?,
      inPausa: json['in_pausa'] as bool? ?? false,
      stato: json['stato'] as String? ?? 'non_previsto',
      ultimoNonConformita: ultimo?['non_conformita'] as int?,
      ultimoIl: ultimo?['il'] as String?,
    );
  }

  final int pianificazioneId;
  final String sede;
  final String? citta;
  final String modello;
  final int domande;
  final String frequenza;
  final String? periodoAl;
  final bool inPausa;

  /// `da_fare`, `fatto` or `non_previsto`.
  final String stato;
  final int? ultimoNonConformita;
  final String? ultimoIl;

  bool get daFare => stato == 'da_fare' && !inPausa;
}

/// A possible answer of a choice question; `nonConforme` marks the problem.
class OpzioneCheck {
  OpzioneCheck({required this.testo, required this.nonConforme});

  factory OpzioneCheck.fromJson(Map<String, dynamic> json) => OpzioneCheck(
    testo: json['testo'] as String? ?? '',
    nonConforme: json['non_conforme'] as bool? ?? false,
  );

  final String testo;
  final bool nonConforme;
}

/// A question of a check template (`scelta`, `testo` or `foto`).
class DomandaCheck {
  DomandaCheck({
    required this.chiave,
    required this.testo,
    this.aiuto,
    required this.tipo,
    required this.obbligatoria,
    this.opzioni = const [],
    this.nota = 'no',
    this.foto = 'no',
    this.righe = 1,
  });

  factory DomandaCheck.fromJson(Map<String, dynamic> json) => DomandaCheck(
    chiave: json['chiave'] as String? ?? '',
    testo: json['testo'] as String? ?? '',
    aiuto: json['aiuto'] as String?,
    tipo: json['tipo'] as String? ?? 'scelta',
    obbligatoria: json['obbligatoria'] as bool? ?? true,
    opzioni: [
      for (final o in json['opzioni'] as List? ?? const [])
        OpzioneCheck.fromJson(o as Map<String, dynamic>),
    ],
    nota: json['nota'] as String? ?? 'no',
    foto: json['foto'] as String? ?? 'no',
    righe: json['righe'] as int? ?? 1,
  );

  final String chiave;
  final String testo;
  final String? aiuto;
  final String tipo;
  final bool obbligatoria;
  final List<OpzioneCheck> opzioni;

  /// `no`, `facoltativa`, `se_nc` (required when non-conforming) or `sempre`.
  final String nota;
  final String foto;
  final int righe;

  /// Is the note / photo needed given the chosen answer?
  /// Returns `no`, `facoltativa` or `obbligatoria`.
  static String serve(String regola, bool nonConforme) {
    if (regola == 'no') return 'no';
    if (regola == 'sempre' || (regola == 'se_nc' && nonConforme)) {
      return 'obbligatoria';
    }
    return regola == 'se_nc' ? 'no' : 'facoltativa';
  }
}

class SezioneCheck {
  SezioneCheck({this.titolo, required this.domande});

  factory SezioneCheck.fromJson(Map<String, dynamic> json) => SezioneCheck(
    titolo: json['titolo'] as String?,
    domande: [
      for (final d in json['domande'] as List? ?? const [])
        DomandaCheck.fromJson(d as Map<String, dynamic>),
    ],
  );

  final String? titolo;
  final List<DomandaCheck> domande;
}

/// The form to fill: `GET /preposto/check/{id}`.
class ModuloCheck {
  ModuloCheck({
    required this.pianificazioneId,
    required this.sede,
    required this.modello,
    required this.versioneId,
    required this.sezioni,
    required this.fotoMb,
    required this.fotoPerDomanda,
  });

  factory ModuloCheck.fromJson(Map<String, dynamic> json) {
    final limiti = json['limiti'] as Map<String, dynamic>? ?? const {};
    final struttura = json['struttura'] as Map<String, dynamic>? ?? const {};
    return ModuloCheck(
      pianificazioneId: json['pianificazione_id'] as int,
      sede: (json['sede'] as Map<String, dynamic>?)?['nome'] as String? ?? '',
      modello:
          (json['modello'] as Map<String, dynamic>?)?['nome'] as String? ?? '',
      versioneId: json['versione_id'] as int? ?? 0,
      sezioni: [
        for (final s in struttura['sezioni'] as List? ?? const [])
          SezioneCheck.fromJson(s as Map<String, dynamic>),
      ],
      fotoMb: limiti['foto_mb'] as int? ?? 10,
      fotoPerDomanda: limiti['foto_per_domanda'] as int? ?? 5,
    );
  }

  final int pianificazioneId;
  final String sede;
  final String modello;
  final int versioneId;
  final List<SezioneCheck> sezioni;
  final int fotoMb;
  final int fotoPerDomanda;

  int get totaleDomande => sezioni.fold(0, (n, s) => n + s.domande.length);
}

/// A sent check in the history: `GET /preposto/check/storico`.
class CheckInviato {
  CheckInviato({
    required this.id,
    required this.compilatoIl,
    required this.sede,
    required this.modello,
    required this.domande,
    required this.nonConformita,
  });

  factory CheckInviato.fromJson(Map<String, dynamic> json) => CheckInviato(
    id: json['id'] as int,
    compilatoIl: json['compilato_il'] as String? ?? '',
    sede: (json['sede'] as Map<String, dynamic>?)?['nome'] as String? ?? '',
    modello:
        (json['modello'] as Map<String, dynamic>?)?['nome'] as String? ?? '',
    domande: json['domande'] as int? ?? 0,
    nonConformita: json['non_conformita'] as int? ?? 0,
  );

  final int id;
  final String compilatoIl;
  final String sede;
  final String modello;
  final int domande;
  final int nonConformita;
}

class RispostaInviata {
  RispostaInviata({
    this.sezione,
    required this.domanda,
    required this.tipo,
    this.risposta,
    required this.nonConforme,
    this.nota,
    this.foto = const [],
  });

  factory RispostaInviata.fromJson(Map<String, dynamic> json) =>
      RispostaInviata(
        sezione: json['sezione'] as String?,
        domanda: json['domanda'] as String? ?? '',
        tipo: json['tipo'] as String? ?? 'scelta',
        risposta: json['risposta'] as String?,
        nonConforme: json['non_conforme'] as bool? ?? false,
        nota: json['nota'] as String?,
        foto: [
          for (final f in json['foto'] as List? ?? const [])
            (f as Map<String, dynamic>)['id'] as int,
        ],
      );

  final String? sezione;
  final String domanda;
  final String tipo;
  final String? risposta;
  final bool nonConforme;
  final String? nota;
  final List<int> foto;
}

/// A sent check with its answers: `GET /preposto/check/compilati/{id}`.
class DettaglioCheck {
  DettaglioCheck({required this.riepilogo, required this.risposte});

  factory DettaglioCheck.fromJson(Map<String, dynamic> json) => DettaglioCheck(
    riepilogo: CheckInviato.fromJson(json),
    risposte: [
      for (final r in json['risposte'] as List? ?? const [])
        RispostaInviata.fromJson(r as Map<String, dynamic>),
    ],
  );

  final CheckInviato riepilogo;
  final List<RispostaInviata> risposte;
}

/// What the preposto typed for a question before sending.
class RispostaDaInviare {
  RispostaDaInviare({this.risposta = '', this.nota = '', List<File>? foto})
    : foto = foto ?? [];

  String risposta;
  String nota;
  final List<File> foto;
}
