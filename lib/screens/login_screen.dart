import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../config.dart';
import '../sessione.dart';
import '../widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _utente = TextEditingController();
  final _password = TextEditingController();
  bool _inCorso = false;
  bool _mostraPassword = false;
  String? _errore;

  @override
  void initState() {
    super.initState();
    final sessione = SessioneScope.read(context);
    _errore = sessione.avviso;
    sessione.avviso = null;
  }

  @override
  void dispose() {
    _utente.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _accedi() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _inCorso = true;
      _errore = null;
    });
    try {
      await SessioneScope.read(context).login(_utente.text.trim(), _password.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errore = e.message);
    } finally {
      if (mounted) setState(() => _inCorso = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: kBrand, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.verified_user, color: Colors.white, size: 38),
                      ),
                      const SizedBox(height: 20),
                      Text('Securlink', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'Certificazione di foto e video per i preposti',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: const Color(0xFF475569)),
                      ),
                      const SizedBox(height: 32),
                      TextFormField(
                        controller: _utente,
                        enabled: !_inCorso,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: const InputDecoration(labelText: 'Nome utente o email', prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Inserisci il nome utente' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        enabled: !_inCorso,
                        obscureText: !_mostraPassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _accedi(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_mostraPassword ? Icons.visibility_off : Icons.visibility),
                            tooltip: _mostraPassword ? 'Nascondi password' : 'Mostra password',
                            onPressed: () => setState(() => _mostraPassword = !_mostraPassword),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty) ? 'Inserisci la password' : null,
                      ),
                      if (_errore != null) ...[
                        const SizedBox(height: 16),
                        BoxMessaggio(testo: _errore!),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _inCorso ? null : _accedi,
                        child: _inCorso
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                            : const Text('Accedi'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Usa le stesse credenziali del sito securlink.securlav.it',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
