import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'api/models.dart';
import 'config.dart';

/// Tap-to-play video with a progress bar; the controller must be initialised.
class VideoAnteprima extends StatefulWidget {
  const VideoAnteprima({super.key, required this.controller});

  final VideoPlayerController controller;

  @override
  State<VideoAnteprima> createState() => _VideoAnteprimaState();
}

class _VideoAnteprimaState extends State<VideoAnteprima> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_aggiorna);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_aggiorna);
    super.dispose();
  }

  void _aggiorna() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return GestureDetector(
      onTap: () => c.value.isPlaying ? c.pause() : c.play(),
      child: AspectRatio(
        aspectRatio: c.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(c),
            if (!c.value.isPlaying)
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: true,
                colors: const VideoProgressColors(playedColor: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum TipoMessaggio { errore, ok, info }

class BoxMessaggio extends StatelessWidget {
  const BoxMessaggio({
    super.key,
    required this.testo,
    this.tipo = TipoMessaggio.errore,
    this.azione,
  });

  final String testo;
  final TipoMessaggio tipo;
  final Widget? azione;

  @override
  Widget build(BuildContext context) {
    final (sfondo, bordo, colore, icona) = switch (tipo) {
      TipoMessaggio.errore => (
        const Color(0xFFFEF2F2),
        const Color(0xFFFECACA),
        kErrore,
        Icons.error_outline,
      ),
      TipoMessaggio.ok => (
        const Color(0xFFECFDF5),
        const Color(0xFFA7F3D0),
        kOk,
        Icons.check_circle_outline,
      ),
      TipoMessaggio.info => (
        kBrandSoft,
        const Color(0xFFC7D7FE),
        kBrand,
        Icons.info_outline,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sfondo,
        border: Border.all(color: bordo),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icona, color: colore, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  testo,
                  style: TextStyle(color: colore, height: 1.35),
                ),
              ),
            ],
          ),
          if (azione != null)
            Align(alignment: Alignment.centerRight, child: azione),
        ],
      ),
    );
  }
}

class BadgeAmbiente extends StatelessWidget {
  const BadgeAmbiente({super.key, required this.isTest, this.compatto = false});

  final bool isTest;
  final bool compatto;

  @override
  Widget build(BuildContext context) {
    final colore = isTest ? kAmbra : kOk;
    final testo = isTest
        ? (compatto ? 'TEST' : 'Ambiente di test')
        : (compatto ? 'PROD' : 'Produzione');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isTest ? const Color(0xFFFFFBEB) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        testo,
        style: TextStyle(
          color: colore,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

class BadgeConformita extends StatelessWidget {
  const BadgeConformita({super.key, required this.conformita});

  final Conformita conformita;

  @override
  Widget build(BuildContext context) {
    final ok = conformita == Conformita.conforme;
    final colore = ok ? kOk : kErrore;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 14,
            color: colore,
          ),
          const SizedBox(width: 4),
          Text(
            conformita.etichetta,
            style: TextStyle(
              color: colore,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class StatoVuoto extends StatelessWidget {
  const StatoVuoto({
    super.key,
    required this.icona,
    required this.titolo,
    this.testo,
    this.azione,
  });

  final IconData icona;
  final String titolo;
  final String? testo;
  final Widget? azione;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icona, size: 56, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 14),
            Text(
              titolo,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (testo != null) ...[
              const SizedBox(height: 6),
              Text(
                testo!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
            if (azione != null) ...[const SizedBox(height: 18), azione!],
          ],
        ),
      ),
    );
  }
}
