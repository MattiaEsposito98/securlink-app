import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api/api_client.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'sessione.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final sessione = Sessione(SecurlinkApi())..avvia();
  runApp(SecurlinkApp(sessione: sessione));
}

class SecurlinkApp extends StatelessWidget {
  const SecurlinkApp({super.key, required this.sessione});

  final Sessione sessione;

  @override
  Widget build(BuildContext context) {
    final schema = ColorScheme.fromSeed(seedColor: kBrand, primary: kBrand, surface: Colors.white);
    return SessioneScope(
      sessione: sessione,
      child: MaterialApp(
        title: 'Securlink',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: schema,
          scaffoldBackgroundColor: const Color(0xFFF1F5F9),
          appBarTheme: const AppBarTheme(
            backgroundColor: kBrand,
            foregroundColor: Colors.white,
            systemOverlayStyle: SystemUiOverlayStyle.light,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFD0D7E2)),
            ),
          ),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
        ),
        home: const _Radice(),
      ),
    );
  }
}

class _Radice extends StatelessWidget {
  const _Radice();

  @override
  Widget build(BuildContext context) {
    return switch (SessioneScope.of(context).stato) {
      StatoSessione.avvio => const Scaffold(body: Center(child: CircularProgressIndicator())),
      StatoSessione.anonimo => const LoginScreen(),
      StatoSessione.autenticato => const HomeScreen(),
    };
  }
}
