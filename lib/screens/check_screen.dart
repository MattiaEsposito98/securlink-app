import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../widgets.dart';
import 'check_dettaglio_screen.dart';
import 'compila_check_screen.dart';

/// «Check» tab (SecurGest, D-204): the checks of the preposto's sites, to do
/// first, and the last ones sent. Shown only when the family has the plugin.
class CheckTab extends StatefulWidget {
  const CheckTab({super.key});

  @override
  State<CheckTab> createState() => _CheckTabState();
}

class _CheckTabState extends State<CheckTab> {
  List<CheckDelGiorno>? _check;
  List<CheckInviato> _storico = const [];
  String? _errore;
  bool _caricando = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    setState(() {
      _caricando = true;
      _errore = null;
    });
    final api = SessioneScope.read(context).api;
    try {
      final risultati = await Future.wait([api.check(), api.storicoCheck()]);
      if (!mounted) return;
      setState(() {
        _check = risultati[0] as List<CheckDelGiorno>;
        _storico = risultati[1] as List<CheckInviato>;
      });
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (mounted) setState(() => _errore = e.message);
    } finally {
      if (mounted) setState(() => _caricando = false);
    }
  }

  Future<void> _compila(CheckDelGiorno c) async {
    final inviato = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CompilaCheckScreen(
          pianificazioneId: c.pianificazioneId,
          sede: c.sede,
        ),
      ),
    );
    if (inviato == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Check inviato.')));
      _carica();
    }
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    if (check == null) {
      if (_errore != null) {
        return StatoVuoto(
          icona: Icons.cloud_off_outlined,
          titolo: 'Non riesco a caricare i check',
          testo: _errore,
          azione: FilledButton(
            onPressed: _carica,
            child: const Text('Riprova'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    final daFare = check.where((c) => c.daFare).length;
    return RefreshIndicator(
      onRefresh: _carica,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (_errore != null) ...[
            BoxMessaggio(testo: _errore!),
            const SizedBox(height: 12),
          ],
          Text(
            check.isEmpty
                ? 'Nessun check'
                : daFare == 0
                ? 'Niente da fare per ora'
                : daFare == 1
                ? '1 check da fare'
                : '$daFare check da fare',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (check.isEmpty)
            const BoxMessaggio(
              tipo: TipoMessaggio.info,
              testo: 'Non ci sono check per le sedi dove lavori. Se te lo aspettavi, chiedi all\'amministratore di assegnarti alla squadra o di pianificare il check.',
            ),
          for (final c in check) ...[
            _SchedaCheck(check: c, onCompila: () => _compila(c)),
            const SizedBox(height: 10),
          ],
          if (_storico.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'I tuoi ultimi check',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final s in _storico)
              _RigaStorico(
                check: s,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CheckDettaglioScreen(riepilogo: s),
                  ),
                ),
              ),
          ],
          if (_caricando && _check != null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _SchedaCheck extends StatelessWidget {
  const _SchedaCheck({required this.check, required this.onCompila});

  final CheckDelGiorno check;
  final VoidCallback onCompila;

  String get _stato {
    if (check.inPausa) return 'In pausa: oggi non serve.';
    if (check.stato == 'non_previsto') return 'Oggi non è previsto.';
    if (check.stato == 'fatto') {
      final nc = check.ultimoNonConformita ?? 0;
      return nc > 0
          ? 'Fatto, con $nc non conformità.'
          : 'Fatto, tutto conforme.';
    }
    return switch (check.frequenza) {
      'settimanale' => 'Da fare questa settimana.',
      'mensile' => 'Da fare questo mese.',
      _ => 'Da fare oggi.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final fare = check.daFare;
    final fatto = check.stato == 'fatto';
    final conNc = fatto && (check.ultimoNonConformita ?? 0) > 0;
    final colore = fare
        ? kArancio
        : conNc
        ? kErrore
        : fatto
        ? kOk
        : const Color(0xFF94A3B8);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: fare ? kArancio : const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  fatto
                      ? (conNc
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle)
                      : Icons.radio_button_unchecked,
                  color: colore,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        check.sede,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      if (check.citta != null)
                        Text(
                          check.citta!,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      const SizedBox(height: 2),
                      Text('${check.modello}, ${check.domande} domande'),
                      const SizedBox(height: 2),
                      Text(
                        _stato,
                        style: TextStyle(
                          color: fare ? kArancio : const Color(0xFF64748B),
                          fontWeight: fare ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: fare
                  ? FilledButton.icon(
                      onPressed: onCompila,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Compila'),
                    )
                  : OutlinedButton(
                      onPressed: onCompila,
                      child: const Text('Compila di nuovo'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RigaStorico extends StatelessWidget {
  const _RigaStorico({required this.check, required this.onTap});

  final CheckInviato check;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final nc = check.nonConformita;
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        nc > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
        color: nc > 0 ? kErrore : kOk,
      ),
      title: Text(check.sede),
      subtitle: Text(
        '${dataBreve(check.compilatoIl)}, ${check.modello}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        nc > 0 ? '$nc non conformità' : 'conforme',
        style: TextStyle(
          color: nc > 0 ? kErrore : kOk,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// «16/11/2026 14:57» from an ISO date, in the phone's time zone.
String dataBreve(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  String due(int n) => n.toString().padLeft(2, '0');
  return '${due(d.day)}/${due(d.month)}/${d.year} ${due(d.hour)}:${due(d.minute)}';
}
