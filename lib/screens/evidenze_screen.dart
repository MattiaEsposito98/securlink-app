import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../widgets.dart';
import 'evidenza_screen.dart';

class EvidenzeScreen extends StatefulWidget {
  const EvidenzeScreen({super.key, required this.versione});

  /// Changes whenever a new evidence is certified: the list reloads.
  final ValueListenable<int> versione;

  @override
  State<EvidenzeScreen> createState() => _EvidenzeScreenState();
}

class _EvidenzeScreenState extends State<EvidenzeScreen> {
  final _cerca = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final List<Evidenza> _evidenze = [];
  Conformita? _filtro;
  int _pagina = 0;
  int _pagine = 1;
  int _totale = 0;
  bool _caricando = false;
  String? _errore;
  // Discards responses of searches that were superseded while in flight.
  int _richiesta = 0;

  @override
  void initState() {
    super.initState();
    widget.versione.addListener(_ricarica);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400 && !_caricando && _pagina < _pagine) _carica(_pagina + 1);
    });
    _ricarica();
  }

  @override
  void dispose() {
    widget.versione.removeListener(_ricarica);
    _debounce?.cancel();
    _cerca.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ricarica() => _carica(1);

  bool get _filtriAttivi => _cerca.text.trim().isNotEmpty || _filtro != null;

  Future<void> _carica(int pagina) async {
    final id = ++_richiesta;
    setState(() {
      _caricando = true;
      if (pagina == 1) _errore = null;
    });
    try {
      final risultato = await SessioneScope.read(context)
          .api
          .evidenze(cerca: _cerca.text.trim(), conformita: _filtro, pagina: pagina);
      if (!mounted || id != _richiesta) return;
      setState(() {
        if (pagina == 1) _evidenze.clear();
        _evidenze.addAll(risultato.evidenze);
        _pagina = risultato.pagina;
        _pagine = risultato.pagine;
        _totale = risultato.totale;
      });
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (!mounted || id != _richiesta) return;
      if (pagina == 1) {
        setState(() => _errore = e.message);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted && id == _richiesta) setState(() => _caricando = false);
    }
  }

  void _cercaCambiata(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _ricarica);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _cerca,
            onChanged: _cercaCambiata,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Cerca per codice, file o nota…',
              prefixIcon: const Icon(Icons.search),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(999)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999),
                borderSide: const BorderSide(color: Color(0xFFD0D7E2)),
              ),
              suffixIcon: _cerca.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Azzera',
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _cerca.clear();
                        _cercaCambiata('');
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              for (final voce in <(String, Conformita?)>[
                ('Tutte', null),
                ('Conformi', Conformita.conforme),
                ('Non conformi', Conformita.nonConforme),
              ]) ...[
                ChoiceChip(
                  label: Text(voce.$1),
                  selected: _filtro == voce.$2,
                  showCheckmark: false,
                  onSelected: (_) {
                    if (_filtro == voce.$2) return;
                    setState(() => _filtro = voce.$2);
                    _ricarica();
                  },
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Expanded(child: _contenuto()),
      ],
    );
  }

  Widget _contenuto() {
    if (_errore != null && _evidenze.isEmpty) {
      return StatoVuoto(
        icona: Icons.cloud_off,
        titolo: 'Impossibile caricare le evidenze',
        testo: _errore,
        azione: OutlinedButton.icon(onPressed: _ricarica, icon: const Icon(Icons.refresh), label: const Text('Riprova')),
      );
    }
    if (_evidenze.isEmpty && _caricando) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _ricarica,
      child: _evidenze.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                StatoVuoto(
                  icona: _filtriAttivi ? Icons.search_off : Icons.folder_open,
                  titolo: _filtriAttivi ? 'Nessun risultato' : 'Nessuna evidenza certificata',
                  testo: _filtriAttivi
                      ? 'Nessuna evidenza corrisponde alla ricerca o al filtro scelto.'
                      : 'Le foto e i video che certifichi compariranno qui.',
                ),
              ],
            )
          : ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: _evidenze.length + 2,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    '$_totale evidenz${_totale == 1 ? 'a' : 'e'}',
                    style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 13),
                  );
                }
                if (i == _evidenze.length + 1) {
                  return _pagina < _pagine
                      ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                      : const SizedBox.shrink();
                }
                return _RigaEvidenza(evidenza: _evidenze[i - 1]);
              },
            ),
    );
  }
}

class _RigaEvidenza extends StatelessWidget {
  const _RigaEvidenza({required this.evidenza});

  final Evidenza evidenza;

  @override
  Widget build(BuildContext context) {
    final e = evidenza;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EvidenzaScreen(evidenza: e))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: kBrandSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(e.isVideo ? Icons.videocam : Icons.photo, color: kBrand),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.codice,
                            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 14),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        BadgeAmbiente(isTest: e.isTest, compatto: true),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(child: Text(e.data, style: const TextStyle(color: Color(0xFF475569), fontSize: 13))),
                        if (e.conformita != null) BadgeConformita(conformita: e.conformita!),
                      ],
                    ),
                    if (e.descrizione.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        e.descrizione,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }
}
