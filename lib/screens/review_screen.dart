import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_player/video_player.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../utils.dart';
import '../widgets.dart';

enum _Fase { pronto, posizione, invio }

/// Shows the capture, collects the note, then GPS + upload + timestamp.
/// Pops `true` once certified, `false` to retake.
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key, required this.file, required this.isVideo, required this.conformita});

  final File file;
  final bool isVideo;
  final Conformita conformita;

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _nota = TextEditingController();
  VideoPlayerController? _video;
  _Fase _fase = _Fase.pronto;
  String? _errore;
  bool _erroreImpostazioni = false;
  int? _dimensione;

  @override
  void initState() {
    super.initState();
    widget.file.length().then((v) => mounted ? setState(() => _dimensione = v) : null);
    if (widget.isVideo) {
      final v = VideoPlayerController.file(widget.file);
      _video = v;
      v.initialize().then((_) {
        v.setLooping(true);
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _nota.dispose();
    _video?.dispose();
    super.dispose();
  }

  Future<void> _certifica() async {
    FocusScope.of(context).unfocus();
    final descrizione = _nota.text.trim();
    if (descrizione.isEmpty) {
      _mostraErrore('La descrizione è obbligatoria: spiega perché è ${widget.conformita == Conformita.conforme ? 'conforme' : 'non conforme'}.');
      return;
    }
    _video?.pause();
    final sessione = SessioneScope.read(context);
    setState(() {
      _fase = _Fase.posizione;
      _errore = null;
      _erroreImpostazioni = false;
    });
    try {
      final pos = await rilevaPosizione();
      if (!mounted) return;
      setState(() => _fase = _Fase.invio);
      final esito = await sessione.api.certifica(
        file: widget.file,
        lat: pos.latitude,
        lon: pos.longitude,
        accuratezza: pos.accuracy,
        conformita: widget.conformita,
        descrizione: descrizione,
      );
      if (!mounted) return;
      await _mostraSuccesso(esito);
      if (mounted) Navigator.of(context).pop(true);
    } on PosizioneException catch (e) {
      _mostraErrore(e.message, impostazioni: e.apriImpostazioni);
    } on SessioneScadutaException {
      // The session listener already switched to the login screen.
    } on ApiException catch (e) {
      _mostraErrore(e.message);
    }
  }

  void _mostraErrore(String testo, {bool impostazioni = false}) {
    if (!mounted) return;
    setState(() {
      _fase = _Fase.pronto;
      _errore = testo;
      _erroreImpostazioni = impostazioni;
    });
  }

  Future<void> _mostraSuccesso(EsitoCertificazione esito) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.verified, color: kOk, size: 48),
        title: const Text('Evidenza certificata'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('La marca temporale qualificata è stata applicata.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SelectableText(
              esito.codice,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            BadgeAmbiente(isTest: esito.ambiente != 'production'),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fatto'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inCorso = _fase != _Fase.pronto;
    final altezzaMedia = MediaQuery.sizeOf(context).height * .45;
    final v = _video;

    return PopScope(
      canPop: !inCorso,
      child: Scaffold(
        appBar: AppBar(title: const Text('Controlla e certifica')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                color: const Color(0xFF0F172A),
                constraints: BoxConstraints(maxHeight: altezzaMedia, minHeight: 200),
                alignment: Alignment.center,
                child: widget.isVideo
                    ? (v != null && v.value.isInitialized
                        ? VideoAnteprima(controller: v)
                        : const CircularProgressIndicator(color: Colors.white))
                    : Image.file(widget.file, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(widget.isVideo ? Icons.videocam_outlined : Icons.photo_outlined, size: 18, color: const Color(0xFF64748B)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [widget.file.uri.pathSegments.last, if (_dimensione != null) formattaMb(_dimensione!)].join(' · '),
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: inCorso ? null : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.replay),
                  label: const Text('Rifai'),
                ),
              ],
            ),
            Align(alignment: Alignment.centerLeft, child: BadgeConformita(conformita: widget.conformita)),
            const SizedBox(height: 12),
            TextField(
              controller: _nota,
              enabled: !inCorso,
              maxLength: 1000,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_errore != null) setState(() => _errore = null);
              },
              decoration: InputDecoration(
                labelText: 'Descrizione (obbligatoria)',
                hintText: widget.conformita.suggerimentoDescrizione,
                alignLabelWithHint: true,
              ),
            ),
            if (_errore != null) ...[
              const SizedBox(height: 8),
              BoxMessaggio(
                testo: _errore!,
                azione: _erroreImpostazioni
                    ? TextButton(onPressed: Geolocator.openAppSettings, child: const Text('Apri impostazioni'))
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: inCorso ? null : _certifica,
              icon: inCorso
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  : const Icon(Icons.verified_user_outlined),
              label: Text(switch (_fase) {
                _Fase.pronto => 'Certifica con marca temporale',
                _Fase.posizione => 'Rilevamento posizione…',
                _Fase.invio => 'Certificazione in corso…',
              }),
            ),
            const SizedBox(height: 10),
            Text(
              _fase == _Fase.invio
                  ? 'Non chiudere l\'app finché la certificazione non è completata.'
                  : 'Alla certificazione vengono registrati posizione GPS, data e ora.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
      ),
    );
  }
}
