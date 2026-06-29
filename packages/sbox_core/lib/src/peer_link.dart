import 'dart:async';
import 'dart:io';

import 'messages.dart';

/// Puerto fijo del host sbox (para poder conectarse escribiendo solo la IP).
const int kSboxPort = 47718;

enum PeerStatus { idle, listening, connecting, connected, rejected, error }

/// Estado del enlace entre las dos cajas.
class PeerState {
  const PeerState(this.status, {this.peerName, this.message});
  final PeerStatus status;
  final String? peerName;
  final String? message;

  static const idle = PeerState(PeerStatus.idle);
  static const listening = PeerState(PeerStatus.listening);
  static const connecting = PeerState(PeerStatus.connecting);
  static const rejected =
      PeerState(PeerStatus.rejected, message: 'Código incorrecto');
  factory PeerState.connected(String name) =>
      PeerState(PeerStatus.connected, peerName: name);
  factory PeerState.error(String m) => PeerState(PeerStatus.error, message: m);
}

/// Interfaz común para host y cliente.
abstract class PeerLink {
  Stream<SboxMessage> get messages;
  Stream<PeerState> get state;
  void send(SboxMessage message);
  Future<void> dispose();
}

/// Direcciones IPv4 locales no-loopback (para mostrarlas en la caja de PC).
Future<List<String>> localIPv4() async {
  final result = <String>[];
  final ifaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
    includeLinkLocal: false,
  );
  for (final iface in ifaces) {
    for (final addr in iface.addresses) {
      result.add(addr.address);
    }
  }
  return result;
}

/// El host (la PC): levanta un servidor WebSocket en la LAN y atiende a un
/// único cliente. Valida el código de emparejamiento (decorativo).
class SboxHost implements PeerLink {
  SboxHost({required this.code, required this.deviceName});

  final String code;
  final String deviceName;

  HttpServer? _server;
  WebSocket? _peer;
  final _messages = StreamController<SboxMessage>.broadcast();
  final _state = StreamController<PeerState>.broadcast();

  @override
  Stream<SboxMessage> get messages => _messages.stream;
  @override
  Stream<PeerState> get state => _state.stream;

  /// Arranca el servidor. Devuelve el puerto usado.
  Future<int> start({int port = kSboxPort}) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _log('host escuchando en 0.0.0.0:${_server!.port} (código $code)');
    _state.add(PeerState.listening);
    _server!.listen((req) async {
      if (!WebSocketTransformer.isUpgradeRequest(req)) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      final ws = await WebSocketTransformer.upgrade(req);
      _attach(ws);
    });
    return _server!.port;
  }

  void _attach(WebSocket ws) {
    _peer?.close();
    _peer = ws;
    _log('teléfono abrió el socket; esperando código…');
    ws.listen(
      (raw) {
        final msg = SboxMessage.tryDecode(raw as String);
        if (msg == null) return;
        if (msg.type == SboxMsgType.hello) {
          if (msg.code != code) {
            _log('código equivocado: "${msg.code}" (esperaba "$code")');
            ws.add(SboxMessage.welcome(ok: false).encode());
            ws.close();
            return;
          }
          _log('EMPAREJADO con ${msg.device}');
          ws.add(SboxMessage.welcome(ok: true, device: deviceName).encode());
          _state.add(PeerState.connected(msg.device ?? 'dispositivo'));
        } else if (msg.type == SboxMsgType.text) {
          _log('texto recibido (${msg.content?.length ?? 0} chars)');
          _messages.add(msg);
        } else if (msg.type != SboxMsgType.ping) {
          _messages.add(msg);
        }
      },
      onDone: () {
        _log('teléfono desconectado');
        _onPeerGone();
      },
      onError: (e) {
        _log('error de socket: $e');
        _onPeerGone();
      },
      cancelOnError: true,
    );
  }

  void _log(String m) {
    // ignore: avoid_print
    print('[sbox-host] $m');
  }

  void _onPeerGone() {
    _peer = null;
    if (!_state.isClosed) _state.add(PeerState.listening);
  }

  @override
  void send(SboxMessage message) => _peer?.add(message.encode());

  @override
  Future<void> dispose() async {
    await _peer?.close();
    await _server?.close(force: true);
    await _messages.close();
    await _state.close();
  }
}

/// El cliente (el teléfono): se conecta al host por IP y envía el código.
class SboxClient implements PeerLink {
  SboxClient({required this.deviceName});

  final String deviceName;

  WebSocket? _ws;
  final _messages = StreamController<SboxMessage>.broadcast();
  final _state = StreamController<PeerState>.broadcast();

  @override
  Stream<SboxMessage> get messages => _messages.stream;
  @override
  Stream<PeerState> get state => _state.stream;

  Future<void> connect(
    String host, {
    required String code,
    int port = kSboxPort,
  }) async {
    _state.add(PeerState.connecting);
    try {
      final ws = await WebSocket.connect('ws://$host:$port')
          .timeout(const Duration(seconds: 6));
      _ws = ws;
      ws.add(SboxMessage.hello(code: code, device: deviceName).encode());
      ws.listen(
        (raw) {
          final msg = SboxMessage.tryDecode(raw as String);
          if (msg == null) return;
          if (msg.type == SboxMsgType.welcome) {
            if (!msg.ok) {
              _state.add(PeerState.rejected);
              ws.close();
              return;
            }
            _state.add(PeerState.connected(msg.device ?? 'PC'));
          } else if (msg.type != SboxMsgType.ping) {
            _messages.add(msg);
          }
        },
        onDone: _onGone,
        onError: (_) => _onGone(),
        cancelOnError: true,
      );
    } on TimeoutException {
      _state.add(PeerState.error('No respondió (¿IP correcta? ¿misma WiFi?)'));
    } catch (e) {
      _state.add(PeerState.error('No se pudo conectar'));
    }
  }

  void _onGone() {
    _ws = null;
    if (!_state.isClosed) _state.add(PeerState.idle);
  }

  @override
  void send(SboxMessage message) => _ws?.add(message.encode());

  @override
  Future<void> dispose() async {
    await _ws?.close();
    await _messages.close();
    await _state.close();
  }
}
