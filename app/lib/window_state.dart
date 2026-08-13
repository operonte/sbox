import 'dart:ui' show PlatformDispatcher, Rect, Size;

import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// Posición/tamaño de la caja de escritorio: por defecto en la esquina
/// superior izquierda, recordando dónde y de qué tamaño la dejó el usuario.
class WindowState {
  static const _margin = 16.0;
  static const _defaultSize = Size(360, 480);
  static const _kx = 'win_x', _ky = 'win_y', _kw = 'win_w', _kh = 'win_h';

  /// Restaura la última posición/tamaño guardados; si no hay, esquina
  /// superior izquierda con un margen.
  static Future<void> restoreOrDefault() async {
    final prefs = await SharedPreferences.getInstance();
    final w = prefs.getDouble(_kw) ?? _defaultSize.width;
    final h = prefs.getDouble(_kh) ?? _defaultSize.height;
    final x = prefs.getDouble(_kx) ?? _margin;
    final y = prefs.getDouble(_ky) ?? _margin;
    final saved = Rect.fromLTWH(x, y, w, h);
    // Los bounds guardados pueden apuntar fuera de la pantalla actual (p. ej.
    // se guardaron con un monitor externo que ya no está conectado). Sin este
    // chequeo, la caja —sin bordes ni entrada en la barra de tareas— abriría
    // fuera del área visible y no habría forma de recuperarla salvo borrando
    // la configuración a mano.
    final bounds = _withinScreen(saved)
        ? saved
        : Rect.fromLTWH(_margin, _margin, _defaultSize.width, _defaultSize.height);
    await windowManager.setBounds(bounds);
  }

  /// true si [bounds] cae, al menos parcialmente, dentro del área visible de
  /// la pantalla principal (alcanza con que una esquina sea alcanzable).
  static bool _withinScreen(Rect bounds) {
    final display = PlatformDispatcher.instance.views.first.display;
    final ratio = display.devicePixelRatio;
    final screen = Rect.fromLTWH(
      0, 0, display.size.width / ratio, display.size.height / ratio,
    );
    return screen.overlaps(bounds);
  }

  /// Guarda la posición/tamaño actuales (se llama al mover/redimensionar).
  static Future<void> save() async {
    final bounds = await windowManager.getBounds();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kx, bounds.left);
    await prefs.setDouble(_ky, bounds.top);
    await prefs.setDouble(_kw, bounds.width);
    await prefs.setDouble(_kh, bounds.height);
  }
}

/// Escucha movimientos/redimensiones de la ventana y persiste el estado.
class WindowStateSaver with WindowListener {
  @override
  void onWindowMoved() => WindowState.save();

  @override
  void onWindowResized() => WindowState.save();
}
