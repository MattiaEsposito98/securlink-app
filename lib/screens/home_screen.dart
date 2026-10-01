import 'package:flutter/material.dart';

import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../widgets.dart';
import 'camera_screen.dart';
import 'evidenze_screen.dart';
import 'password_screen.dart';

enum _VoceAccount { password, esci }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  // Chosen before capturing; cleared after each certification so the next
  // one is a conscious choice again.
  Conformita? _conformita;
  // Bumped after each certification so the evidence list reloads.
  final _versioneEvidenze = ValueNotifier<int>(0);

  @override
  void dispose() {
    _versioneEvidenze.dispose();
    super.dispose();
  }

  Future<void> _acquisisci(ModalitaAcquisizione modalita) async {
    final conformita = _conformita;
    if (conformita == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Scegli prima se è una conformità o una non conformità.')));
      return;
    }
    final certificata = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CameraScreen(modalita: modalita, conformita: conformita)),
    );
    if (certificata == true && mounted) {
      setState(() => _conformita = null);
      _versioneEvidenze.value++;
      SessioneScope.read(context).aggiornaUtente();
    }
  }

  Future<void> _confermaLogout() async {
    final esci = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Esci'),
        content: const Text('Vuoi uscire dal tuo account su questo dispositivo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    if (esci == true && mounted) await SessioneScope.read(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final utente = SessioneScope.of(context).utente;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Image.asset('assets/logo_orizzontale.png', height: 30, semanticLabel: 'Securlink'),
        actions: [
          if (utente != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(child: BadgeAmbiente(isTest: utente.isTest, compatto: true)),
            ),
          PopupMenuButton<_VoceAccount>(
            tooltip: 'Account',
            icon: const Icon(Icons.account_circle_outlined),
            onSelected: (voce) => switch (voce) {
              _VoceAccount.password => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const PasswordScreen()),
                ),
              _VoceAccount.esci => _confermaLogout(),
            },
            itemBuilder: (context) => [
              if (utente != null)
                PopupMenuItem<_VoceAccount>(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(utente.nome, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                      Text(utente.email, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              if (utente != null) const PopupMenuDivider(),
              const PopupMenuItem(
                value: _VoceAccount.password,
                child: ListTile(leading: Icon(Icons.key_outlined), title: Text('Cambia password'), contentPadding: EdgeInsets.zero),
              ),
              const PopupMenuItem(
                value: _VoceAccount.esci,
                child: ListTile(leading: Icon(Icons.logout), title: Text('Esci'), contentPadding: EdgeInsets.zero),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _CertificaTab(
            utente: utente,
            conformita: _conformita,
            onConformita: (c) => setState(() => _conformita = c),
            onAcquisisci: _acquisisci,
          ),
          EvidenzeScreen(versione: _versioneEvidenze),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.photo_camera_outlined), selectedIcon: Icon(Icons.photo_camera), label: 'Certifica'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Evidenze'),
        ],
      ),
    );
  }
}

class _CertificaTab extends StatelessWidget {
  const _CertificaTab({
    required this.utente,
    required this.conformita,
    required this.onConformita,
    required this.onAcquisisci,
  });

  final Utente? utente;
  final Conformita? conformita;
  final void Function(Conformita) onConformita;
  final void Function(ModalitaAcquisizione) onAcquisisci;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final u = utente;
    final limiteRaggiunto = u?.limiteMese != null && (u!.usateMese ?? 0) >= u.limiteMese!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (u != null) ...[
          Text('Ciao, ${u.nome}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Scatta una foto o registra un video dal vivo e certificalo con marca temporale qualificata.',
            style: TextStyle(color: Color(0xFF475569)),
          ),
          const SizedBox(height: 16),
        ],
        if (u != null && u.isTest) ...[
          const BoxMessaggio(
            tipo: TipoMessaggio.info,
            testo: 'Ambiente di test: le certificazioni non hanno valore legale.',
          ),
          const SizedBox(height: 12),
        ],
        if (limiteRaggiunto) ...[
          BoxMessaggio(
            testo: 'Limite mensile di certificazioni raggiunto (${u.usateMese}/${u.limiteMese}). Contatta Securlav per aumentarlo.',
          ),
          const SizedBox(height: 12),
        ],
        const _TitoloPasso(numero: 1, testo: 'Che cosa stai segnalando?'),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final c in Conformita.values) ...[
              Expanded(
                child: _SceltaConformita(
                  conformita: c,
                  selezionata: conformita == c,
                  onTap: () => onConformita(c),
                ),
              ),
              if (c != Conformita.values.last) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 20),
        const _TitoloPasso(numero: 2, testo: 'Acquisisci dal vivo'),
        const SizedBox(height: 10),
        _PulsanteAcquisizione(
          icona: Icons.photo_camera,
          titolo: 'Scatta foto',
          sottotitolo: 'Foto dal vivo, certificata con posizione GPS',
          primario: true,
          attenuato: conformita == null,
          onTap: limiteRaggiunto ? null : () => onAcquisisci(ModalitaAcquisizione.foto),
        ),
        const SizedBox(height: 12),
        _PulsanteAcquisizione(
          icona: Icons.videocam,
          titolo: 'Registra video',
          sottotitolo: u == null ? 'Video dal vivo con audio' : 'Video dal vivo con audio, fino a ${u.maxUploadMb} MB',
          attenuato: conformita == null,
          onTap: limiteRaggiunto ? null : () => onAcquisisci(ModalitaAcquisizione.video),
        ),
        const SizedBox(height: 20),
        if (u?.limiteMese != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Certificazioni questo mese', style: TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      Text('${u!.usateMese} / ${u.limiteMese}', style: const TextStyle(fontWeight: FontWeight.w700, color: kBrand)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: u.limiteMese! == 0 ? 1 : ((u.usateMese ?? 0) / u.limiteMese!).clamp(0, 1).toDouble(),
                      minHeight: 8,
                      color: kArancio,
                      backgroundColor: kBrandSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, size: 16, color: Color(0xFF94A3B8)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Foto e video si acquisiscono solo dalla fotocamera: non è possibile scegliere file già presenti sul telefono. Serve la connessione a Internet e la posizione GPS attiva.',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), height: 1.4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TitoloPasso extends StatelessWidget {
  const _TitoloPasso({required this.numero, required this.testo});

  final int numero;
  final String testo;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: kBrandSoft, shape: BoxShape.circle),
          child: Text('$numero', style: const TextStyle(color: kBrand, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Text(testo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
      ],
    );
  }
}

class _SceltaConformita extends StatelessWidget {
  const _SceltaConformita({required this.conformita, required this.selezionata, required this.onTap});

  final Conformita conformita;
  final bool selezionata;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ok = conformita == Conformita.conforme;
    final colore = ok ? kOk : kErrore;
    final sfondo = ok ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2);
    return Semantics(
      button: true,
      selected: selezionata,
      label: '${conformita.titolo}, ${conformita.sottotitolo}',
      child: Material(
        color: selezionata ? sfondo : Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: selezionata ? colore : const Color(0xFFE2E8F0), width: 2),
            ),
            child: Column(
              children: [
                Icon(
                  ok ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                  size: 28,
                  color: selezionata ? colore : const Color(0xFF94A3B8),
                ),
                const SizedBox(height: 6),
                Text(
                  conformita.titolo,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: selezionata ? colore : const Color(0xFF334155)),
                ),
                const SizedBox(height: 2),
                Text(
                  conformita.sottotitolo,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: selezionata ? colore : const Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsanteAcquisizione extends StatelessWidget {
  const _PulsanteAcquisizione({
    required this.icona,
    required this.titolo,
    required this.sottotitolo,
    required this.onTap,
    this.primario = false,
    this.attenuato = false,
  });

  final IconData icona;
  final String titolo;
  final String sottotitolo;
  final VoidCallback? onTap;
  final bool primario;

  /// Looks inactive but stays tappable, so a tap can explain what is missing.
  final bool attenuato;

  @override
  Widget build(BuildContext context) {
    final sfondo = primario ? kBrand : Colors.white;
    final testo = primario ? Colors.white : const Color(0xFF0F172A);
    return Opacity(
      opacity: onTap == null ? .45 : (attenuato ? .6 : 1),
      child: Material(
        color: sfondo,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: primario ? null : Border.all(color: const Color(0xFFC7D7FE)),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: primario ? Colors.white.withValues(alpha: .15) : kBrandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icona, color: primario ? Colors.white : kBrand, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titolo, style: TextStyle(color: testo, fontSize: 17, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(sottotitolo, style: TextStyle(color: testo.withValues(alpha: .75), fontSize: 13)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: testo.withValues(alpha: .6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
