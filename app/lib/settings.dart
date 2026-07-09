import 'dart:convert';

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

  /// Enviar el portapapeles automáticamente al detectar un cambio, sin
  /// esperar a que toquen el botón. Aplica a texto e imagen (PC) o solo
  /// texto (Android, por la restricción del sistema en 2º plano).
  final ValueNotifier<bool> autoClipboard = ValueNotifier<bool>(true);

  static const _kScale = 'text_scale';
  static const _kName = 'device_name';
  static const _kAutoDel = 'auto_delete_images';
  static const _kAutoDelSecs = 'auto_delete_seconds';
  static const _kAutoClipboard = 'auto_clipboard';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    textScale.value = p.getDouble(_kScale) ?? 1.0;
    deviceName.value = p.getString(_kName) ?? '';
    autoDeleteImages.value = p.getBool(_kAutoDel) ?? true;
    autoDeleteSeconds.value = p.getInt(_kAutoDelSecs) ?? 30;
    autoClipboard.value = p.getBool(_kAutoClipboard) ?? true;
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

  Future<void> setAutoClipboard(bool value) async {
    autoClipboard.value = value;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoClipboard, value);
  }
}

/// Dispositivos "de confianza": una vez emparejados por código, se
/// reconectan solos sin volver a pedirlo. Clave = token (estable), valor =
/// último nombre visto de ese dispositivo (solo para mostrarlo en la lista).
class TrustStore {
  TrustStore._();
  static final TrustStore instance = TrustStore._();

  final ValueNotifier<Map<String, String>> tokens =
      ValueNotifier<Map<String, String>>({});

  static const _kKey = 'trusted_tokens';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_kKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      tokens.value = decoded.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      // Datos corruptos: seguimos sin dispositivos de confianza.
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kKey, jsonEncode(tokens.value));
  }

  /// Token guardado para un dispositivo ya visto con este [label], si lo hay.
  String? tokenFor(String label) {
    for (final e in tokens.value.entries) {
      if (e.value == label) return e.key;
    }
    return null;
  }

  /// El otro lado confirmó (o reconfirmó) un [token] para [label]: se guarda.
  Future<void> remember(String token, String label) async {
    if (tokens.value[token] == label) return; // ya estaba, nada que hacer
    tokens.value = {...tokens.value, token: label};
    await _save();
  }

  Future<void> forget(String token) async {
    if (!tokens.value.containsKey(token)) return;
    final next = {...tokens.value}..remove(token);
    tokens.value = next;
    await _save();
  }
}
