import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

const kLinuxDownloadUrl =
    'https://github.com/operonte/sbox/releases/latest/download/sbox-x86_64.AppImage';
// Sin build de Windows todavía — el botón queda deshabilitado hasta que
// exista un instalador real que enlazar aquí.
const kWindowsDownloadUrl = '';

/// Pantalla "Cómo usar sbox": guía de primer uso + descargas de PC +
/// solución de problemas. Solo Android (el PC ya ve el código en pantalla).
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              color: cCard.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: cBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('PRIMEROS PASOS'),
                        const _Step(1, 'Instala sbox en tu PC (link más abajo) y en tu Android.'),
                        const _Step(2, 'Abre sbox en el PC — muestra un código de 6 dígitos.'),
                        const _Step(3, 'Abre sbox en el Android, en la misma WiFi que el PC, '
                            'y escribe ese código.'),
                        const _Step(4, 'Listo. La próxima vez se conectan solos, sin volver a '
                            'pedir el código — a menos que "olvides" el dispositivo desde '
                            'Configuración.'),
                        const _Label('USO DIARIO'),
                        const _Bullet('Lo que copias en un dispositivo se manda solo al otro '
                            '(se puede apagar en "Portapapeles" arriba).'),
                        const _Bullet('Para mandar un archivo: el botón 📎, o "Compartir" desde '
                            'cualquier otra app.'),
                        const _Bullet('Lo que llega se guarda en Descargas/sbox, y si es texto '
                            'o imagen también queda en tu portapapeles.'),
                        const _Label('DESCARGAR SBOX PARA PC'),
                        _downloadRow(Icons.desktop_windows, 'Linux (AppImage)',
                            kLinuxDownloadUrl, enabled: true),
                        const SizedBox(height: 8),
                        _downloadRow(Icons.desktop_windows, 'Windows',
                            kWindowsDownloadUrl, enabled: false, note: 'Próximamente'),
                        const _Label('SI ALGO NO FUNCIONA'),
                        const _Bullet('El AppImage no abre en Linux: instala fuse — '
                            '"sudo apt install libfuse2" (Ubuntu/Debian/Pop!_OS). La mayoría '
                            'de distros modernas ya lo trae.'),
                        const _Bullet('No aparece la PC sola: anota la IP que muestra la '
                            'cajita del PC y escríbela a mano en el campo de abajo del '
                            'código.'),
                        const _Bullet('No conecta: revisa que el PC y el Android estén en la '
                            'misma red WiFi — sbox no funciona por datos móviles ni entre '
                            'redes distintas.'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 16, 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: cDim, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Text(
            'Cómo usar sbox',
            style: TextStyle(
              fontFamily: fontMono,
              fontWeight: FontWeight.w700,
              fontSize: 15,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _downloadRow(IconData icon, String label, String url,
      {required bool enabled, String? note}) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled
            ? () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)
            : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: enabled ? cAccent : cDim, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
              ),
              if (note != null)
                Text(note, style: const TextStyle(color: cDim, fontSize: 11))
              else if (enabled)
                const Icon(Icons.download, color: cDim, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: fontMono,
          color: cDim,
          fontSize: 11,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step(this.n, this.text);
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cAccent.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style: const TextStyle(
                    color: cAccent, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 4, color: cDim),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
