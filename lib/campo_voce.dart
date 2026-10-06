import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/models.dart';
import 'config.dart';

/// Creates an entry on the server and returns the saved name (the existing
/// one if the same name was already there). Throws [ApiException].
typedef CreaVoce = Future<String> Function(TipoVoce tipo, String testo);

/// Removes an entry on the server and returns the updated list.
typedef EliminaVoce = Future<List<String>> Function(
  TipoVoce tipo,
  String testo,
);

/// A dropdown-like field: tap to pick from the family's list or create a new
/// entry on the spot. The list grows one entry at a time.
class CampoVoce extends StatelessWidget {
  const CampoVoce({
    super.key,
    required this.tipo,
    required this.voci,
    required this.valore,
    required this.onScelta,
    required this.onCrea,
    required this.onElimina,
  });

  final TipoVoce tipo;
  final List<String> voci;
  final String? valore;
  final ValueChanged<String> onScelta;
  final CreaVoce onCrea;
  final EliminaVoce onElimina;

  Future<void> _apri(BuildContext context) async {
    final scelta = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (_) => _FoglioVoci(
        tipo: tipo,
        voci: voci,
        valore: valore,
        onCrea: onCrea,
        onElimina: onElimina,
      ),
    );
    if (scelta != null) onScelta(scelta);
  }

  @override
  Widget build(BuildContext context) {
    final vuoto = valore == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: tipo.titolo,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF0F172A),
            ),
            children: [
              TextSpan(
                text: ' ${tipo.obbligo}',
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
        if (tipo.aiuto != null) ...[
          const SizedBox(height: 2),
          Text(
            tipo.aiuto!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Semantics(
          button: true,
          label: '${tipo.titolo}: ${valore ?? 'da scegliere'}',
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _apri(context),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: vuoto ? const Color(0xFFD0D7E2) : kBrand,
                  width: vuoto ? 1 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      valore ?? 'Scegli ${tipo.scegli}…',
                      style: TextStyle(
                        fontSize: 16,
                        color: vuoto
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF0F172A),
                        fontWeight: vuoto ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: Color(0xFF64748B),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FoglioVoci extends StatefulWidget {
  const _FoglioVoci({
    required this.tipo,
    required this.voci,
    required this.valore,
    required this.onCrea,
    required this.onElimina,
  });

  final TipoVoce tipo;
  final List<String> voci;
  final String? valore;
  final CreaVoce onCrea;
  final EliminaVoce onElimina;

  @override
  State<_FoglioVoci> createState() => _FoglioVociState();
}

class _FoglioVociState extends State<_FoglioVoci> {
  final _nome = TextEditingController();
  late List<String> _voci = List.of(widget.voci);
  late bool _creando = widget.voci.isEmpty;
  bool _inCorso = false;
  String? _errore;

  @override
  void dispose() {
    _nome.dispose();
    super.dispose();
  }

  Future<void> _elimina(String voce) async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminare «$voce»?'),
        content: const Text(
          'Sparisce dall\'elenco per tutti gli utenti del tuo gruppo. Le evidenze già certificate non cambiano.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: kErrore,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (conferma != true || !mounted) return;
    setState(() => _errore = null);
    try {
      final aggiornato = await widget.onElimina(widget.tipo, voce);
      if (!mounted) return;
      setState(() {
        _voci = aggiornato;
        if (_voci.isEmpty) _creando = true;
      });
    } on SessioneScadutaException {
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errore = e.message);
    }
  }

  Future<void> _aggiungi() async {
    final testo = _nome.text.trim();
    if (testo.isEmpty) {
      setState(() => _errore = 'Scrivi il nome da aggiungere.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _inCorso = true;
      _errore = null;
    });
    try {
      final salvata = await widget.onCrea(widget.tipo, testo);
      if (mounted) Navigator.of(context).pop(salvata);
    } on SessioneScadutaException {
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _errore = e.message);
    } finally {
      if (mounted) setState(() => _inCorso = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tastiera = MediaQuery.viewInsetsOf(context).bottom;
    final altezzaMax = MediaQuery.sizeOf(context).height * .75;
    return Padding(
      padding: EdgeInsets.only(bottom: tastiera),
      // SafeArea keeps the last row clear of Android's navigation buttons.
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: altezzaMax),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Scegli ${widget.tipo.scegli}',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (_voci.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    'Non ce n\'è ancora nessuna. Creala qui sotto: da ora comparirà nell\'elenco per tutti gli utenti del tuo gruppo.',
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      height: 1.4,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final voce in _voci)
                        ListTile(
                          title: Text(
                            voce,
                            style: TextStyle(
                              fontWeight: voce == widget.valore
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          leading: voce == widget.valore
                              ? const Icon(Icons.check, color: kBrand)
                              : const SizedBox(width: 24),
                          trailing: IconButton(
                            tooltip: 'Elimina',
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFF94A3B8),
                            ),
                            onPressed: () => _elimina(voce),
                          ),
                          onTap: () => Navigator.of(context).pop(voce),
                        ),
                    ],
                  ),
                ),
              const Divider(height: 1),
              if (!_creando)
                ListTile(
                  leading: const Icon(
                    Icons.add_circle_outline,
                    color: kArancio,
                  ),
                  title: Text(
                    'Crea ${widget.tipo.nuova}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: kBrand,
                    ),
                  ),
                  onTap: () => setState(() => _creando = true),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _nome,
                        autofocus: _voci.isNotEmpty,
                        enabled: !_inCorso,
                        maxLength: widget.tipo.limite,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _aggiungi(),
                        onChanged: (_) {
                          if (_errore != null) setState(() => _errore = null);
                        },
                        decoration: InputDecoration(
                          labelText: widget.tipo == TipoVoce.area
                              ? 'Nome della nuova area'
                              : 'Oggetto della nuova non conformità',
                          helperText: widget.tipo == TipoVoce.nonConformita
                              ? 'Solo il titolo: i dettagli vanno nella descrizione.'
                              : null,
                          errorText: _errore,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: _inCorso ? null : _aggiungi,
                        icon: _inCorso
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: const Text('Aggiungi e usa'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
