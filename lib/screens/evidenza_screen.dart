import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../widgets.dart';

class EvidenzaScreen extends StatefulWidget {
  const EvidenzaScreen({super.key, required this.evidenza});

  final Evidenza evidenza;

  @override
  State<EvidenzaScreen> createState() => _EvidenzaScreenState();
}

class _EvidenzaScreenState extends State<EvidenzaScreen> {
  late Future<File> _media;
  VideoPlayerController? _video;

  EsitoVerifica? _verifica;
  String? _erroreVerifica;
  bool _verificando = false;

  FormatoReport? _esportando;

  Evidenza get _e => widget.evidenza;
  SecurlinkApi get _api => SessioneScope.read(context).api;

  @override
  void initState() {
    super.initState();
    _media = _caricaMedia();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<File> _caricaMedia() async {
    final file = await _api.fileOriginale(_e);
    if (_e.isVideo) {
      final v = VideoPlayerController.file(file);
      await v.initialize();
      await v.setLooping(true);
      if (!mounted) {
        await v.dispose();
      } else {
        _video = v;
      }
    }
    return file;
  }

  Future<void> _verificaIntegrita() async {
    setState(() {
      _verificando = true;
      _erroreVerifica = null;
    });
    try {
      final esito = await _api.verifica(_e.id);
      if (mounted) setState(() => _verifica = esito);
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (mounted) setState(() => _erroreVerifica = e.message);
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  Future<void> _esporta(FormatoReport formato, {required bool condividi}) async {
    setState(() => _esportando = formato);
    try {
      final file = await _api.esporta(_e, formato);
      if (condividi) {
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: 'Evidenza ${_e.codice}'));
      } else {
        final risultato = await OpenFilex.open(file.path);
        if (risultato.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nessuna app per aprire questo file: usa "Condividi" per salvarlo o inviarlo.')),
          );
        }
      }
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _esportando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_e.codice)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _anteprima(),
          const SizedBox(height: 16),
          _Sezione(
            titolo: 'Dettagli',
            child: Column(
              children: [
                _Riga(etichetta: 'Codice', valore: _e.codice, mono: true),
                _Riga(etichetta: 'Data', valore: _e.data),
                _Riga(etichetta: 'File', valore: _e.nomeFile),
                _Riga(
                  etichetta: 'Ambiente',
                  child: Align(alignment: Alignment.centerLeft, child: BadgeAmbiente(isTest: _e.isTest)),
                ),
                if (_e.conformita != null)
                  _Riga(
                    etichetta: 'Esito',
                    child: Align(alignment: Alignment.centerLeft, child: BadgeConformita(conformita: _e.conformita!)),
                  ),
                if (_e.descrizione.isNotEmpty) _Riga(etichetta: 'Descrizione', valore: _e.descrizione),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Sezione(
            titolo: 'Integrità',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ricalcola l\'impronta (hash SHA-256) del file conservato e la confronta con quella certificata.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
                const SizedBox(height: 12),
                if (_verifica != null) ...[
                  BoxMessaggio(
                    tipo: _verifica!.integra ? TipoMessaggio.ok : TipoMessaggio.errore,
                    testo: _verifica!.integra
                        ? 'Integra — il file non è stato modificato.'
                        : 'ATTENZIONE — l\'impronta non corrisponde: il file risulta modificato.',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'SHA-256: ${_verifica!.hashAttuale}',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_erroreVerifica != null) ...[
                  BoxMessaggio(testo: _erroreVerifica!),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: _verificando ? null : _verificaIntegrita,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _verificando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.fingerprint),
                  label: Text(_verificando ? 'Verifica in corso…' : 'Verifica integrità'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Sezione(
            titolo: 'Report',
            child: Column(
              children: [
                for (final formato in FormatoReport.values)
                  _RigaReport(
                    formato: formato,
                    inCorso: _esportando == formato,
                    disabilitato: _esportando != null,
                    onApri: () => _esporta(formato, condividi: false),
                    onCondividi: () => _esporta(formato, condividi: true),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _anteprima() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        color: const Color(0xFF0F172A),
        constraints: BoxConstraints(minHeight: 220, maxHeight: MediaQuery.sizeOf(context).height * .5),
        alignment: Alignment.center,
        child: FutureBuilder<File>(
          future: _media,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 40),
                    const SizedBox(height: 8),
                    Text(
                      snap.error is ApiException ? (snap.error as ApiException).message : 'Anteprima non disponibile.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _media = _caricaMedia()),
                      child: const Text('Riprova', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            }
            if (!snap.hasData) return const CircularProgressIndicator(color: Colors.white);
            final v = _video;
            if (_e.isVideo && v != null) return VideoAnteprima(controller: v);
            return InteractiveViewer(child: Image.file(snap.data!, fit: BoxFit.contain));
          },
        ),
      ),
    );
  }
}

class _Sezione extends StatelessWidget {
  const _Sezione({required this.titolo, required this.child});

  final String titolo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titolo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Riga extends StatelessWidget {
  const _Riga({required this.etichetta, this.valore, this.child, this.mono = false});

  final String etichetta;
  final String? valore;
  final Widget? child;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 96, child: Text(etichetta, style: const TextStyle(color: Color(0xFF94A3B8)))),
          Expanded(
            child: child ??
                SelectableText(
                  valore ?? '',
                  style: TextStyle(fontFamily: mono ? 'monospace' : null, color: const Color(0xFF0F172A)),
                ),
          ),
        ],
      ),
    );
  }
}

class _RigaReport extends StatelessWidget {
  const _RigaReport({
    required this.formato,
    required this.inCorso,
    required this.disabilitato,
    required this.onApri,
    required this.onCondividi,
  });

  final FormatoReport formato;
  final bool inCorso;
  final bool disabilitato;
  final VoidCallback onApri;
  final VoidCallback onCondividi;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !disabilitato,
      onTap: onApri,
      leading: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: kBrandSoft, borderRadius: BorderRadius.circular(10)),
        child: Text(formato.etichetta, style: const TextStyle(color: kBrand, fontWeight: FontWeight.w800, fontSize: 12)),
      ),
      title: Text(formato.etichetta, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(formato.descrizione),
      trailing: inCorso
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
          : IconButton(
              tooltip: 'Condividi',
              icon: const Icon(Icons.share_outlined),
              onPressed: disabilitato ? null : onCondividi,
            ),
    );
  }
}
