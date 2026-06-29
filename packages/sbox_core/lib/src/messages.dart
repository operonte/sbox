import 'dart:convert';

/// Tipos de mensaje del protocolo sbox (texto, por ahora).
enum SboxMsgType { hello, welcome, text, ping }

/// Mensaje que viaja por el canal entre las dos cajas. Se serializa como JSON.
class SboxMessage {
  SboxMessage(this.type, [this.data = const {}]);

  final SboxMsgType type;
  final Map<String, dynamic> data;

  /// Texto compartido (lo que se "copia" entre dispositivos).
  factory SboxMessage.text(String content) =>
      SboxMessage(SboxMsgType.text, {'content': content});

  /// El cliente saluda al host con el código de emparejamiento.
  factory SboxMessage.hello({required String code, required String device}) =>
      SboxMessage(SboxMsgType.hello, {'code': code, 'device': device});

  /// El host acepta (ok=true) o rechaza (ok=false) al cliente.
  factory SboxMessage.welcome({required bool ok, String? device}) =>
      SboxMessage(SboxMsgType.welcome, {'ok': ok, 'device': ?device});

  String? get content => data['content'] as String?;
  String? get code => data['code'] as String?;
  String? get device => data['device'] as String?;
  bool get ok => data['ok'] == true;

  String encode() => jsonEncode({'type': type.name, ...data});

  /// Decodifica de forma tolerante: devuelve null si el JSON es inválido.
  static SboxMessage? tryDecode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final type = SboxMsgType.values.firstWhere(
        (t) => t.name == decoded['type'],
        orElse: () => SboxMsgType.ping,
      );
      final data = Map<String, dynamic>.from(decoded)..remove('type');
      return SboxMessage(type, data);
    } catch (_) {
      return null;
    }
  }
}
