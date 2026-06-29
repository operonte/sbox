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

  static const _kScale = 'text_scale';
  static const _kName = 'device_name';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    textScale.value = p.getDouble(_kScale) ?? 1.0;
    deviceName.value = p.getString(_kName) ?? '';
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
}
