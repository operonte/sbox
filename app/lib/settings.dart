import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ajustes persistentes de sbox (tamaño de texto, nombre del dispositivo).
class Settings {
  Settings._();
  static final Settings instance = Settings._();

  /// Escala de texto aplicada a toda la app (1× … 4×).
  final ValueNotifier<double> textScale = ValueNotifier<double>(1.0);

  /// Nombre con el que este dispositivo se anuncia al emparejar.
  final ValueNotifier<String> deviceName = ValueNotifier<String>('');

  /// Borrar automáticamente las imágenes recibidas de la carpeta sbox del PC
  /// pasados unos segundos (portapapeles efímero). Solo aplica en escritorio.
  final ValueNotifier<bool> autoDeleteImages = ValueNotifier<bool>(true);

  /// Segundos antes de borrar una imagen recibida (si [autoDeleteImages]).
  final ValueNotifier<int> autoDeleteSeconds = ValueNotifier<int>(30);

  static const _kScale = 'text_scale';
  static const _kName = 'device_name';
  static const _kAutoDel = 'auto_delete_images';
  static const _kAutoDelSecs = 'auto_delete_seconds';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    textScale.value = p.getDouble(_kScale) ?? 1.0;
    deviceName.value = p.getString(_kName) ?? '';
    autoDeleteImages.value = p.getBool(_kAutoDel) ?? true;
    autoDeleteSeconds.value = p.getInt(_kAutoDelSecs) ?? 30;
  }

  Future<void> setTextScale(double value) async {
    textScale.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kScale, value);
  }

  Future<void> setDeviceName(String value) async {
    deviceName.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, value);
  }

  Future<void> setAutoDeleteImages(bool value) async {
    autoDeleteImages.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoDel, value);
  }

  Future<void> setAutoDeleteSeconds(int value) async {
    autoDeleteSeconds.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kAutoDelSecs, value);
  }
}
