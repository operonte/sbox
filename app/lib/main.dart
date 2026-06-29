import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// sbox — portapapeles universal PC ↔ Android por red local, sin nube.
/// La misma UI corre en escritorio (caja flotante) y en Android.

const _card = Color(0xFF14151A); // superficie de la caja
const _accent = Color(0xFF3B82F6); // azul eléctrico
const _dim = Color(0xFF8A8F98); // texto secundario
const _border = Color(0x14FFFFFF); // borde sutil (blanco ~8%)
const _mono = 'monospace';

/// window_manager (caja flotante frameless/translúcida/always-on-top) solo
/// aplica en escritorio. En Android la app corre normal a pantalla completa.
bool get isDesktop =>
    !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(360, 440),
      minimumSize: Size(300, 360),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      try {
        await windowManager.setHasShadow(false);
      } catch (_) {}
      await windowManager.setAlwaysOnTop(true);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const SboxApp());
}

class SboxApp extends StatelessWidget {
  const SboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: _mono,
      ),
      home: const FloatingBox(),
    );
  }
}

class FloatingBox extends StatelessWidget {
  const FloatingBox({super.key});

  @override
  Widget build(BuildContext context) {
    // Fondo transparente: solo se pinta la tarjeta redondeada translúcida.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
            decoration: BoxDecoration(
              color: _card.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _border),
            ),
            child: const Column(
              children: [
                _Header(),
                Expanded(child: _DropZone()),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _SyncButton(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'SBOX',
            style: TextStyle(
              fontFamily: _mono,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          // El botón de cerrar solo tiene sentido en la caja de escritorio.
          if (isDesktop)
            _IconBtn(icon: Icons.close, onTap: () => windowManager.close()),
        ],
      ),
    );

    // En escritorio, arrastrar la cabecera mueve la ventana flotante.
    return isDesktop ? DragToMoveArea(child: header) : header;
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 18, color: _dim),
      ),
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.block, color: _dim, size: 22),
          ),
          const SizedBox(height: 14),
          const Text(
            'Portapapeles\nvacío',
            textAlign: TextAlign.center,
            style: TextStyle(color: _dim, fontSize: 14, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _SyncButton extends StatelessWidget {
  const _SyncButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _accent.withValues(alpha: 0.45)),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {},
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 13),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.sync, size: 16, color: _accent),
                  SizedBox(width: 8),
                  Text(
                    'Sincronizar',
                    style: TextStyle(
                      fontFamily: _mono,
                      color: _accent,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
