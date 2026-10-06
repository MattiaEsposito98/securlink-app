class Utente {
  Utente({
    required this.id,
    required this.nome,
    required this.email,
    required this.ambiente,
    required this.maxUploadMb,
    this.usateMese,
    this.limiteMese,
  });

  factory Utente.fromJson(Map<String, dynamic> json) {
    final limite = json['limite_mensile'] as Map<String, dynamic>?;
    return Utente(
      id: json['id'] as int,
      nome: json['nome'] as String? ?? '',
      email: json['email'] as String? ?? '',
      ambiente: json['ambiente'] as String? ?? 'sandbox',
      maxUploadMb: json['max_upload_mb'] as int? ?? 10,
      usateMese: limite?['usate'] as int?,
      limiteMese: limite?['limite'] as int?,
    );
  }

  final int id;
  final String nome;
  final String email;
  final String ambiente;
  final int maxUploadMb;
  final int? usateMese;
  final int? limiteMese;

  bool get isTest => ambiente != 'production';
  int get maxUploadBytes => maxUploadMb * 1024 * 1024;

  Map<String, dynamic> toJson() => {
    'id': id,
    'nome': nome,
    'email': email,
    'ambiente': ambiente,
    'max_upload_mb': maxUploadMb,
    if (limiteMese != null)
      'limite_mensile': {'usate': usateMese, 'limite': limiteMese},
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
    integra: (json['integro'] as bool? ?? false) && (json['manifest_coerente'] as bool? ?? false),
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
List<String> nomiVoci(Object? voci) =>
    (voci as List? ?? const []).map((v) => (v as Map)['nome'] as String).toList();
