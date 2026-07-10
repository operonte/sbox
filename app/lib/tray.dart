import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Ícono en la bandeja del sistema (Linux/COSMIC), como el que deja OBS al
/// minimizar. La app sigue conectada y funcionando aunque la ventana esté
/// oculta — ocultar no es cerrar. Clic (izq. o der.) abre el menú con
/// "Mostrar/ocultar" y "Salir" (la única forma real de terminar sbox).
class SboxTray with TrayListener {
  Future<void> init() async {
    trayManager.addListener(this);
    // El ícono vive junto al binario (lo copia scripts/install-linux.sh, o
    // está en la raíz del AppDir de la AppImage). Ruta absoluta: el propio
    // plugin la respeta tal cual en vez de buscarla dentro de flutter_assets.
    final iconPath =
        '${File(Platform.resolvedExecutable).parent.path}/sbox_icon.png';
    try {
      if (await File(iconPath).exists()) await trayManager.setIcon(iconPath);
    } catch (_) {
      // Sin ícono no hay bandeja visible, pero sbox sigue funcionando igual.
    }
    await trayManager.setToolTip('sbox');
    await trayManager.setContextMenu(
      Menu(items: [
        MenuItem(
          key: 'toggle',
          label: 'Mostrar / ocultar sbox',
          onClick: (_) => _toggle(),
        ),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: 'Salir', onClick: (_) => _quit()),
      ]),
    );
  }

  Future<void> _toggle() async {
    if (await windowManager.isVisible()) {
      await windowManager.hide();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }

  Future<void> _quit() async {
    await trayManager.destroy();
    await windowManager.close();
  }

  // En Linux el clic (izq. o der.) sobre el ícono normalmente ya abre el
  // menú de contexto solo; esto cubre el caso en que no lo haga.
  @override
  void onTrayIconMouseDown() => _toggle();

  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
}
