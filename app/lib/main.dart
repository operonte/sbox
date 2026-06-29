import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'platform.dart';
import 'sbox_home.dart';
import 'theme.dart';

/// sbox — portapapeles universal PC ↔ Android por la misma WiFi, sin servidor.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(360, 480),
      minimumSize: Size(320, 420),
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
        fontFamily: fontMono,
        colorScheme: ColorScheme.fromSeed(
          seedColor: cAccent,
          brightness: Brightness.dark,
        ),
      ),
      home: const SboxHome(),
    );
  }
}
