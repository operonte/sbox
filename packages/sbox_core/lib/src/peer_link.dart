import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'messages.dart';

/// Puerto fijo del host sbox (para poder conectarse escribiendo solo la IP).
const int kSboxPort = 47718;

enum PeerStatus { idle, listening, connecting, connected, rejected, error }

/// Estado del enlace entre las dos cajas.
class PeerState {
  const PeerState(this.status, {this.peerName, this.message, this.token});
  final PeerStatus status;
  final String? peerName;
  final String? message;

  /// Presente solo en [PeerStatus.connected]: token de confianza a guardar
  /// para que la próxima vez este dispositivo se reconecte sin pedir código.
  final String? token;

  static const idle = PeerState(PeerStatus.idle);
  static const listening = PeerState(PeerStatus.listening);
  static const connecting = PeerState(PeerStatus.connecting);
  static const reconnecting =
      PeerState(PeerStatus.connecting, message: 'Reconectando…');
  static const rejected =
      PeerState(PeerStatus.rejected, message: 'Código incorrecto');
  factory PeerState.connected(String name, {String? token}) =>
      PeerState(PeerStatus.connected, peerName: name, token: token);
  factory PeerState.error(String m) => PeerState(PeerStatus.error, message: m);
}

/// Interfaz común para host y cliente.
abstract class PeerLink {
  Stream<SboxMessage> get messages;

  /// Archivos completos recibidos (cabecera + bytes ya emparejados).
  Stream<ReceivedFile> get files;
  Stream<PeerState> get state;
  void send(SboxMessage message);

  /// Envía un archivo: una trama de cabecera (texto) y otra con los bytes.
  void sendFile(String name, List<int> bytes);
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
  SboxHost({
    required this.code,
    required this.deviceName,
    Set<String>? trustedTokens,
    this.onTrust,
  }) : _trustedTokens = {...?trustedTokens};

  final String code;
  final String deviceName;

  /// Se llama cuando un dispositivo queda (o sigue) emparejado, con el token
  /// a recordar y el nombre actual del dispositivo — para que la app lo
  /// persista y no vuelva a pedirle el código la próxima vez.
  final void Function(String token, String deviceName)? onTrust;

  final Set<String> _trustedTokens;
  String? _peerToken; // token con el que se autenticó el peer conectado ahora

  HttpServer? _server;
  WebSocket? _peer;
  SboxMessage? _pendingFile; // cabecera a la espera de su trama binaria
  final _messages = StreamController<SboxMessage>.broadcast();
  final _files = StreamController<ReceivedFile>.broadcast();
  final _state = StreamController<PeerState>.broadcast();

  /// Reemplaza el conjunto de tokens de confianza (p. ej. tras "olvidar" un
  /// dispositivo en Configuración). Si el peer conectado ahora mismo usaba un
  /// token que ya no es de confianza, se le desconecta.
  void updateTrustedTokens(Set<String> tokens) {
    _trustedTokens
      ..clear()
      ..addAll(tokens);
    if (_peerToken != null && !_trustedTokens.contains(_peerToken)) {
      _peer?.close();
    }
  }

  String _newToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Stream<SboxMessage> get messages => _messages.stream;
  @override
  Stream<ReceivedFile> get files => _files.stream;
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
    // Ping/pong automático: mantiene viva la conexión y detecta caídas reales
    // (si el teléfono desaparece sin cerrar, el socket se cierra solo).
    ws.pingInterval = const Duration(seconds: 10);
    _log('teléfono abrió el socket; esperando código…');
    ws.listen(
      (raw) {
        // Trama binaria: son los bytes del archivo cuya cabecera ya llegó.
        if (raw is! String) {
          _absorbBinary(raw);
          return;
        }
        final msg = SboxMessage.tryDecode(raw);
        if (msg == null) return;
        if (msg.type == SboxMsgType.hello) {
          final incoming = msg.device ?? 'dispositivo';
          String token;
          if (msg.token != null && _trustedTokens.contains(msg.token)) {
            // Dispositivo ya conocido: entra sin pedirle el código.
            token = msg.token!;
            _log('EMPAREJADO (conocido) con $incoming');
          } else if (msg.code == code) {
            // Primera vez (o token olvidado): valida el código y le da uno
            // nuevo para que no vuelva a pedírselo.
            token = _newToken();
            _trustedTokens.add(token);
            _log('EMPAREJADO (nuevo) con $incoming');
          } else {
            _log('código equivocado: "${msg.code}" (esperaba "$code")');
            ws.add(SboxMessage.welcome(ok: false).encode());
            ws.close();
            return;
          }
          _peerToken = token;
          onTrust?.call(token, incoming);
          ws.add(
            SboxMessage.welcome(ok: true, device: deviceName, token: token)
                .encode(),
          );
          _state.add(PeerState.connected(incoming));
        } else if (msg.type == SboxMsgType.text) {
          _log('texto recibido (${msg.content?.length ?? 0} chars)');
          _messages.add(msg);
        } else if (msg.type == SboxMsgType.fileHeader) {
          _pendingFile = msg; // los bytes vienen en la siguiente trama
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

  /// Empareja una trama binaria con la última cabecera de archivo recibida.
  void _absorbBinary(dynamic raw) {
    final header = _pendingFile;
    _pendingFile = null;
    if (header == null) return;
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    // A prueba de fallos: si los bytes no coinciden con el tamaño anunciado,
    // el archivo llegó truncado/desincronizado → se descarta (no se guarda
    // algo corrupto haciéndolo pasar por completo).
    if (header.size > 0 && bytes.length != header.size) {
      _log('archivo descartado: ${header.name} (${bytes.length} de '
          '${header.size} bytes)');
      return;
    }
    _log('archivo recibido: ${header.name} (${bytes.length} bytes)');
    _files.add(ReceivedFile(name: header.name ?? 'archivo', bytes: bytes));
  }

  void _log(String m) {
    // ignore: avoid_print
    print('[sbox-host] $m');
  }

  void _onPeerGone() {
    _peer = null;
    _peerToken = null;
    _pendingFile = null;
    if (!_state.isClosed) _state.add(PeerState.listening);
  }

  @override
  void send(SboxMessage message) => _peer?.add(message.encode());

  @override
  void sendFile(String name, List<int> bytes) {
    _peer?.add(SboxMessage.fileHeader(name: name, size: bytes.length).encode());
    _peer?.add(bytes);
  }

  @override
  Future<void> dispose() async {
    await _peer?.close();
    await _server?.close(force: true);
    await _messages.close();
    await _files.close();
    await _state.close();
  }
}

/// El cliente (el teléfono): se conecta al host por IP y envía el código.
class SboxClient implements PeerLink {
  SboxClient({required this.deviceName});

  final String deviceName;

  WebSocket? _ws;
  SboxMessage? _pendingFile; // cabecera a la espera de su trama binaria

  // Reconexión: recuerda a quién estaba conectado y reintenta si se cae.
  String? _host;
  String? _code;
  String? _token;
  int _port = kSboxPort;
  bool _wasConnected = false;
  bool _rejected = false;
  bool _disposed = false;
  bool _opening = false; // hay un intento de conexión en curso
  int _retries = 0;
  Timer? _reconnectTimer;

  final _messages = StreamController<SboxMessage>.broadcast();
  final _files = StreamController<ReceivedFile>.broadcast();
  final _state = StreamController<PeerState>.broadcast();

  @override
  Stream<SboxMessage> get messages => _messages.stream;
  @override
  Stream<ReceivedFile> get files => _files.stream;
  @override
  Stream<PeerState> get state => _state.stream;

  /// [token]: si ya emparejamos antes con este host, el token que nos dio la
  /// última vez — así entra directo, sin pedir [code].
  Future<void> connect(
    String host, {
    String code = '',
    String? token,
    int port = kSboxPort,
  }) async {
    _reconnectTimer?.cancel(); // evita un reintento pendiente en paralelo
    _host = host;
    _code = code;
    _token = token;
    _port = port;
    _wasConnected = false;
    _rejected = false;
    _retries = 0;
    await _open();
  }

  /// Abre (o reabre) el socket usando los últimos datos de conexión.
  Future<void> _open() async {
    if (_disposed || _host == null || _code == null || _opening) return;
    _opening = true;
    _state.add(_wasConnected ? PeerState.reconnecting : PeerState.connecting);
    try {
      final ws = await WebSocket.connect('ws://$_host:$_port')
          .timeout(const Duration(seconds: 6));
      _opening = false;
      ws.pingInterval = const Duration(seconds: 10);
      _ws = ws;
      ws.add(
        SboxMessage.hello(code: _code ?? '', device: deviceName, token: _token)
            .encode(),
      );
      ws.listen(
        (raw) {
          // Trama binaria: bytes del archivo cuya cabecera ya llegó.
          if (raw is! String) {
            _absorbBinary(raw);
            return;
          }
          final msg = SboxMessage.tryDecode(raw);
          if (msg == null) return;
          if (msg.type == SboxMsgType.welcome) {
            if (!msg.ok) {
              _rejected = true; // código incorrecto: no reintentar
              _state.add(PeerState.rejected);
              ws.close();
              return;
            }
            _wasConnected = true;
            _retries = 0;
            _token = msg.token ?? _token;
            _state.add(PeerState.connected(msg.device ?? 'PC', token: _token));
          } else if (msg.type == SboxMsgType.fileHeader) {
            _pendingFile = msg;
          } else if (msg.type != SboxMsgType.ping) {
            _messages.add(msg);
          }
        },
        onDone: _onGone,
        onError: (_) => _onGone(),
        cancelOnError: true,
      );
    } on TimeoutException {
      _opening = false;
      _onConnectFailure('No respondió (¿IP correcta? ¿misma WiFi?)');
    } catch (e) {
      _opening = false;
      _onConnectFailure('No se pudo conectar');
    }
  }

  /// Fuerza un reintento inmediato sin esperar el backoff (p. ej. cuando vuelve
  /// la red o la app al primer plano). Solo actúa si ya habíamos emparejado y no
  /// hay ya un socket vivo ni un intento en curso.
  void reconnectNow() {
    if (_disposed || _rejected || !_wasConnected) return;
    if (_ws != null || _opening) return;
    _reconnectTimer?.cancel();
    _retries = 0;
    _open();
  }

  /// Falló al abrir el socket: si ya habíamos estado conectados, reintenta;
  /// si es el primer intento, muestra el error para que el usuario corrija.
  void _onConnectFailure(String msg) {
    if (_wasConnected) {
      _scheduleReconnect();
    } else if (!_state.isClosed) {
      _state.add(PeerState.error(msg));
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    // Nunca se rinde solo: reintenta indefinidamente con backoff hasta 10 s.
    // Así una caída de WiFi de varios minutos se recupera sola al volver (solo
    // el botón rojo de salir corta de verdad). Ver también [reconnectNow].
    _retries++;
    final secs = _retries < 10 ? _retries : 10; // 1,2,…,10,10… segundos
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: secs), _open);
  }

  /// Empareja una trama binaria con la última cabecera de archivo recibida.
  void _absorbBinary(dynamic raw) {
    final header = _pendingFile;
    _pendingFile = null;
    if (header == null) return;
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    // A prueba de fallos: descarta el archivo si los bytes no coinciden con el
    // tamaño anunciado (llegó truncado o desincronizado).
    if (header.size > 0 && bytes.length != header.size) return;
    _files.add(ReceivedFile(name: header.name ?? 'archivo', bytes: bytes));
  }

  void _onGone() {
    _ws = null;
    _pendingFile = null;
    if (_disposed || _rejected) return;
    if (_wasConnected) {
      // Caída tras haber estado conectado: avisar y reintentar solo.
      if (!_state.isClosed) _state.add(PeerState.reconnecting);
      _scheduleReconnect();
    } else if (!_state.isClosed) {
      _state.add(PeerState.idle);
    }
  }

  @override
  void send(SboxMessage message) => _ws?.add(message.encode());

  @override
  void sendFile(String name, List<int> bytes) {
    _ws?.add(SboxMessage.fileHeader(name: name, size: bytes.length).encode());
    _ws?.add(bytes);
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _ws?.close();
    await _messages.close();
    await _files.close();
    await _state.close();
  }
}
