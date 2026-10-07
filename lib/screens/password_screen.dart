import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../sessione.dart';
import '../widgets.dart';

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _attuale = TextEditingController();
  final _nuova = TextEditingController();
  final _conferma = TextEditingController();
  bool _inCorso = false;
  bool _mostra = false;
  String? _errore;

  @override
  void dispose() {
    _attuale.dispose();
    _nuova.dispose();
    _conferma.dispose();
    super.dispose();
  }

  Future<void> _salva() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _inCorso = true;
      _errore = null;
    });
    try {
      await SessioneScope.read(context).api
          .cambiaPassword(attuale: _attuale.text, nuova: _nuova.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password modificata. Usala anche per accedere al sito.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } on SessioneScadutaException {
      // Handled by the session listener.
    } on ApiException catch (e) {
      if (mounted) setState(() => _errore = e.message);
    } finally {
      if (mounted) setState(() => _inCorso = false);
    }
  }

  InputDecoration _decorazione(String etichetta) => InputDecoration(
    labelText: etichetta,
    prefixIcon: const Icon(Icons.lock_outline),
    suffixIcon: IconButton(
      icon: Icon(_mostra ? Icons.visibility_off : Icons.visibility),
      tooltip: _mostra ? 'Nascondi password' : 'Mostra password',
      onPressed: () => setState(() => _mostra = !_mostra),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_inCorso,
      child: Scaffold(
        appBar: AppBar(title: const Text('Cambia password')),
        body: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'La nuova password vale sia per l\'app sia per il sito. Le sessioni aperte sul sito verranno chiuse.',
                style: TextStyle(color: Color(0xFF475569), height: 1.4),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _attuale,
                enabled: !_inCorso,
                obscureText: !_mostra,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.next,
                decoration: _decorazione('Password attuale'),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Inserisci la password attuale'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nuova,
                enabled: !_inCorso,
                obscureText: !_mostra,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                decoration: _decorazione('Nuova password')
                    .copyWith(helperText: 'Almeno 8 caratteri'),
                validator: (v) {
                  if (v == null || v.length < 8) {
                    return 'La password deve avere almeno 8 caratteri';
                  }
                  if (v == _attuale.text) {
                    return 'Deve essere diversa da quella attuale';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _conferma,
                enabled: !_inCorso,
                obscureText: !_mostra,
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _salva(),
                decoration: _decorazione('Conferma nuova password'),
                validator: (v) =>
                    v != _nuova.text ? 'Le due password non coincidono' : null,
              ),
              if (_errore != null) ...[
                const SizedBox(height: 16),
                BoxMessaggio(testo: _errore!),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _inCorso ? null : _salva,
                child: _inCorso
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Salva nuova password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
