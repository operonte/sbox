import 'dart:io';

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

  test('fileHeader y fileProgress hacen round-trip por JSON', () {
    final header = SboxMessage.tryDecode(
      SboxMessage.fileHeader(name: 'foto.png', size: 2048).encode(),
    );
    expect(header!.type, SboxMsgType.fileHeader);
    expect(header.name, 'foto.png');
    expect(header.size, 2048);

    final progress = SboxMessage.tryDecode(
      SboxMessage.fileProgress(received: 1024).encode(),
    );
    expect(progress!.type, SboxMsgType.fileProgress);
    expect(progress.received, 1024);
  });

  test('clear hace round-trip por JSON', () {
    final decoded = SboxMessage.tryDecode(SboxMessage.clear().encode());
    expect(decoded!.type, SboxMsgType.clear);
  });

  test('un archivo de 0 bytes termina la transferencia (no se cuelga en 0%)',
      () async {
    // Regresión: antes, un archivo vacío nunca mandaba ningún pedazo binario
    // y el receptor se quedaba esperando el fin para siempre.
    final empty = await File(
      '${Directory.systemTemp.path}/sbox_test_empty_${DateTime.now().microsecondsSinceEpoch}.opus',
    ).create();
    addTearDown(() => empty.delete());

    final host = SboxHost(code: '000000', deviceName: 'PC');
    final client = SboxClient(deviceName: 'Android');
    addTearDown(() async {
      await host.dispose();
      await client.dispose();
    });

    final port = await host.start(port: 0);
    final connected = host.state.firstWhere((s) => s.status == PeerStatus.connected);
    await client.connect('127.0.0.1', code: '000000', port: port);
    await connected;

    final finished = client.fileEvents.firstWhere((e) => e is FileFinished);
    await host.sendFile('vacio.opus', empty);

    final result = await finished.timeout(const Duration(seconds: 5));
    expect((result as FileFinished).ok, isTrue);
  });
}
