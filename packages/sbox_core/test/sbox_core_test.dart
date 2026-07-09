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

  test('hello/welcome llevan el token de confianza por JSON', () {
    final hello = SboxMessage.tryDecode(
      SboxMessage.hello(code: '123456', device: 'Android', token: 'abc')
          .encode(),
    );
    expect(hello!.code, '123456');
    expect(hello.token, 'abc');

    final welcomeSinToken = SboxMessage.tryDecode(
      SboxMessage.welcome(ok: true, device: 'PC').encode(),
    );
    expect(welcomeSinToken!.token, isNull);

    final welcomeConToken = SboxMessage.tryDecode(
      SboxMessage.welcome(ok: true, device: 'PC', token: 'xyz').encode(),
    );
    expect(welcomeConToken!.token, 'xyz');
  });
}
