import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';

import '../api/models.dart';
import '../config.dart';
import '../sessione.dart';
import '../utils.dart';
import 'review_screen.dart';

enum ModalitaAcquisizione { foto, video }

/// Live capture only: there is deliberately no way to pick an existing file.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.modalita, required this.segnalazione});

  final ModalitaAcquisizione modalita;
  final Segnalazione segnalazione;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  List<CameraDescription> _camere = [];
  int _indice = 0;
  CameraController? _controller;
  bool _inizializzando = false;
  bool _inRevisione = false;
  bool _occupato = false;
  bool _senzaAudio = false;
  String? _errore;
  bool _erroreImpostazioni = false;

  FlashMode _flash = FlashMode.off;
  bool _registrando = false;
  Duration _trascorso = Duration.zero;
  Timer? _timer;
  late final int _maxBytes;
  late final Duration _durataMax;

  bool get _isVideo => widget.modalita == ModalitaAcquisizione.video;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _maxBytes = SessioneScope.read(context).utente?.maxUploadBytes ?? 10 * 1024 * 1024;
    _durataMax = durataMassimaVideo(_maxBytes, kVideoBitrate, kAudioBitrate);
    _avvia();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final c = _controller;
      // Not initialised yet means a permission prompt is on screen: leave it be.
      if (c == null || !c.value.isInitialized) return;
      _timer?.cancel();
      setState(() {
        _controller = null;
        _registrando = false;
      });
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_inizializzando && !_inRevisione && _camere.isNotEmpty) {
        _inizializza();
      }
    }
  }

  Future<void> _avvia() async {
    try {
      _camere = await availableCameras();
    } on CameraException {
      _camere = [];
    }
    if (_camere.isEmpty) {
      setState(() => _errore = 'Nessuna fotocamera disponibile su questo dispositivo.');
      return;
    }
    final posteriore = _camere.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    _indice = posteriore >= 0 ? posteriore : 0;
    await _inizializza();
  }

  Future<void> _inizializza() async {
    if (_inizializzando) return;
    _inizializzando = true;
    final precedente = _controller;
    setState(() {
      _controller = null;
      _errore = null;
    });
    await precedente?.dispose();

    final c = CameraController(
      _camere[_indice],
      ResolutionPreset.high,
      enableAudio: _isVideo && !_senzaAudio,
      videoBitrate: kVideoBitrate,
      audioBitrate: kAudioBitrate,
    );
    try {
      await c.initialize();
      await c.setFlashMode(FlashMode.off).catchError((_) {});
      _flash = FlashMode.off;
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } on CameraException catch (e) {
      await c.dispose();
      if (_isVideo && !_senzaAudio && e.code.startsWith('AudioAccess')) {
        // Like the web dashboard: without the microphone, record video only.
        _senzaAudio = true;
        _inizializzando = false;
        _snack('Microfono non consentito: il video verrà registrato senza audio.');
        return _inizializza();
      }
      if (mounted) {
        setState(() {
          _erroreImpostazioni = e.code.contains('Denied') || e.code.contains('Restricted');
          _errore = _erroreImpostazioni
              ? 'Accesso alla fotocamera negato. Per certificare serve uno scatto dal vivo: consenti la fotocamera nelle impostazioni dell\'app.'
              : 'Impossibile avviare la fotocamera (${e.description ?? e.code}).';
        });
      }
    } finally {
      _inizializzando = false;
    }
  }

  Future<void> _cambiaFotocamera() async {
    if (_camere.length < 2 || _registrando) return;
    _indice = (_indice + 1) % _camere.length;
    await _inizializza();
  }

  Future<void> _cambiaFlash() async {
    final c = _controller;
    if (c == null) return;
    final prossimo = _isVideo
        ? (_flash == FlashMode.torch ? FlashMode.off : FlashMode.torch)
        : switch (_flash) {
            FlashMode.off => FlashMode.auto,
            FlashMode.auto => FlashMode.always,
            _ => FlashMode.off,
          };
    try {
      await c.setFlashMode(prossimo);
      setState(() => _flash = prossimo);
    } on CameraException {
      _snack('Flash non disponibile su questa fotocamera.');
    }
  }

  Future<void> _scatta() async {
    final c = _controller;
    if (c == null || _occupato) return;
    setState(() => _occupato = true);
    try {
      final foto = await c.takePicture();
      await _revisione(await _salvaAcquisizione(foto, 'jpg'), isVideo: false);
    } on CameraException catch (e) {
      _snack('Scatto non riuscito: ${e.description ?? e.code}');
    } finally {
      if (mounted) setState(() => _occupato = false);
    }
  }

  Future<void> _avviaVideo() async {
    final c = _controller;
    if (c == null || _occupato) return;
    setState(() => _occupato = true);
    try {
      await c.startVideoRecording();
      _trascorso = Duration.zero;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _trascorso += const Duration(seconds: 1));
        if (_trascorso >= _durataMax) _fermaVideo();
      });
      setState(() => _registrando = true);
    } on CameraException catch (e) {
      _snack('Registrazione non avviata: ${e.description ?? e.code}');
    } finally {
      if (mounted) setState(() => _occupato = false);
    }
  }

  Future<void> _fermaVideo() async {
    final c = _controller;
    if (c == null || !_registrando) return;
    _timer?.cancel();
    setState(() {
      _registrando = false;
      _occupato = true;
    });
    try {
      final video = await c.stopVideoRecording();
      final estensione = video.path.contains('.') ? video.path.split('.').last.toLowerCase() : 'mp4';
      final file = await _salvaAcquisizione(video, estensione);
      final dimensione = await file.length();
      if (dimensione > _maxBytes) {
        await file.delete();
        _snack('Il video è troppo grande (${formattaMb(dimensione)}, limite ${formattaMb(_maxBytes)}): registrane uno più breve.');
        return;
      }
      await _revisione(file, isVideo: true);
    } on CameraException catch (e) {
      _snack('Registrazione non riuscita: ${e.description ?? e.code}');
    } finally {
      if (mounted) setState(() => _occupato = false);
    }
  }

  Future<File> _salvaAcquisizione(XFile acquisito, String estensione) async {
    final dir = await getTemporaryDirectory();
    final destinazione = '${dir.path}/${nomeEvidenza(DateTime.now(), estensione)}';
    await acquisito.saveTo(destinazione);
    try {
      await File(acquisito.path).delete();
    } on FileSystemException {
      // The plugin's own temp file; the OS will clean it up.
    }
    return File(destinazione);
  }

  Future<void> _revisione(File file, {required bool isVideo}) async {
    _inRevisione = true;
    await _controller?.pausePreview().catchError((_) {});
    if (!mounted) return;
    final certificata = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(file: file, isVideo: isVideo, segnalazione: widget.segnalazione),
      ),
    );
    _inRevisione = false;
    file.delete().ignore();
    if (!mounted) return;
    if (certificata == true) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_controller == null) {
      await _inizializza();
    } else {
      await _controller!.resumePreview().catchError((_) {});
    }
  }

  void _snack(String testo) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(testo)));
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_errore != null)
            _ErroreCamera(
              testo: _errore!,
              impostazioni: _erroreImpostazioni,
              onRiprova: _camere.isEmpty ? _avvia : _inizializza,
            )
          else if (c == null || !c.value.isInitialized)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else
            Center(child: CameraPreview(c)),
          _barraSuperiore(c),
          if (_errore == null) _barraInferiore(c),
        ],
      ),
    );
  }

  Widget _barraSuperiore(CameraController? c) {
    final flashIcona = switch (_flash) {
      FlashMode.auto => Icons.flash_auto,
      FlashMode.always || FlashMode.torch => Icons.flash_on,
      FlashMode.off => Icons.flash_off,
    };
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _PulsanteTondo(icona: Icons.close, tooltip: 'Chiudi', onPressed: () => Navigator.of(context).pop()),
              const Spacer(),
              if (_registrando)
                _IndicatoreRec(trascorso: _trascorso, massimo: _durataMax)
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    '${_isVideo ? 'VIDEO' : 'FOTO'} · ${widget.segnalazione.conformita.etichetta.toUpperCase()}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: .8, fontSize: 13),
                  ),
                ),
              const Spacer(),
              _PulsanteTondo(
                icona: flashIcona,
                tooltip: 'Flash',
                onPressed: c == null ? null : _cambiaFlash,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barraInferiore(CameraController? c) {
    final pronto = c != null && c.value.isInitialized && !_occupato;
    final suggerimento = _isVideo
        ? (_registrando ? 'Tocca per fermare' : 'Tocca per registrare · max ${formattaDurata(_durataMax)}')
        : 'Tocca per scattare';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black54],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(suggerimento, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Expanded(child: SizedBox()),
                    _Otturatore(
                      video: _isVideo,
                      registrando: _registrando,
                      onTap: !pronto && !_registrando
                          ? null
                          : _isVideo
                              ? (_registrando ? _fermaVideo : _avviaVideo)
                              : _scatta,
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _camere.length > 1 && !_registrando
                            ? _PulsanteTondo(
                                icona: Icons.cameraswitch_outlined,
                                tooltip: 'Cambia fotocamera',
                                onPressed: pronto ? _cambiaFotocamera : null,
                              )
                            : const SizedBox(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Otturatore extends StatelessWidget {
  const _Otturatore({required this.video, required this.registrando, required this.onTap});

  final bool video;
  final bool registrando;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: video ? (registrando ? 'Ferma registrazione' : 'Avvia registrazione') : 'Scatta foto',
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? .5 : 1,
          child: Container(
            width: 78,
            height: 78,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: registrando ? 30 : 60,
                height: registrando ? 30 : 60,
                decoration: BoxDecoration(
                  color: video ? const Color(0xFFEF4444) : Colors.white,
                  borderRadius: BorderRadius.circular(registrando ? 8 : 30),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IndicatoreRec extends StatelessWidget {
  const _IndicatoreRec({required this.trascorso, required this.massimo});

  final Duration trascorso;
  final Duration massimo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xEEB91C1C), borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, color: Colors.white, size: 10),
          const SizedBox(width: 6),
          Text(
            'REC ${formattaDurata(trascorso)} / ${formattaDurata(massimo)}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

class _PulsanteTondo extends StatelessWidget {
  const _PulsanteTondo({required this.icona, required this.tooltip, required this.onPressed});

  final IconData icona;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icona),
      color: Colors.white,
      disabledColor: Colors.white38,
      iconSize: 26,
      style: IconButton.styleFrom(backgroundColor: Colors.black45, fixedSize: const Size(48, 48)),
    );
  }
}

class _ErroreCamera extends StatelessWidget {
  const _ErroreCamera({required this.testo, required this.impostazioni, required this.onRiprova});

  final String testo;
  final bool impostazioni;
  final VoidCallback onRiprova;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 56),
            const SizedBox(height: 16),
            Text(testo, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, height: 1.4)),
            const SizedBox(height: 24),
            if (impostazioni)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kBrand),
                onPressed: Geolocator.openAppSettings,
                child: const Text('Apri impostazioni'),
              ),
            TextButton(
              onPressed: onRiprova,
              child: const Text('Riprova', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}
