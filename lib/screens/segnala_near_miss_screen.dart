import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../widgets.dart';
import 'near_miss_screen.dart' show dataDa;

/// The near-miss form (SecurMiss, D-207), made for the phone: site, when, what
/// happened, the cause (searchable, or «Altro»), what was done at once (the
/// cause suggests it), risk, origin and up to 5 photos. The reporter is the
/// account. The server checks everything again.
class SegnalaNearMissScreen extends StatefulWidget {
  const SegnalaNearMissScreen({super.key, required this.dati});

  final DatiNearMiss dati;

  @override
  State<SegnalaNearMissScreen> createState() => _SegnalaNearMissScreenState();
}

class _SegnalaNearMissScreenState extends State<SegnalaNearMissScreen> {
  final _scroll = ScrollController();
  final _punto = TextEditingController();
  final _descrizione = TextEditingController();
  final _causaAltro = TextEditingController();
  final _azioni = TextEditingController();
  final _origineAltro = TextEditingController();
  final _rischi = <String>{};
  final _origini = <String>{};
  final _foto = <File>[];
  int? _sede;
  DateTime? _data;
  int? _casistica;
  bool _causaLibera = false;
  List<String> _errori = const [];
  bool _invio = false;

  DatiNearMiss get _dati => widget.dati;

  @override
  void initState() {
    super.initState();
    if (_dati.sedi.length == 1) _sede = _dati.sedi.first.id;
  }

  @override
  void dispose() {
    for (final c in [
      _punto,
      _descrizione,
      _causaAltro,
      _azioni,
      _origineAltro,
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  bool get _vuoto =>
      _descrizione.text.trim().isEmpty && _foto.isEmpty && _casistica == null;

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _scegliData() async {
    final oggi = DateTime.tryParse(_dati.oggi) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _data ?? oggi,
      firstDate: oggi.subtract(const Duration(days: 365)),
      lastDate: oggi,
    );
    if (d != null) setState(() => _data = d);
  }

  Future<void> _scegliCausa() async {
    final scelta = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FoglioCausa(casistiche: _dati.casistiche),
    );
    if (scelta == null || !mounted) return;
    setState(() {
      if (scelta is CasisticaNearMiss) {
        _casistica = scelta.id;
        _causaLibera = false;
        // The cause's immediate actions are a starting point: only if the
        // reporter has not written his own.
        final proposte = _dati.casistiche.map((c) => c.azioniImmediate);
        if (_azioni.text.trim().isEmpty || proposte.contains(_azioni.text)) {
          _azioni.text = scelta.azioniImmediate;
        }
      } else {
        _casistica = null;
        _causaLibera = true;
      }
    });
  }

  Future<void> _aggiungiFoto() async {
    if (_foto.length >= _dati.fotoMax) return;
    try {
      final foto = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        imageQuality: 85,
      );
      if (foto == null) return;
      final file = File(foto.path);
      if (await file.length() > 10 * 1024 * 1024) {
        _messaggio('La foto supera i 10 MB.');
        return;
      }
      if (mounted) setState(() => _foto.add(file));
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

  /// What is still missing, before bothering the server.
  List<String> _mancanti() => [
    if (_sede == null) 'la sede',
    if (_data == null) 'la data dell\'evento',
    if (_descrizione.text.trim().isEmpty) 'cosa è successo',
    if (_casistica == null && !_causaLibera) 'la causa',
    if (_causaLibera && _causaAltro.text.trim().isEmpty) 'la causa (Altro)',
    if (_azioni.text.trim().isEmpty) 'cosa avete fatto subito',
    if (_rischi.isEmpty) 'il potenziale rischio',
    if (_origini.isEmpty) 'l\'origine',
    if (_origini.contains('altro') && _origineAltro.text.trim().isEmpty)
      'l\'altra origine',
  ];

  Future<void> _invia() async {
    final mancanti = _mancanti();
    if (mancanti.isNotEmpty) {
      setState(() => _errori = ['Manca ancora: ${mancanti.join(', ')}.']);
      _inCima();
      return;
    }
    setState(() {
      _invio = true;
      _errori = const [];
    });
    try {
      final numero = await SessioneScope.read(context).api.inviaNearMiss(
        NearMissDaInviare(
          cantiereId: _sede!,
          dataEvento: _iso(_data!),
          descrizione: _descrizione.text,
          azioniImmediate: _azioni.text,
          rischi: _rischi.toList(),
          origini: _origini.toList(),
          casisticaId: _causaLibera ? null : _casistica,
          causaAltro: _causaAltro.text,
          punto: _punto.text,
          origineAltro: _origineAltro.text,
          foto: _foto,
        ),
      );
      if (mounted) Navigator.of(context).pop(numero);
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _errori = e.dettagli.isNotEmpty ? e.dettagli : [e.message],
      );
      _inCima();
    } finally {
      if (mounted) setState(() => _invio = false);
    }
  }

  void _inCima() {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<bool> _conferma() async {
    final esci = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uscire senza inviare?'),
        content: const Text('Quello che hai scritto andrà perso.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continua'),
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
    final causa = _casistica == null
        ? null
        : _dati.casistiche.where((c) => c.id == _casistica).firstOrNull;
    return PopScope(
      canPop: _vuoto || _invio,
      onPopInvokedWithResult: (esce, _) async {
        if (esce) return;
        if (await _conferma() && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Segnala un near miss')),
        body: ListView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            if (_errori.isNotEmpty) ...[
              BoxMessaggio(
                testo: _errori.length == 1
                    ? _errori.first
                    : 'Da sistemare prima di inviare:\n${_errori.map((e) => '• $e').join('\n')}',
              ),
              const SizedBox(height: 12),
            ],
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Segnali come ',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                  TextSpan(
                    text: _dati.segnalatore,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_dati.sedi.length > 1) ...[
              DropdownButtonFormField<int>(
                initialValue: _sede,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Sede *',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final s in _dati.sedi)
                    DropdownMenuItem(value: s.id, child: Text(s.etichetta)),
                ],
                onChanged: (v) => setState(() => _sede = v),
              ),
              const SizedBox(height: 14),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  _dati.sedi.first.etichetta,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                alignment: Alignment.centerLeft,
              ),
              onPressed: _scegliData,
              icon: const Icon(Icons.event_outlined),
              label: Text(
                _data == null
                    ? 'Quando è successo *'
                    : 'Successo il ${dataDa(_iso(_data!))}',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _punto,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Punto preciso (facoltativo)',
                hintText: 'Es. zona gru, piano 2',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _descrizione,
              minLines: 4,
              maxLines: 8,
              maxLength: 5000,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Cosa è successo *',
                alignLabelWithHint: true,
                helperText: 'L\'attività in corso, come è andata, perché non ha causato danni.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 18),
            _titolo('La causa *'),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                alignment: Alignment.centerLeft,
              ),
              onPressed: _scegliCausa,
              child: Text(
                causa?.causa ??
                    (_causaLibera
                        ? 'Altro: la descrivo io'
                        : 'Scegli la causa più vicina'),
                style: TextStyle(
                  fontWeight: causa != null || _causaLibera
                      ? FontWeight.w600
                      : null,
                ),
              ),
            ),
            if (_causaLibera) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _causaAltro,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Descrivi la causa',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
            if (_casistica != null || _causaLibera) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _azioni,
                minLines: 3,
                maxLines: 7,
                maxLength: 3000,
                decoration: InputDecoration(
                  labelText: 'Cosa avete fatto subito *',
                  alignLabelWithHint: true,
                  helperText: causa != null
                      ? 'Proposte dalla causa scelta: cambiale se avete fatto altro.'
                      : null,
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 18),
            _titolo('Potenziale rischio *'),
            _scelte(_dati.rischi, _rischi),
            const SizedBox(height: 18),
            _titolo('Origine *'),
            _scelte(_dati.origini, _origini),
            if (_origini.contains('altro')) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _origineAltro,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Quale altra origine?',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 18),
            _titolo('Foto (facoltative, al massimo ${_dati.fotoMax})'),
            _fotoRiga(),
          ],
        ),
        bottomNavigationBar: Material(
          elevation: 8,
          color: Colors.white,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: kArancio,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _invio ? null : _invia,
                child: _invio
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Invia la segnalazione'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _titolo(String testo) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(testo, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget _scelte(List<VoceNearMiss> voci, Set<String> scelti) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final v in voci)
        FilterChip(
          label: Text(v.nome),
          selected: scelti.contains(v.codice),
          showCheckmark: true,
          onSelected: (on) => setState(() {
            on ? scelti.add(v.codice) : scelti.remove(v.codice);
          }),
        ),
    ],
  );

  Widget _fotoRiga() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      for (final f in _foto)
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
                onTap: () => setState(() => _foto.remove(f)),
                child: const CircleAvatar(
                  radius: 11,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.close, size: 15),
                ),
              ),
            ),
          ],
        ),
      if (_foto.length < _dati.fotoMax)
        OutlinedButton.icon(
          onPressed: _aggiungiFoto,
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Aggiungi una foto'),
        ),
    ],
  );
}

/// The causes, with a search box: type a word, tap the row. «Altro» is last.
class _FoglioCausa extends StatefulWidget {
  const _FoglioCausa({required this.casistiche});

  final List<CasisticaNearMiss> casistiche;

  @override
  State<_FoglioCausa> createState() => _FoglioCausaState();
}

class _FoglioCausaState extends State<_FoglioCausa> {
  String _cerca = '';

  @override
  Widget build(BuildContext context) {
    final testo = _cerca.trim().toLowerCase();
    final trovate = [
      for (final c in widget.casistiche)
        if (testo.isEmpty || c.causa.toLowerCase().contains(testo)) c,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _cerca = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Scrivi una parola: carico, scala, scavo…',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final c in trovate)
                    ListTile(
                      title: Text(c.causa),
                      onTap: () => Navigator.pop(context, c),
                    ),
                  if (trovate.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Nessuna causa con «$_cerca».',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  ListTile(
                    title: const Text(
                      'Altro: la descrivo io',
                      style: TextStyle(
                        color: kBrand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () => Navigator.pop(context, 'altro'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
