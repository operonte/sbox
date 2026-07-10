import 'dart:io';

/// Arranque automático de sbox al iniciar sesión en Linux (estándar XDG
/// autostart: un .desktop en ~/.config/autostart). El estado "activado" es
/// simplemente si ese archivo existe — sin duplicarlo en shared_preferences,
/// para que no se desincronice si alguien lo borra a mano.
class LinuxAutostart {
  LinuxAutostart._();

  static String? get _home => Platform.environment['HOME'];
  static String? get _dir =>
      _home == null ? null : '$_home/.config/autostart';
  static String? get _file => _dir == null ? null : '$_dir/sbox.desktop';

  static Future<bool> isEnabled() async {
    final file = _file;
    if (file == null) return false;
    return File(file).exists();
  }

  static Future<void> setEnabled(bool enabled) async {
    final file = _file;
    if (file == null) return;
    if (!enabled) {
      final f = File(file);
      if (await f.exists()) await f.delete();
      return;
    }
    final dir = Directory(_dir!);
    if (!await dir.exists()) await dir.create(recursive: true);
    final exe = Platform.resolvedExecutable;
    final iconPath = '${File(exe).parent.path}/sbox_icon.png';
    final icon = await File(iconPath).exists() ? iconPath : 'sbox';
    // --tray: al iniciar con el sistema, se queda en la bandeja en vez de
    // mostrar la caja encima de todo (ver tray.dart / main.dart).
    await File(file).writeAsString('''
[Desktop Entry]
Type=Application
Name=sbox
Comment=Portapapeles universal entre PC y Android por la misma WiFi
Exec=$exe --tray
Icon=$icon
Terminal=false
X-GNOME-Autostart-enabled=true
''');
  }
}
