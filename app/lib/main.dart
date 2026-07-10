import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'platform.dart';
import 'sbox_home.dart';
import 'settings.dart';
import 'theme.dart';
import 'tray.dart';
import 'window_state.dart';

/// sbox — portapapeles universal PC ↔ Android por la misma WiFi, sin servidor.

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.instance.load();
  await TrustStore.instance.load();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      minimumSize: Size(300, 360),
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: true,
    );
    // --tray: arranque automático con el sistema (ver autostart.dart) — se
    // queda solo en la bandeja, sin mostrar la caja encima de todo al
    // iniciar sesión.
    final startHidden = args.contains('--tray');
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await windowManager.setResizable(true);
      try {
        await windowManager.setHasShadow(false);
      } catch (_) {}
      await windowManager.setAlwaysOnTop(true);
      // Posición/tamaño: última guardada, o esquina superior izquierda.
      await WindowState.restoreOrDefault();
      if (!startHidden) {
        await windowManager.show();
        await windowManager.focus();
      }
    });
    windowManager.addListener(WindowStateSaver());
    await SboxTray().init();
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
        fontFamily: fontMono,
        colorScheme: ColorScheme.fromSeed(
          seedColor: cAccent,
          brightness: Brightness.dark,
        ),
      ),
      // Escala de texto global ajustable desde Configuración (1×…4×).
      builder: (context, child) {
        return ValueListenableBuilder<double>(
          valueListenable: Settings.instance.textScale,
          builder: (context, scale, _) {
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            );
          },
        );
      },
      home: const SboxHome(),
    );
  }
}
