import 'dart:io';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../widgets.dart';
import 'check_screen.dart' show dataBreve;

/// A check already sent, read-only: how it was at the moment of sending (D-204).
class CheckDettaglioScreen extends StatefulWidget {
  const CheckDettaglioScreen({super.key, required this.riepilogo});

  final CheckInviato riepilogo;

  @override
  State<CheckDettaglioScreen> createState() => _CheckDettaglioScreenState();
}

class _CheckDettaglioScreenState extends State<CheckDettaglioScreen> {
  DettaglioCheck? _dettaglio;
  String? _errore;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    setState(() => _errore = null);
    try {
      final d = await SessioneScope.read(context).api
          .dettaglioCheck(widget.riepilogo.id);
      if (mounted) setState(() => _dettaglio = d);
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (mounted) setState(() => _errore = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.riepilogo;
    final d = _dettaglio;
    return Scaffold(
      appBar: AppBar(title: Text(r.modello)),
      body: d == null
          ? _errore != null
                ? StatoVuoto(
                    icona: Icons.cloud_off_outlined,
                    titolo: 'Non riesco ad aprire il check',
                    testo: _errore,
                    azione: FilledButton(
                      onPressed: _carica,
                      child: const Text('Riprova'),
                    ),
                  )
                : const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(r.sede, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  'Inviato il ${dataBreve(r.compilatoIl)}. '
                  '${r.nonConformita > 0 ? '${r.nonConformita} non conformità.' : 'Tutto conforme.'}',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                ..._righe(d),
              ],
            ),
    );
  }

  List<Widget> _righe(DettaglioCheck d) {
    final out = <Widget>[];
    String? sezione;
    for (var i = 0; i < d.risposte.length; i++) {
      final r = d.risposte[i];
      if (i == 0 || r.sezione != sezione) {
        sezione = r.sezione;
        if (sezione != null) {
          out
            ..add(const SizedBox(height: 8))
            ..add(Text(sezione, style: Theme.of(context).textTheme.titleMedium))
            ..add(const Divider(thickness: 2, color: Color(0xFF0F172A)));
        }
      }
      out
        ..add(_Risposta(numero: i + 1, risposta: r))
        ..add(const SizedBox(height: 14));
    }
    return out;
  }
}

class _Risposta extends StatelessWidget {
  const _Risposta({required this.numero, required this.risposta});

  final int numero;
  final RispostaInviata risposta;

  @override
  Widget build(BuildContext context) {
    final r = risposta;
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            width: 4,
            color: r.nonConforme ? kErrore : const Color(0xFFCBD5E1),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$numero. ${r.domanda}', style: const TextStyle(fontSize: 14)),
          if (r.tipo != 'foto')
            Text(
              r.risposta == null
                  ? 'nessuna risposta'
                  : r.nonConforme
                  ? '${r.risposta} (non conforme)'
                  : r.risposta!,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: r.nonConforme ? kErrore : null,
              ),
            ),
          if (r.nota != null && r.nota!.isNotEmpty)
            Text(
              'Nota: ${r.nota}',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          if (r.foto.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final id in r.foto) _Foto(id: id)],
            ),
          ],
        ],
      ),
    );
  }
}

class _Foto extends StatefulWidget {
  const _Foto({required this.id});

  final int id;

  @override
  State<_Foto> createState() => _FotoState();
}

class _FotoState extends State<_Foto> {
  Future<File>? _file;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _file ??= SessioneScope.read(context).api.fotoCheck(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<File>(
      future: _file,
      builder: (context, snap) {
        final file = snap.data;
        return GestureDetector(
          onTap: file == null
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.black,
                    insetPadding: EdgeInsets.zero,
                    child: InteractiveViewer(child: Image.file(file)),
                  ),
                ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 80,
              height: 80,
              child: file != null
                  ? Image.file(file, fit: BoxFit.cover)
                  : Container(
                      color: const Color(0xFFE2E8F0),
                      child: snap.hasError
                          ? const Icon(Icons.broken_image_outlined)
                          : const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                    ),
            ),
          ),
        );
      },
    );
  }
}
