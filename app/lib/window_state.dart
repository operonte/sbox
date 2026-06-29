import 'dart:ui' show Rect, Size;

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
    await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
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
