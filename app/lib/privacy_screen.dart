import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'about_screen.dart' show kLinkedInUrl, kPrivacyUrl;
import 'theme.dart';

/// Pantalla "Política de privacidad": resumen corto + link a la versión
/// alojada en la web (la fuente única — evita mantener el texto duplicado en
/// dos lugares, y es la que se declara en la ficha de la tienda).
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

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
                        const _P(
                          'sbox no tiene servidor ni nube. No recolecta, no '
                          'analiza ni envía tus datos a ningún lado — ni '
                          'siquiera al desarrollador.',
                        ),
                        const SizedBox(height: 20),
                        _linkRow(Icons.lock_outline, 'Ver la política completa',
                            kPrivacyUrl),
                        const SizedBox(height: 24),
                        const _Label('CONTACTO'),
                        const _P(
                          'Para preguntas sobre esta política o sobre sbox, '
                          'escribe por LinkedIn (no se ofrece contacto por '
                          'correo).',
                        ),
                        const SizedBox(height: 8),
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
            'Política de privacidad',
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
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
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

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
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

class _P extends StatelessWidget {
  const _P(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
    );
  }
}
