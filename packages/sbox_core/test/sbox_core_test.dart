import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_core/sbox_core.dart';

void main() {
  test('SboxMessage de texto hace round-trip por JSON', () {
    final decoded =
        SboxMessage.tryDecode(SboxMessage.text('hola').encode());
    expect(decoded!.type, SboxMsgType.text);
    expect(decoded.content, 'hola');
  });

  test('JSON inválido devuelve null', () {
    expect(SboxMessage.tryDecode('{no json'), isNull);
  });
}
