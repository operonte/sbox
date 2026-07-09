import 'package:flutter/material.dart';

import 'about_screen.dart';
import 'autostart.dart';
import 'platform.dart';
import 'privacy_screen.dart';
import 'settings.dart';
import 'theme.dart';

/// Pantalla de Configuración: tamaño de texto (1×…4×) y nombre del dispositivo.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameCtrl =
      TextEditingController(text: Settings.instance.deviceName.value);

  // El estado real vive en el archivo .desktop (ver autostart.dart); esto es
  // solo la copia en memoria para pintar el switch mientras se consulta.
  bool _autostartOn = false;

  @override
  void initState() {
    super.initState();
    if (isDesktop) {
      LinuxAutostart.isEnabled().then((v) {
        if (mounted) setState(() => _autostartOn = v);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

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
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Label('TAMAÑO DEL TEXTO'),
                        const SizedBox(height: 10),
                        _textSizeSelector(),
                        const SizedBox(height: 24),
                        const _Label('NOMBRE DEL DISPOSITIVO'),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _nameCtrl,
                          onChanged: (v) =>
                              Settings.instance.setDeviceName(v.trim()),
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Mi PC',
                            hintStyle: const TextStyle(color: cDim),
                            isDense: true,
                            filled: true,
                            fillColor: Colors.black.withValues(alpha: 0.25),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: cBorder),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  BorderSide(color: cAccent.withValues(alpha: 0.6)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Con este nombre te verá el otro dispositivo al emparejar.',
                          style: TextStyle(color: cDim, fontSize: 12, height: 1.4),
                        ),
                        const SizedBox(height: 24),
                        const _Label('DISPOSITIVOS DE CONFIANZA'),
                        const SizedBox(height: 10),
                        _trustedDevicesSection(),
                        const SizedBox(height: 24),
                        const _Label('PORTAPAPELES'),
                        const SizedBox(height: 10),
                        _autoClipboardSection(),
                        // Auto-borrado de imágenes e inicio automático: solo
                        // tienen sentido en el PC (host).
                        if (isDesktop) ...[
                          const SizedBox(height: 24),
                          const _Label('IMÁGENES RECIBIDAS (PC)'),
                          const SizedBox(height: 10),
                          _autoDeleteSection(),
                          const SizedBox(height: 24),
                          const _Label('INICIO AUTOMÁTICO'),
                          const SizedBox(height: 10),
                          _autostartSection(),
                        ],
                        const SizedBox(height: 24),
                        const _Label('ACERCA DE SBOX'),
                        const SizedBox(height: 10),
                        _navRow(context, Icons.info_outline, 'Acerca de',
                            () => const AboutScreen()),
                        const SizedBox(height: 8),
                        _navRow(context, Icons.privacy_tip_outlined,
                            'Política de privacidad', () => const PrivacyScreen()),
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
            'Configuración',
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

  Widget _textSizeSelector() {
    const options = <String, double>{'1×': 1.0, '2×': 2.0, '3×': 3.0, '4×': 4.0};
    return ValueListenableBuilder<double>(
      valueListenable: Settings.instance.textScale,
      builder: (context, current, _) {
        final entries = options.entries.toList();
        return Row(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              Expanded(
                child: _sizeChip(
                  entries[i].key,
                  entries[i].value,
                  current == entries[i].value,
                ),
              ),
              if (i < entries.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _navRow(
    BuildContext context,
    IconData icon,
    String label,
    Widget Function() screen,
  ) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => screen())),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cBorder),
        ),
        child: Row(
          children: [
            Icon(icon, color: cDim, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            const Icon(Icons.chevron_right, color: cDim, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _trustedDevicesSection() {
    return ValueListenableBuilder<Map<String, String>>(
      valueListenable: TrustStore.instance.tokens,
      builder: (context, tokens, _) {
        if (tokens.isEmpty) {
          return const Text(
            'Ninguno todavía. La primera vez que emparejes un dispositivo '
            'con el código, queda guardado aquí y no vuelve a pedírselo.',
            style: TextStyle(color: cDim, fontSize: 12, height: 1.4),
          );
        }
        final entries = tokens.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        return Column(
          children: [
            for (final e in entries) ...[
              _trustedDeviceRow(e.key, e.value),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _trustedDeviceRow(String token, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user, color: cAccent, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: cDim, size: 18),
            tooltip: 'Olvidar',
            onPressed: () => TrustStore.instance.forget(token),
          ),
        ],
      ),
    );
  }

  Widget _autoClipboardSection() {
    return ValueListenableBuilder<bool>(
      valueListenable: Settings.instance.autoClipboard,
      builder: (context, on, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Enviar el portapapeles automáticamente al copiar algo',
                  style:
                      TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
                ),
              ),
              Switch(
                value: on,
                activeThumbColor: cAccent,
                onChanged: (v) => Settings.instance.setAutoClipboard(v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isDesktop
                ? 'Sin tocar el botón: cada vez que copies texto o una imagen '
                    'se manda solo.'
                : 'Solo mientras la app está abierta: Android no deja leer el '
                    'portapapeles en 2º plano.',
            style: const TextStyle(color: cDim, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _autostartSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Iniciar sbox al encender el PC',
                style: TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
              ),
            ),
            Switch(
              value: _autostartOn,
              activeThumbColor: cAccent,
              onChanged: (v) async {
                setState(() => _autostartOn = v); // responde al toque ya
                await LinuxAutostart.setEnabled(v);
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Abre la cajita de sbox junto con tu sesión de escritorio.',
          style: TextStyle(color: cDim, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _autoDeleteSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: Settings.instance.autoDeleteImages,
          builder: (context, on, _) => Row(
            children: [
              const Expanded(
                child: Text(
                  'Borrar automáticamente las imágenes que llegan',
                  style:
                      TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
                ),
              ),
              Switch(
                value: on,
                activeThumbColor: cAccent,
                onChanged: (v) => Settings.instance.setAutoDeleteImages(v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // Selector de segundos: atenuado y sin efecto si el borrado está apagado.
        ValueListenableBuilder<bool>(
          valueListenable: Settings.instance.autoDeleteImages,
          builder: (context, on, _) => AnimatedOpacity(
            opacity: on ? 1 : 0.35,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(ignoring: !on, child: _secondsSelector()),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Solo imágenes, solo de la carpeta Descargas/sbox del PC. Pasado ese '
          'tiempo se borran; los demás archivos no se tocan.',
          style: TextStyle(color: cDim, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }

  Widget _secondsSelector() {
    const options = <String, int>{'15 s': 15, '30 s': 30, '60 s': 60};
    return ValueListenableBuilder<int>(
      valueListenable: Settings.instance.autoDeleteSeconds,
      builder: (context, current, _) {
        final entries = options.entries.toList();
        return Row(
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              Expanded(
                child: _secChip(
                  entries[i].key,
                  entries[i].value,
                  current == entries[i].value,
                ),
              ),
              if (i < entries.length - 1) const SizedBox(width: 8),
            ],
          ],
        );
      },
    );
  }

  Widget _secChip(String label, int value, bool selected) {
    return GestureDetector(
      onTap: () => Settings.instance.setAutoDeleteSeconds(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cAccent.withValues(alpha: selected ? 0.18 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cAccent.withValues(alpha: selected ? 0.6 : 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: fontMono,
            fontWeight: FontWeight.w700,
            color: selected ? cAccent : cDim,
          ),
        ),
      ),
    );
  }

  Widget _sizeChip(String label, double value, bool selected) {
    return GestureDetector(
      onTap: () => Settings.instance.setTextScale(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cAccent.withValues(alpha: selected ? 0.18 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cAccent.withValues(alpha: selected ? 0.6 : 0.18),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: fontMono,
            fontWeight: FontWeight.w700,
            color: selected ? cAccent : cDim,
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
    return Text(
      text,
      style: const TextStyle(
        fontFamily: fontMono,
        color: cDim,
        fontSize: 11,
        letterSpacing: 2,
      ),
    );
  }
}
