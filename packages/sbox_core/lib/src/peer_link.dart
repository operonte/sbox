import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'messages.dart';

/// Puerto fijo del host sbox (para poder conectarse escribiendo solo la IP).
const int kSboxPort = 47718;

/// Tamaño de cada pedazo al enviar un archivo: mantiene la memoria acotada
/// sin importar cuán grande sea el archivo (no se carga entero en RAM).
const int _kChunkSize = 256 * 1024;

/// Cada cuánto manda el receptor un acuse de progreso mientras llegan los
/// pedazos de un archivo — no uno por cada pedazo (un archivo de 2 GB son
/// miles de pedazos), alcanza con una actualización fluida para la UI.
const Duration _kProgressAckInterval = Duration(milliseconds: 250);

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

/// Eventos de un archivo entrante, en el orden en que ocurren: una cabecera,
/// varios pedazos de datos, y por último si se completó bien o no.
sealed class FileEvent {}

/// Llegó la cabecera de un archivo nuevo — antes de cualquier byte.
class FileStarted extends FileEvent {
  FileStarted(this.name, this.size);
  final String name;
  final int size;
}

/// Un pedazo de bytes del archivo actualmente en recepción.
class FileData extends FileEvent {
  FileData(this.bytes);
  final Uint8List bytes;
}

/// Terminó de llegar el archivo — [ok] es false si la conexión se cortó a
/// mitad de camino (archivo incompleto, hay que descartarlo).
class FileFinished extends FileEvent {
  FileFinished(this.ok);
  final bool ok;
}

/// Interfaz común para host y cliente.
abstract class PeerLink {
  Stream<SboxMessage> get messages;

  /// Eventos del archivo actualmente en recepción (cabecera → pedazos → fin).
  Stream<FileEvent> get fileEvents;
  Stream<PeerState> get state;

  /// Progreso (0.0–1.0) del envío de archivo en curso, confirmado por el
  /// acuse del otro lado — no hay valor mientras no hay ningún envío activo.
  Stream<double> get sendProgress;
  void send(SboxMessage message);

  /// Envía un archivo leyéndolo del disco en pedazos: la memoria usada no
  /// depende del tamaño del archivo.
  Future<void> sendFile(String name, File file);
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

/// Envía [file] por [sink] en pedazos de [_kChunkSize], sin cargarlo entero
/// en memoria. Reutilizado por host y cliente (misma lógica de envío).
Future<void> _streamFileTo(void Function(List<int>) sink, File file) async {
  final raf = await file.open();
  try {
    while (true) {
      final chunk = await raf.read(_kChunkSize);
      if (chunk.isEmpty) break;
      sink(chunk);
    }
  } finally {
    await raf.close();
  }
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

  // Archivo actualmente en recepción (null si no hay ninguno en curso).
  bool _receivingFile = false;
  int _recvTotal = 0;
  int _recvSoFar = 0;
  DateTime? _lastAckSent;

  // Tamaño del archivo actualmente en envío (para calcular el % con los
  // acuses que manda el otro lado).
  int? _sendTotal;

  final _messages = StreamController<SboxMessage>.broadcast();
  final _fileEvents = StreamController<FileEvent>.broadcast();
  final _state = StreamController<PeerState>.broadcast();
  final _sendProgress = StreamController<double>.broadcast();

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
  Stream<FileEvent> get fileEvents => _fileEvents.stream;
  @override
  Stream<PeerState> get state => _state.stream;
  @override
  Stream<double> get sendProgress => _sendProgress.stream;

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
        // Trama binaria: un pedazo de los bytes del archivo en curso.
        if (raw is! String) {
          _onBinaryChunk(raw);
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
          _startReceivingFile(msg.name, msg.size);
        } else if (msg.type == SboxMsgType.fileProgress) {
          _onProgressAck(msg.received);
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

  void _startReceivingFile(String? name, int size) {
    _receivingFile = true;
    _recvTotal = size;
    _recvSoFar = 0;
    _lastAckSent = null;
    _fileEvents.add(FileStarted(name ?? 'archivo', size));
  }

  /// Suma un pedazo binario al archivo en curso de recepción, avisa a quien
  /// escucha y manda un acuse de progreso (con throttle) al emisor.
  void _onBinaryChunk(dynamic raw) {
    if (!_receivingFile) return; // trama inesperada sin cabecera: se ignora
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    _recvSoFar += bytes.length;
    // A prueba de fallos: si se pasó del tamaño anunciado (no debería pasar,
    // TCP entrega en orden, pero es la misma cautela que ya existía) se
    // descarta en vez de dejar pasar algo desincronizado.
    if (_recvTotal > 0 && _recvSoFar > _recvTotal) {
      _log('archivo descartado: llegaron más bytes de los anunciados');
      _receivingFile = false;
      _fileEvents.add(FileFinished(false));
      return;
    }
    _fileEvents.add(FileData(bytes));
    if (_recvTotal > 0 && _recvSoFar >= _recvTotal) {
      _receivingFile = false;
      _log('archivo recibido completo ($_recvSoFar bytes)');
      _sendProgressAck(); // acuse final, sin throttle: asegura que llegue el 100%
      _fileEvents.add(FileFinished(true));
    } else {
      _maybeSendProgressAck();
    }
  }

  void _maybeSendProgressAck() {
    final now = DateTime.now();
    if (_lastAckSent != null && now.difference(_lastAckSent!) < _kProgressAckInterval) {
      return;
    }
    _sendProgressAck();
  }

  void _sendProgressAck() {
    _lastAckSent = DateTime.now();
    send(SboxMessage.fileProgress(received: _recvSoFar));
  }

  void _onProgressAck(int received) {
    final total = _sendTotal;
    if (total != null && total > 0) {
      _sendProgress.add((received / total).clamp(0.0, 1.0));
    }
  }

  void _log(String m) {
    // ignore: avoid_print
    print('[sbox-host] $m');
  }

  void _onPeerGone() {
    _peer = null;
    _peerToken = null;
    // Si había un archivo a medio recibir, avisar que quedó incompleto para
    // que quien escucha borre lo que haya escrito hasta ahora.
    if (_receivingFile) {
      _receivingFile = false;
      _fileEvents.add(FileFinished(false));
    }
    _sendTotal = null;
    if (!_state.isClosed) _state.add(PeerState.listening);
  }

  @override
  void send(SboxMessage message) => _peer?.add(message.encode());

  @override
  Future<void> sendFile(String name, File file) async {
    final size = await file.length();
    _sendTotal = size;
    _sendProgress.add(0.0);
    send(SboxMessage.fileHeader(name: name, size: size));
    try {
      await _streamFileTo((chunk) => _peer?.add(chunk), file);
    } finally {
      _sendTotal = null;
    }
  }

  @override
  Future<void> dispose() async {
    await _peer?.close();
    await _server?.close(force: true);
    await _messages.close();
    await _fileEvents.close();
    await _state.close();
    await _sendProgress.close();
  }
}

/// El cliente (el teléfono): se conecta al host por IP y envía el código.
class SboxClient implements PeerLink {
  SboxClient({required this.deviceName});

  final String deviceName;

  WebSocket? _ws;

  // Archivo actualmente en recepción (mismo esquema que en SboxHost).
  bool _receivingFile = false;
  int _recvTotal = 0;
  int _recvSoFar = 0;
  DateTime? _lastAckSent;
  int? _sendTotal;

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
  final _fileEvents = StreamController<FileEvent>.broadcast();
  final _state = StreamController<PeerState>.broadcast();
  final _sendProgress = StreamController<double>.broadcast();

  @override
  Stream<SboxMessage> get messages => _messages.stream;
  @override
  Stream<FileEvent> get fileEvents => _fileEvents.stream;
  @override
  Stream<PeerState> get state => _state.stream;
  @override
  Stream<double> get sendProgress => _sendProgress.stream;

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
          // Trama binaria: un pedazo de los bytes del archivo en curso.
          if (raw is! String) {
            _onBinaryChunk(raw);
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
            _startReceivingFile(msg.name, msg.size);
          } else if (msg.type == SboxMsgType.fileProgress) {
            _onProgressAck(msg.received);
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

  void _startReceivingFile(String? name, int size) {
    _receivingFile = true;
    _recvTotal = size;
    _recvSoFar = 0;
    _lastAckSent = null;
    _fileEvents.add(FileStarted(name ?? 'archivo', size));
  }

  /// Suma un pedazo binario al archivo en curso de recepción, avisa a quien
  /// escucha y manda un acuse de progreso (con throttle) al emisor.
  void _onBinaryChunk(dynamic raw) {
    if (!_receivingFile) return;
    final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
    _recvSoFar += bytes.length;
    if (_recvTotal > 0 && _recvSoFar > _recvTotal) {
      _receivingFile = false;
      _fileEvents.add(FileFinished(false));
      return;
    }
    _fileEvents.add(FileData(bytes));
    if (_recvTotal > 0 && _recvSoFar >= _recvTotal) {
      _receivingFile = false;
      _sendProgressAck();
      _fileEvents.add(FileFinished(true));
    } else {
      _maybeSendProgressAck();
    }
  }

  void _maybeSendProgressAck() {
    final now = DateTime.now();
    if (_lastAckSent != null && now.difference(_lastAckSent!) < _kProgressAckInterval) {
      return;
    }
    _sendProgressAck();
  }

  void _sendProgressAck() {
    _lastAckSent = DateTime.now();
    send(SboxMessage.fileProgress(received: _recvSoFar));
  }

  void _onProgressAck(int received) {
    final total = _sendTotal;
    if (total != null && total > 0) {
      _sendProgress.add((received / total).clamp(0.0, 1.0));
    }
  }

  void _onGone() {
    _ws = null;
    if (_receivingFile) {
      _receivingFile = false;
      _fileEvents.add(FileFinished(false));
    }
    _sendTotal = null;
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
  Future<void> sendFile(String name, File file) async {
    final size = await file.length();
    _sendTotal = size;
    _sendProgress.add(0.0);
    send(SboxMessage.fileHeader(name: name, size: size));
    try {
      await _streamFileTo((chunk) => _ws?.add(chunk), file);
    } finally {
      _sendTotal = null;
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    await _ws?.close();
    await _messages.close();
    await _fileEvents.close();
    await _state.close();
    await _sendProgress.close();
  }
}
