import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_core/sbox_core.dart';

void main() {
  test('SboxMessage de texto hace round-trip por JSON', () {
    final original = SboxMessage.text('hola desde la PC');
    final decoded = SboxMessage.tryDecode(original.encode());

    expect(decoded, isNotNull);
    expect(decoded!.type, SboxMsgType.text);
    expect(decoded.content, 'hola desde la PC');
  });

  test('hello transporta código y dispositivo', () {
    final decoded = SboxMessage.tryDecode(
      SboxMessage.hello(code: '482193', device: 'Android').encode(),
    );

    expect(decoded!.type, SboxMsgType.hello);
    expect(decoded.code, '482193');
    expect(decoded.device, 'Android');
  });

  test('welcome lleva el flag ok', () {
    final ok = SboxMessage.tryDecode(SboxMessage.welcome(ok: true).encode());
    final no = SboxMessage.tryDecode(SboxMessage.welcome(ok: false).encode());

    expect(ok!.ok, isTrue);
    expect(no!.ok, isFalse);
  });

  test('JSON inválido devuelve null en vez de lanzar', () {
    expect(SboxMessage.tryDecode('no soy json'), isNull);
  });
}
