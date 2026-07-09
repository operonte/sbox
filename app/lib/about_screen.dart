import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme.dart';

const kLinkedInUrl = 'https://www.linkedin.com/in/cristian-bravo-droguett';

Future<void> _open(String url) async {
  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}

/// Pantalla "Acerca de": versión, repo y contacto del desarrollador.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/icon/sbox_icon.png',
                            width: 72,
                            height: 72,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'sbox',
                          style: TextStyle(
                            fontFamily: fontMono,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snap) => Text(
                            snap.hasData
                                ? 'v${snap.data!.version}'
                                : ' ',
                            style: const TextStyle(
                                color: cDim, fontSize: 12, fontFamily: fontMono),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Portapapeles universal entre PC y Android por la '
                          'misma WiFi. Sin servidor, sin nube: lo que copias '
                          'viaja directo de un dispositivo al otro.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        _linkRow(Icons.person, 'Cristian Bravo · LinkedIn', kLinkedInUrl),
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
            'Acerca de',
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

  Widget _linkRow(IconData icon, String label, String url) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(url),
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
            Icon(icon, color: cAccent, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            const Icon(Icons.open_in_new, color: cDim, size: 14),
          ],
        ),
      ),
    );
  }
}
