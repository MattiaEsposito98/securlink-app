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
        if (limiteMese != null) 'limite_mensile': {'usate': usateMese, 'limite': limiteMese},
      };
}

class Evidenza {
  Evidenza({
    required this.id,
    required this.codice,
    required this.nomeFile,
    required this.data,
    required this.ambiente,
    required this.nota,
    required this.mime,
  });

  factory Evidenza.fromJson(Map<String, dynamic> json) => Evidenza(
        id: json['id'] as int,
        codice: json['codice'] as String? ?? '',
        nomeFile: json['nome_file'] as String? ?? '',
        data: json['data'] as String? ?? '',
        ambiente: json['ambiente'] as String? ?? '',
        nota: json['nota'] as String? ?? '',
        mime: json['mime'] as String? ?? '',
      );

  final int id;
  final String codice;
  final String nomeFile;
  final String data;
  final String ambiente;
  final String nota;
  final String mime;

  bool get isVideo => mime.startsWith('video/');
  bool get isTest => ambiente != 'production';
}

class PaginaEvidenze {
  PaginaEvidenze({required this.evidenze, required this.totale, required this.pagina, required this.pagine});

  factory PaginaEvidenze.fromJson(Map<String, dynamic> json) => PaginaEvidenze(
        evidenze: (json['evidenze'] as List)
            .map((e) => Evidenza.fromJson(e as Map<String, dynamic>))
            .toList(),
        totale: json['totale'] as int,
        pagina: json['pagina'] as int,
        pagine: json['pagine'] as int,
      );

  final List<Evidenza> evidenze;
  final int totale;
  final int pagina;
  final int pagine;
}

class EsitoCertificazione {
  EsitoCertificazione({required this.codice, required this.ambiente});

  factory EsitoCertificazione.fromJson(Map<String, dynamic> json) => EsitoCertificazione(
        codice: json['codice_evidenza'] as String? ?? '',
        ambiente: json['ambiente'] as String? ?? '',
      );

  final String codice;
  final String ambiente;
}

class EsitoVerifica {
  EsitoVerifica({required this.integra, required this.hashSalvato, required this.hashAttuale});

  factory EsitoVerifica.fromJson(Map<String, dynamic> json) => EsitoVerifica(
        integra: json['integra'] as bool,
        hashSalvato: json['hash_salvato'] as String? ?? '',
        hashAttuale: json['hash_attuale'] as String? ?? '',
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
