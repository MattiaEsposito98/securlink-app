import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../widgets.dart';
import 'segnala_near_miss_screen.dart';

/// «Near miss» tab (SecurMiss, D-207): report a near miss at one of the
/// preposto's sites and see the last ones sent. Shown only when the family has
/// the plugin.
class NearMissTab extends StatefulWidget {
  const NearMissTab({super.key});

  @override
  State<NearMissTab> createState() => _NearMissTabState();
}

class _NearMissTabState extends State<NearMissTab> {
  DatiNearMiss? _dati;
  String? _errore;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    setState(() => _errore = null);
    try {
      final dati = await SessioneScope.read(context).api.nearMiss();
      if (mounted) setState(() => _dati = dati);
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (mounted) setState(() => _errore = e.message);
    }
  }

  Future<void> _segnala(DatiNearMiss dati) async {
    final numero = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => SegnalaNearMissScreen(dati: dati)),
    );
    if (numero != null && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              numero > 0
                  ? 'Segnalazione n. $numero inviata. Grazie!'
                  : 'Segnalazione inviata. Grazie!',
            ),
          ),
        );
      _carica();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dati = _dati;
    if (dati == null) {
      if (_errore != null) {
        return StatoVuoto(
          icona: Icons.cloud_off_outlined,
          titolo: 'Non riesco a caricare i near miss',
          testo: _errore,
          azione: FilledButton(
            onPressed: _carica,
            child: const Text('Riprova'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: _carica,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Hai visto un quasi incidente?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          const Text(
            'Qualcosa che poteva fare male o danni e per fortuna non li ha '
            'fatti. Segnalarlo aiuta a evitare che capiti davvero.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 15),
          ),
          const SizedBox(height: 14),
          if (dati.sedi.isEmpty)
            const BoxMessaggio(
              tipo: TipoMessaggio.info,
              testo: 'Non sei assegnato a nessuna sede. Chiedi all\'amministratore di metterti in una squadra.',
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kArancio,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => _segnala(dati),
              icon: const Icon(Icons.warning_amber_rounded),
              label: const Text('Segnala un near miss'),
            ),
          if (dati.inviate.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              'Le tue ultime segnalazioni',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final s in dati.inviate) _RigaNearMiss(segnalazione: s),
          ],
        ],
      ),
    );
  }
}

class _RigaNearMiss extends StatelessWidget {
  const _RigaNearMiss({required this.segnalazione});

  final NearMissInviato segnalazione;

  @override
  Widget build(BuildContext context) {
    final s = segnalazione;
    final chiusa = s.stato == 'chiusa';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        chiusa ? Icons.check_circle_outline : Icons.hourglass_empty,
        color: chiusa ? kOk : kAmbra,
      ),
      title: Text('n. ${s.numero}, ${s.sede}'),
      subtitle: Text(
        '${dataDa(s.dataEvento)}, ${s.causa}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        s.statoEtichetta,
        style: TextStyle(
          color: chiusa ? kOk : const Color(0xFF64748B),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// «16/11/2026» from an ISO date (`2026-11-16`).
String dataDa(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  String due(int n) => n.toString().padLeft(2, '0');
  return '${due(d.day)}/${due(d.month)}/${d.year}';
}
