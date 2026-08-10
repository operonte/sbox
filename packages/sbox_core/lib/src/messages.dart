import 'dart:convert';

/// Tipos de mensaje del protocolo sbox.
/// `fileHeader` es una trama de texto (nombre + tamaño) que precede a varias
/// tramas binarias con los bytes del archivo, en pedazos. `fileProgress` es
/// el acuse que manda quien RECIBE de vuelta a quien envía, con cuánto lleva
/// acumulado — así el emisor puede mostrar un % real, no adivinado.
enum SboxMsgType { hello, welcome, text, fileHeader, fileProgress, ping }

/// Mensaje que viaja por el canal entre las dos cajas. Se serializa como JSON.
class SboxMessage {
  SboxMessage(this.type, [this.data = const {}]);

  final SboxMsgType type;
  final Map<String, dynamic> data;

  /// Texto compartido (lo que se "copia" entre dispositivos). Lleva el
  /// momento en que este dispositivo detectó la copia (`copiedAt`, epoch ms)
  /// para que el otro lado sepa si esto es más nuevo que lo que ya tiene —
  /// así se resuelve quién manda cuando PC y celular copian casi a la vez.
  factory SboxMessage.text(String content) => SboxMessage(SboxMsgType.text, {
        'content': content,
        'copiedAt': DateTime.now().millisecondsSinceEpoch,
      });

  /// El cliente saluda al host con el código de emparejamiento, o con el
  /// [token] que le dieron la vez anterior si ya es un dispositivo conocido
  /// (en ese caso [code] puede ir vacío).
  factory SboxMessage.hello({
    required String code,
    required String device,
    String? token,
  }) =>
      SboxMessage(
        SboxMsgType.hello,
        {'code': code, 'device': device, 'token': ?token},
      );

  /// El host acepta (ok=true) o rechaza (ok=false) al cliente. Si acepta,
  /// [token] es el que el cliente debe guardar y reenviar la próxima vez
  /// para no tener que volver a pedir el código.
  factory SboxMessage.welcome({required bool ok, String? device, String? token}) =>
      SboxMessage(SboxMsgType.welcome, {'ok': ok, 'device': ?device, 'token': ?token});

  /// Cabecera que anuncia un archivo; las siguientes tramas binarias serán
  /// sus bytes, en pedazos, hasta completar [size].
  factory SboxMessage.fileHeader({required String name, required int size}) =>
      SboxMessage(SboxMsgType.fileHeader, {'name': name, 'size': size});

  /// Acuse de recepción parcial de un archivo en curso.
  factory SboxMessage.fileProgress({required int received}) =>
      SboxMessage(SboxMsgType.fileProgress, {'received': received});

  String? get content => data['content'] as String?;
  String? get code => data['code'] as String?;
  String? get device => data['device'] as String?;
  String? get token => data['token'] as String?;
  String? get name => data['name'] as String?;
  int get size => (data['size'] as num?)?.toInt() ?? 0;
  int get copiedAt => (data['copiedAt'] as num?)?.toInt() ?? 0;
  int get received => (data['received'] as num?)?.toInt() ?? 0;
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
