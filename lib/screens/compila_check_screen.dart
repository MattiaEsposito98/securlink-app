import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../utils.dart';
import '../widgets.dart';

/// Fills a SecurGest check (D-204): big answers to tap, the non-conformity in
/// red, a note and photos that appear when the template asks for them, the
/// position if the phone gives it (optional). The server checks everything again.
class CompilaCheckScreen extends StatefulWidget {
  const CompilaCheckScreen({
    super.key,
    required this.pianificazioneId,
    required this.sede,
  });

  final int pianificazioneId;
  final String sede;

  @override
  State<CompilaCheckScreen> createState() => _CompilaCheckScreenState();
}

class _CompilaCheckScreenState extends State<CompilaCheckScreen> {
  final _scroll = ScrollController();
  final _risposte = <String, RispostaDaInviare>{};
  ModuloCheck? _modulo;
  String? _erroreCaricamento;
  List<String> _errori = const [];
  bool _invio = false;
  double? _lat;
  double? _lon;
  double? _accuratezza;

  @override
  void initState() {
    super.initState();
    _carica();
    _rilevaPosizione();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    setState(() => _erroreCaricamento = null);
    try {
      final modulo = await SessioneScope.read(context).api
          .moduloCheck(widget.pianificazioneId);
      if (mounted) setState(() => _modulo = modulo);
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (mounted) setState(() => _erroreCaricamento = e.message);
    }
  }

  /// The position is optional for the checks: if it is not there, no problem.
  Future<void> _rilevaPosizione() async {
    try {
      final p = await rilevaPosizione();
      if (mounted) {
        setState(() {
          _lat = p.latitude;
          _lon = p.longitude;
          _accuratezza = p.accuracy;
        });
      }
    } on PosizioneException {
      // No position: the check goes without.
    }
  }

  RispostaDaInviare _di(DomandaCheck d) =>
      _risposte.putIfAbsent(d.chiave, RispostaDaInviare.new);

  bool _nonConforme(DomandaCheck d) {
    final scelta = _risposte[d.chiave]?.risposta;
    return d.opzioni.any((o) => o.testo == scelta && o.nonConforme);
  }

  int get _date => _risposte.values
      .where((r) => r.risposta.isNotEmpty || r.foto.isNotEmpty)
      .length;

  Future<void> _aggiungiFoto(DomandaCheck d, ModuloCheck modulo) async {
    final r = _di(d);
    if (r.foto.length >= modulo.fotoPerDomanda) return;
    try {
      final foto = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (foto == null) return;
      final file = File(foto.path);
      if (await file.length() > modulo.fotoMb * 1024 * 1024) {
        _messaggio('La foto supera i ${modulo.fotoMb} MB.');
        return;
      }
      if (mounted) setState(() => r.foto.add(file));
    } on Exception {
      _messaggio('Non riesco ad aprire la fotocamera. Controlla il permesso.');
    }
  }

  void _messaggio(String testo) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(testo)));
  }

  Future<void> _invia(ModuloCheck modulo) async {
    setState(() {
      _invio = true;
      _errori = const [];
    });
    try {
      await SessioneScope.read(context).api.inviaCheck(
        modulo: modulo,
        risposte: _risposte,
        lat: _lat,
        lon: _lon,
        accuratezza: _accuratezza,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _errori = e.dettagli.isNotEmpty ? e.dettagli : [e.message],
      );
      // The template changed meanwhile: reload it (the answers stay).
      if (e.message.contains('ricarica')) _carica();
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } finally {
      if (mounted) setState(() => _invio = false);
    }
  }

  Future<bool> _conferma() async {
    if (_date == 0) return true;
    final esci = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uscire dal check?'),
        content: const Text('Le risposte date finora andranno perse.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continua a compilare'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    return esci == true;
  }

  @override
  Widget build(BuildContext context) {
    final modulo = _modulo;
    return PopScope(
      canPop: _date == 0 || _invio,
      onPopInvokedWithResult: (esce, _) async {
        if (esce) return;
        if (await _conferma() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(modulo?.modello ?? widget.sede)),
        body: modulo == null
            ? _erroreCaricamento != null
                  ? StatoVuoto(
                      icona: Icons.cloud_off_outlined,
                      titolo: 'Non riesco ad aprire il check',
                      testo: _erroreCaricamento,
                      azione: FilledButton(
                        onPressed: _carica,
                        child: const Text('Riprova'),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator())
            : _form(modulo),
        bottomNavigationBar: modulo == null ? null : _barra(modulo),
      ),
    );
  }

  Widget _form(ModuloCheck modulo) {
    var numero = 0;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          modulo.sede,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
        ),
        const SizedBox(height: 12),
        if (_errori.isNotEmpty) ...[
          BoxMessaggio(
            testo: _errori.length == 1
                ? _errori.first
                : 'Da sistemare prima di inviare:\n${_errori.map((e) => '• $e').join('\n')}',
          ),
          const SizedBox(height: 12),
        ],
        for (final s in modulo.sezioni) ...[
          if (s.titolo != null) ...[
            const SizedBox(height: 8),
            Text(s.titolo!, style: Theme.of(context).textTheme.titleLarge),
            const Divider(thickness: 2, color: Color(0xFF0F172A)),
          ],
          for (final d in s.domande) ...[
            _domanda(d, ++numero, modulo),
            const SizedBox(height: 18),
          ],
        ],
      ],
    );
  }

  Widget _domanda(DomandaCheck d, int numero, ModuloCheck modulo) {
    final r = _di(d);
    final nc = _nonConforme(d);
    final nota = d.tipo == 'scelta' ? DomandaCheck.serve(d.nota, nc) : 'no';
    final foto = d.tipo == 'foto'
        ? (d.obbligatoria ? 'obbligatoria' : 'facoltativa')
        : d.tipo == 'scelta'
        ? DomandaCheck.serve(d.foto, nc)
        : 'no';
    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            width: 4,
            color: nc ? kErrore : const Color(0xFFCBD5E1),
          ),
        ),
      ),
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$numero. ',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                TextSpan(text: d.testo),
                if (!d.obbligatoria)
                  const TextSpan(
                    text: '  facoltativa',
                    style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                  ),
              ],
            ),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          if (d.aiuto != null) ...[
            const SizedBox(height: 2),
            Text(d.aiuto!, style: const TextStyle(color: Color(0xFF64748B))),
          ],
          const SizedBox(height: 8),
          if (d.tipo == 'scelta')
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final o in d.opzioni) _scelta(d, o, r)],
            ),
          if (d.tipo == 'testo')
            TextField(
              minLines: d.righe == 3 ? 3 : 1,
              maxLines: d.righe == 3 ? 6 : 1,
              maxLength: d.righe == 3 ? 2000 : 300,
              onChanged: (v) => r.risposta = v.trim(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          if (nota != 'no') ...[
            const SizedBox(height: 8),
            TextField(
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              onChanged: (v) => r.nota = v,
              decoration: InputDecoration(
                hintText: nota == 'obbligatoria'
                    ? (nc
                          ? 'Descrivi la non conformità (obbligatoria)'
                          : 'Nota (obbligatoria)')
                    : 'Nota (facoltativa)',
                border: const OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
          if (foto != 'no') ...[
            const SizedBox(height: 8),
            _fotoRiga(d, r, modulo, foto == 'obbligatoria'),
          ],
        ],
      ),
    );
  }

  Widget _scelta(DomandaCheck d, OpzioneCheck o, RispostaDaInviare r) {
    final scelto = r.risposta == o.testo;
    final colore = o.nonConforme ? kErrore : kBrand;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 88, minHeight: 48),
      child: scelto
          ? FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colore),
              onPressed: () => setState(() => r.risposta = ''),
              child: Text(o.testo),
            )
          : OutlinedButton(
              onPressed: () => setState(() => r.risposta = o.testo),
              child: Text(o.testo),
            ),
    );
  }

  Widget _fotoRiga(
    DomandaCheck d,
    RispostaDaInviare r,
    ModuloCheck modulo,
    bool obbligatoria,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final f in r.foto)
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(f, width: 72, height: 72, fit: BoxFit.cover),
              ),
              Positioned(
                top: -8,
                right: -8,
                child: InkWell(
                  onTap: () => setState(() => r.foto.remove(f)),
                  child: const CircleAvatar(
                    radius: 11,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.close, size: 15),
                  ),
                ),
              ),
            ],
          ),
        if (r.foto.length < modulo.fotoPerDomanda)
          OutlinedButton.icon(
            onPressed: () => _aggiungiFoto(d, modulo),
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(
              obbligatoria
                  ? 'Aggiungi una foto (obbligatoria)'
                  : 'Aggiungi una foto',
            ),
          ),
      ],
    );
  }

  Widget _barra(ModuloCheck modulo) {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$_date di ${modulo.totaleDomande} risposte'
                  '${_lat != null ? ', posizione rilevata' : ''}',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kArancio,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(120, 48),
                ),
                onPressed: _invio ? null : () => _invia(modulo),
                child: _invio
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Invia il check'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
