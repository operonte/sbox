import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart' as fsel;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:home_widget/home_widget.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:sbox_core/sbox_core.dart';
import 'package:share_plus/share_plus.dart' as share_plus;
import 'package:window_manager/window_manager.dart';

import 'discovery.dart';
import 'platform.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// La caja sbox: en escritorio actúa de host (muestra código + IP); en Android
/// actúa de cliente (descubre la PC en la WiFi y empareja con el código).
class SboxHome extends StatefulWidget {
  const SboxHome({super.key});

  @override
  State<SboxHome> createState() => _SboxHomeState();
}

class _SboxHomeState extends State<SboxHome> with WidgetsBindingObserver {
  // Enlace activo (host o cliente).
  SboxHost? _host;
  SboxClient? _client;
  PeerLink? get _link => _host ?? _client;

  PeerState _state = PeerState.idle;
  String? _shared; // último texto compartido (lo que viaja entre cajas)

  // Último archivo recibido (efímero: solo el último).
  String? _recvName;
  String? _recvPath;
  int _recvSize = 0;
  bool _sending = false;

  // Host (PC)
  String _code = '';
  int _port = kSboxPort;
  List<String> _ips = const [];
  SboxAdvertiser? _advertiser;
  // Notifica al SboxHost cuando cambia la lista de dispositivos de confianza
  // (p. ej. al "olvidar" uno en Configuración); se quita al recrear el host.
  VoidCallback? _trustListener;

  // Cliente (Android)
  SboxBrowser? _browser;
  final List<DiscoveredHost> _found = [];
  final _ipCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  // Últimos datos de una conexión exitosa, para reconectar al volver al foco
  // (el puerto lo recuerda internamente el propio SboxClient).
  String? _lastHost;
  String? _lastCode;
  // Hay un intento de auto-conexión con un token guardado en curso: si lo
  // rechazan, no se muestra "código incorrecto" (el usuario no pidió esto).
  bool _autoConnecting = false;

  // Envío
  final _sendCtrl = TextEditingController();
  // Cola de envío de archivos: uno a la vez y en orden (ver [_sendFilePath]).
  Future<void> _sendQueue = Future<void>.value();

  StreamSubscription<PeerState>? _stateSub;
  StreamSubscription<SboxMessage>? _msgSub;
  StreamSubscription<ReceivedFile>? _fileSub;
  StreamSubscription<DiscoveredHost>? _hostSub;
  StreamSubscription<List<SharedMediaFile>>? _shareSub;
  // Cambios de red (Android): al volver la WiFi, reconectar al instante.
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  // Compartido por «Compartir → sbox» mientras aún no había conexión (se manda
  // al conectar). Archivos por ruta y textos/URLs por separado.
  final List<String> _pendingSharePaths = [];
  final List<String> _pendingShareTexts = [];

  // Servicio en primer plano (Android): mantiene la conexión viva en 2º plano.
  bool _bgOn = false;

  /// Tope de tamaño por archivo. Es un portapapeles: para fotos/clips va sobrado
  /// y evita que un video enorme deje sin memoria al teléfono.
  static const int _maxFileBytes = 150 * 1024 * 1024; // 150 MB

  /// Canal hacia el runner nativo de Linux para leer/escribir imágenes del
  /// portapapeles.
  static const _clipboardChannel = MethodChannel('sbox/clipboard');

  /// Extensiones consideradas imagen (para el portapapeles y el auto-borrado).
  static const _imageExts = {
    '.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.heic', '.heif',
  };

  // Borrados de imágenes programados en el PC (para cancelarlos al cerrar).
  final List<Timer> _imageDeletions = [];

  bool _isImage(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return _imageExts.contains(name.substring(dot).toLowerCase());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (isDesktop) {
      _startHost();
    } else {
      _initForegroundTask();
      _startBrowsing();
      _listenShares();
      _watchConnectivity();
    }
  }

  /// Android: cuando vuelve la red (WiFi recuperada), reconectar al instante en
  /// vez de esperar el backoff. Complementa la reconexión-al-volver-al-foco.
  void _watchConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (hasNet && !_connected) _client?.reconnectNow();
    });
  }

  /// «Compartir → sbox»: lo que el usuario comparte desde otra app (foto, video,
  /// archivo, texto) llega aquí y se envía al PC (en cuanto haya conexión).
  void _listenShares() {
    final intent = ReceiveSharingIntent.instance;
    // Compartido que ABRIÓ la app.
    intent.getInitialMedia().then((files) {
      _onShared(files);
      intent.reset();
    });
    // Compartido mientras la app ya estaba abierta.
    _shareSub = intent.getMediaStream().listen(_onShared);
  }

  /// Android congela el proceso al perder el foco y el socket muere. Al volver
  /// a primer plano, si éramos cliente y nos quedamos sin conexión, reconectamos
  /// con los últimos datos conocidos.
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle != AppLifecycleState.resumed || isDesktop) return;
    if (_connected || _lastHost == null || _lastCode == null) return;
    // Ya emparejamos antes: reintento inmediato con reconexión infinita.
    _client?.reconnectNow();
  }

  /// Nombre con el que este equipo se anuncia (configurable; con defecto).
  String _myName() {
    final custom = Settings.instance.deviceName.value.trim();
    if (custom.isNotEmpty) return custom;
    return isDesktop ? 'PC' : 'Android';
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _listen(PeerLink link) {
    _stateSub?.cancel();
    _msgSub?.cancel();
    _fileSub?.cancel();
    _stateSub = link.state.listen((s) {
      if (_autoConnecting &&
          (s.status == PeerStatus.rejected || s.status == PeerStatus.error)) {
        // Intento silencioso con un token guardado: si falla, no asustamos
        // con un error que el usuario no pidió; solo volvemos a la pantalla
        // normal de emparejado.
        _autoConnecting = false;
        if (s.status == PeerStatus.rejected && _found.isNotEmpty) {
          final stale = TrustStore.instance.tokenFor(_found.first.label);
          if (stale != null) TrustStore.instance.forget(stale);
        }
        // Sin esto la pantalla se quedaba trabada en "Conectando…" (el botón
        // se deshabilita en ese estado): hay que volver a "idle" para que el
        // usuario pueda escribir el código a mano.
        if (mounted) setState(() => _state = PeerState.idle);
        return;
      }
      if (s.status == PeerStatus.connected) {
        _autoConnecting = false;
        if (s.token != null) {
          TrustStore.instance.remember(s.token!, s.peerName ?? 'PC');
        }
      }
      if (mounted) setState(() => _state = s);
      _updateWidget();
      _syncBgService(s); // mantener vivo el servicio en 2º plano según el estado
      _flushPendingShares(); // si quedaron compartidos en cola, mandarlos ya
      if (s.status == PeerStatus.connected) {
        _startClipboardWatch();
      } else {
        _stopClipboardWatch();
      }
    });
    _msgSub = link.messages.listen((m) async {
      if (m.type == SboxMsgType.text && m.content != null) {
        if (mounted) setState(() => _shared = m.content);
        // Portapapeles compartido: copiar automáticamente lo recibido.
        await Clipboard.setData(ClipboardData(text: m.content!));
        _updateWidget();
      }
    });
    _fileSub = link.files.listen(_onFileReceived);
  }

  Future<void> _startHost() async {
    unawaited(_sweepOldImages()); // limpia imágenes viejas de sesiones previas
    _code = (100000 + Random().nextInt(900000)).toString();
    final host = SboxHost(
      code: _code,
      deviceName: _myName(),
      trustedTokens: TrustStore.instance.tokens.value.keys.toSet(),
      onTrust: (token, label) => TrustStore.instance.remember(token, label),
    );
    _trustListener = () =>
        host.updateTrustedTokens(TrustStore.instance.tokens.value.keys.toSet());
    TrustStore.instance.tokens.addListener(_trustListener!);
    _host = host;
    _listen(host);
    _port = await host.start();
    _ips = await localIPv4();
    _advertiser = SboxAdvertiser();
    try {
      await _advertiser!.start(
        port: _port,
        deviceLabel: _myName(),
        ip: _primaryIp, // IP real de la WiFi (evita la virtual de VMs/VPN)
      );
    } catch (_) {
      // mDNS es opcional: si falla, queda el emparejamiento por IP manual.
    }
    if (mounted) setState(() {});
  }

  Future<void> _startBrowsing() async {
    _client = SboxClient(deviceName: _myName());
    _listen(_client!);
    _browser = SboxBrowser();
    _hostSub = _browser!.hosts.listen((h) {
      if (_found.any((e) => e.key == h.key)) return;
      if (mounted) setState(() => _found.add(h));
      _maybeAutoConnect(h);
    });
    try {
      await _browser!.start();
    } catch (_) {
      // Si el descubrimiento falla, el usuario puede escribir la IP a mano.
    }
  }

  void _connect() {
    final manualIp = _ipCtrl.text.trim();
    final host = manualIp.isNotEmpty
        ? DiscoveredHost(label: 'PC', ip: manualIp, port: kSboxPort)
        : (_found.isEmpty ? null : _found.first);
    if (host == null) return;
    final code = _codeCtrl.text.trim();
    _lastHost = host.ip;
    _lastCode = code;
    _autoConnecting = false; // conexión pedida a mano: sí mostrar errores
    _client?.connect(host.ip, code: code, port: host.port);
  }

  /// Si ya conocemos [h] (nos dio un token en un emparejado anterior), nos
  /// conectamos solos sin mostrarle el código al usuario.
  void _maybeAutoConnect(DiscoveredHost h) {
    if (_connected || _client == null) return;
    final token = TrustStore.instance.tokenFor(h.label);
    if (token == null) return;
    _autoConnecting = true;
    _lastHost = h.ip;
    _lastCode = '';
    _client!.connect(h.ip, token: token, port: h.port);
  }

  void _send(String text) {
    if (text.isEmpty) return;
    _link?.send(SboxMessage.text(text));
    if (mounted) setState(() => _shared = text);
  }

  Future<void> _sendClipboard() async {
    // En el PC (Wayland), si hay una imagen en el portapapeles, enviarla como
    // archivo. Si no hay imagen (o falla), enviar el texto como siempre.
    if (isDesktop && await _sendClipboardImage()) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _send(text);
  }

  /// Lee una imagen del portapapeles usando el canal nativo GTK del runner (sin
  /// herramientas externas) y la envía como archivo. Devuelve true si había una
  /// imagen (se haya enviado o no); false si no hay imagen (entonces se envía
  /// el texto). Con [dedupe] no reenvía la misma imagen dos veces seguidas
  /// (para el vigilante automático; el botón manual siempre reenvía).
  Future<bool> _sendClipboardImage({bool dedupe = false}) async {
    try {
      final bytes =
          await _clipboardChannel.invokeMethod<Uint8List>('getImagePng');
      if (bytes == null || bytes.isEmpty) return false;
      if (dedupe) {
        final hash = _quickHash(bytes);
        if (hash == _lastAutoImageHash) return true; // ya se mandó esta misma
        _lastAutoImageHash = hash;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/captura_${DateTime.now().millisecondsSinceEpoch}.png';
      await File(path).writeAsBytes(bytes, flush: true);
      await _sendFilePath(path);
      return true;
    } catch (_) {
      return false; // sin imagen o canal no disponible → se enviará el texto
    }
  }

  /// Suma de verificación barata (no criptográfica) para notar si la imagen
  /// del portapapeles cambió, sin comparar los bytes completos en cada tick.
  int _quickHash(Uint8List bytes) {
    var h = bytes.length;
    for (var i = 0; i < bytes.length; i += 97) {
      h = 0x1fffffff & (h * 31 + bytes[i]);
    }
    return h;
  }

  // ------------------------------------------------------ auto-portapapeles
  /// Revisa el portapapeles cada [_clipboardPollInterval] y manda solo lo que
  /// cambió (evita reenviar lo mismo, y evita el eco de lo que acabamos de
  /// recibir del otro lado — ver comparación con [_shared]).
  static const _clipboardPollInterval = Duration(seconds: 2);
  Timer? _clipboardWatch;
  int? _lastAutoImageHash;

  void _startClipboardWatch() {
    _clipboardWatch ??=
        Timer.periodic(_clipboardPollInterval, (_) => _autoClipboardTick());
  }

  void _stopClipboardWatch() {
    _clipboardWatch?.cancel();
    _clipboardWatch = null;
    _lastAutoImageHash = null;
  }

  Future<void> _autoClipboardTick() async {
    if (!Settings.instance.autoClipboard.value || !_connected || _sending) {
      return;
    }
    if (isDesktop && await _sendClipboardImage(dedupe: true)) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    // Distinto de lo último compartido (mandado o recibido): es una copia
    // nueva del usuario, no un eco de lo que sbox acaba de traer.
    if (text != null && text.isNotEmpty && text != _shared) _send(text);
  }

  // ----------------------------------------------------------------- archivos
  /// Elige un archivo (cualquier tipo) y lo envía al otro dispositivo.
  /// En escritorio usa el diálogo GTK nativo; en Android el selector del sistema.
  Future<void> _pickAndSendFile() async {
    if (!_connected || _sending) return;
    String? path;
    try {
      if (isDesktop) {
        path = (await fsel.openFile())?.path;
      } else {
        final result = await FilePicker.platform.pickFiles();
        path = result?.files.single.path;
      }
    } catch (e) {
      _toast('No se pudo leer el archivo');
      return;
    }
    if (path == null) return;
    setState(() => _sending = true);
    await _sendFilePath(path);
    if (mounted) setState(() => _sending = false);
  }

  /// Cámara (Android): tomar una foto o grabar un video y enviarlo al otro
  /// dispositivo (cae en su carpeta Descargas/sbox).
  Future<void> _capture() async {
    if (!_connected) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: cCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: cAccent),
              title: const Text('Tomar foto',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam, color: cAccent),
              title: const Text('Grabar video',
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.pop(context, 'video'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      final picker = ImagePicker();
      final file = choice == 'photo'
          ? await picker.pickImage(source: ImageSource.camera)
          : await picker.pickVideo(source: ImageSource.camera);
      if (file == null) return;
      // Las fotos pasan por el editor (girar/recortar) antes de enviarse; el
      // video se envía tal cual. En el editor, ✓ envía y ← descarta.
      var pathToSend = file.path;
      if (choice == 'photo') {
        final edited = await _editPhoto(file.path);
        if (edited == null) return; // canceló en el editor → no se envía nada
        pathToSend = edited;
      }
      setState(() => _sending = true);
      await _sendFilePath(pathToSend);
      if (mounted) setState(() => _sending = false);
    } catch (_) {
      _toast('No se pudo usar la cámara');
    }
  }

  /// Editor de la foto recién tomada: girar y recortar (uCrop nativo). Devuelve
  /// la ruta de la imagen editada, o `null` si el usuario cancela (equivale a
  /// «eliminar»: no se envía nada). Si el editor falla, se envía sin editar.
  Future<String?> _editPhoto(String path) async {
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: path,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Editar foto',
            toolbarColor: cBg,
            toolbarWidgetColor: Colors.white,
            backgroundColor: cBg,
            activeControlsWidgetColor: cAccent,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
        ],
      );
      return cropped?.path;
    } catch (_) {
      return path; // editor no disponible → se envía la foto sin editar
    }
  }

  /// Guarda un archivo recibido (Descargas en PC / almacenamiento de la app en
  /// Android) y lo deja listo para abrir.
  Future<void> _onFileReceived(ReceivedFile f) async {
    try {
      final dir = await _incomingDir();
      final path = await _uniquePath(dir, f.name);
      await File(path).writeAsBytes(f.bytes, flush: true);
      // En Android la tarjeta solo muestra el último recibido: borrar la copia
      // interna del anterior para no acumular archivos en la app. (En el PC la
      // copia vive en Descargas/sbox, que es del usuario: no se toca aquí.)
      final previous = _recvPath;
      if (!isDesktop && previous != null && previous != path) {
        try {
          await File(previous).delete();
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _recvName = f.name;
          _recvPath = path;
          _recvSize = f.size;
        });
      } else {
        _recvName = f.name;
        _recvPath = path;
        _recvSize = f.size;
      }
      if (isDesktop) {
        // Si es imagen: además de quedar en la carpeta, dejarla en el
        // portapapeles del PC (como ya se hace con el texto) y, si está
        // activado, programar su borrado de la carpeta sbox.
        if (_isImage(f.name)) {
          await _copyImageToClipboard(f.bytes);
          if (Settings.instance.autoDeleteImages.value) {
            _scheduleImageDeletion(path);
          }
        }
      } else {
        // En Android, copiarlo también a Descargas visible al recibir (en el PC
        // ya cae directo en Descargas/sbox). Así no depende de abrirlo.
        await _saveToDownloads(path);
      }
      _updateWidget(lastText: '📎 ${f.name}');
    } catch (e) {
      _toast('No se pudo guardar el archivo');
    }
  }

  /// Deja una imagen en el portapapeles del PC vía el canal nativo GTK
  /// (contraparte de getImagePng). Best-effort: si falla, no rompe nada.
  Future<void> _copyImageToClipboard(Uint8List bytes) async {
    try {
      await _clipboardChannel.invokeMethod<bool>('setImagePng', bytes);
    } catch (_) {
      // Sin canal nativo (p. ej. otra plataforma): se ignora en silencio.
    }
  }

  /// Programa el borrado de una imagen recibida de la carpeta sbox del PC
  /// pasados los segundos configurados (portapapeles efímero). Si al borrarla
  /// seguía siendo la imagen mostrada, limpia la tarjeta de «recibido».
  void _scheduleImageDeletion(String path) {
    final secs = Settings.instance.autoDeleteSeconds.value;
    late final Timer t;
    t = Timer(Duration(seconds: secs), () async {
      _imageDeletions.remove(t);
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Ya no está o no se pudo borrar: nada que hacer.
      }
      if (mounted && _recvPath == path) {
        setState(() {
          _recvName = null;
          _recvPath = null;
          _recvSize = 0;
        });
      }
    });
    _imageDeletions.add(t);
  }

  /// Al arrancar el host, borra imágenes viejas que quedaran en Descargas/sbox
  /// (p. ej. si la app se cerró antes de que saltara su temporizador). Hace que
  /// el borrado efímero sea fiable entre reinicios.
  Future<void> _sweepOldImages() async {
    if (!isDesktop || !Settings.instance.autoDeleteImages.value) return;
    try {
      final dir = Directory(await _incomingDir());
      if (!await dir.exists()) return;
      final maxAge = Duration(seconds: Settings.instance.autoDeleteSeconds.value);
      final now = DateTime.now();
      await for (final entity in dir.list()) {
        if (entity is! File || !_isImage(entity.path)) continue;
        final stat = await entity.stat();
        if (now.difference(stat.modified) > maxAge) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {
      // La carpeta puede no existir aún o no ser accesible: se ignora.
    }
  }

  Future<String> _incomingDir() async {
    if (isDesktop) {
      // Subcarpeta «sbox» dentro de Descargas (igual que en Android).
      final d = await getDownloadsDirectory();
      final base = d?.path ?? '${Platform.environment['HOME']}/Descargas';
      final dir = Directory('$base/sbox');
      await dir.create(recursive: true);
      return dir.path;
    }
    final d = await getApplicationDocumentsDirectory();
    return d.path;
  }

  /// Evita pisar archivos: «foto.png» → «foto (1).png» si ya existe.
  Future<String> _uniquePath(String dir, String name) async {
    if (!await File('$dir/$name').exists()) return '$dir/$name';
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var i = 1;
    while (await File('$dir/$base ($i)$ext').exists()) {
      i++;
    }
    return '$dir/$base ($i)$ext';
  }

  Future<void> _openReceived() async {
    final path = _recvPath;
    if (path == null) return;
    // En el PC está en ~/Descargas; en Android ya se copió a Descargas/sbox al
    // recibir. Aquí solo se abre.
    if (isDesktop) {
      await Process.run('xdg-open', [path]);
      return;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      _toast('No hay una app para abrir este archivo');
    }
  }

  /// Comparte el último archivo recibido con la hoja de compartir del sistema
  /// (otras apps, guardar, etc.) sin salir de sbox. Solo Android.
  Future<void> _shareReceived() async {
    final path = _recvPath;
    if (path == null) return;
    try {
      await share_plus.Share.shareXFiles([share_plus.XFile(path)]);
    } catch (_) {
      _toast('No se pudo compartir el archivo');
    }
  }

  /// Copia un archivo a la carpeta Descargas visible (Descargas/sbox) vía
  /// MediaStore. A prueba de fallos: si no se puede, el archivo igual se abre.
  ///
  /// Ojo: `MediaStore.saveFile` BORRA el archivo de origen tras copiarlo. Por
  /// eso le pasamos una copia temporal (mismo nombre, carpeta de caché) y así
  /// conservamos la copia interna, que es la que usan «Ver» y «Compartir».
  Future<void> _saveToDownloads(String path) async {
    String? tmp;
    try {
      MediaStore.appFolder = 'sbox';
      await MediaStore.ensureInitialized();
      final cache = await getTemporaryDirectory();
      tmp = '${cache.path}/${path.split('/').last}';
      await File(path).copy(tmp);
      final info = await MediaStore().saveFile(
        tempFilePath: tmp,
        dirType: DirType.download,
        dirName: DirName.download,
      );
      if (info != null) _toast('Guardado en Descargas/sbox');
    } catch (_) {
      // Sin acceso a Descargas: se abre desde la copia interna igualmente.
    } finally {
      // Si MediaStore no llegó a borrar el temporal (p. ej. falló antes),
      // limpiarlo para no dejar basura en la caché.
      if (tmp != null) {
        try {
          final leftover = File(tmp);
          if (await leftover.exists()) await leftover.delete();
        } catch (_) {}
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ----------------------------------------------------- compartir / drag&drop
  /// Envía un archivo por su ruta, encolado: un envío a la vez y en orden. Así
  /// no se cargan varios archivos grandes en memoria al mismo tiempo (p. ej. al
  /// compartir o soltar varios juntos) — a prueba de errores frente a OOM.
  Future<void> _sendFilePath(String path) {
    final task = _sendQueue.then((_) => _doSendFilePath(path));
    _sendQueue = task.catchError((_) {}); // un fallo no corta la cola
    return task;
  }

  /// Lee un archivo del disco por su ruta y lo envía al otro dispositivo.
  /// Comprueba el tamaño ANTES de cargarlo en memoria (a prueba de errores).
  Future<void> _doSendFilePath(String path) async {
    final name = path.split('/').last;
    try {
      final file = File(path);
      if (await file.length() > _maxFileBytes) {
        _toast('«$name» es muy grande (máx ${_fmtSize(_maxFileBytes)})');
        return;
      }
      _link?.sendFile(name, await file.readAsBytes());
      _toast('Enviado: $name');
    } catch (_) {
      _toast('No se pudo enviar el archivo');
    }
  }

  /// Llega contenido por «Compartir → sbox». Si hay conexión, se envía; si no,
  /// se guarda en cola y se manda al conectar.
  void _onShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    var queued = false;
    for (final f in files) {
      // Para texto/URL, `path` trae el contenido en sí.
      final isText =
          f.type == SharedMediaType.text || f.type == SharedMediaType.url;
      if (_connected) {
        isText ? _send(f.path) : _sendFilePath(f.path);
      } else {
        (isText ? _pendingShareTexts : _pendingSharePaths).add(f.path);
        queued = true;
      }
    }
    if (queued) _toast('Conéctate y se enviará lo compartido');
  }

  void _flushPendingShares() {
    if (!_connected) return;
    if (_pendingShareTexts.isNotEmpty) {
      final texts = List<String>.from(_pendingShareTexts);
      _pendingShareTexts.clear();
      for (final t in texts) {
        _send(t);
      }
    }
    if (_pendingSharePaths.isNotEmpty) {
      final paths = List<String>.from(_pendingSharePaths);
      _pendingSharePaths.clear();
      for (final p in paths) {
        _sendFilePath(p);
      }
    }
  }

  /// Arrastrar y soltar archivos sobre el recuadro (escritorio).
  Future<void> _onDesktopDrop(DropDoneDetails detail) async {
    if (!_connected) {
      _toast('Conéctate primero para enviar');
      return;
    }
    for (final file in detail.files) {
      await _sendFilePath(file.path);
    }
  }

  /// Empuja el estado y el último contenido al widget de inicio (solo Android).
  Future<void> _updateWidget({String? lastText}) async {
    if (isDesktop) return;
    final last = lastText ?? _shared ?? '';
    try {
      await HomeWidget.saveWidgetData<bool>('connected', _connected);
      await HomeWidget.saveWidgetData<String>(
        'status',
        _connected ? 'Conectado · ${_state.peerName ?? ''}' : 'Desconectado',
      );
      await HomeWidget.saveWidgetData<String>('lastText', last);
      await HomeWidget.updateWidget(androidName: 'SboxWidgetProvider');
    } catch (_) {
      // El widget es opcional: si falla la actualización, no rompe la app.
    }
  }

  // -------------------------------------------------- servicio en primer plano
  /// Configura el canal de la notificación del servicio (una sola vez).
  void _initForegroundTask() {
    try {
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'sbox_conn',
          channelName: 'Conexión sbox',
          channelDescription: 'Mantiene sbox conectado en segundo plano',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          onlyAlertOnce: true,
        ),
        iosNotificationOptions: const IOSNotificationOptions(),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          allowWakeLock: true,
          allowWifiLock: true, // mantener la WiFi despierta para el socket LAN
          autoRunOnBoot: false,
          // Si el usuario descarta la app de recientes, se corta el servicio
          // (la conexión vive en el isolate principal, que muere ahí de todos
          // modos). Mientras la app esté en 2º plano, sigue viva.
          stopWithTask: true,
        ),
      );
    } catch (_) {}
  }

  /// Ajusta el servicio según el estado: lo arranca al conectar y mantiene la
  /// notificación al día. No lo detiene en caídas: sigue hasta el botón rojo.
  void _syncBgService(PeerState s) {
    if (isDesktop) return;
    final text = switch (s.status) {
      PeerStatus.connected => 'Conectado · ${s.peerName ?? ''}',
      PeerStatus.connecting => s.message ?? 'Conectando…',
      _ => 'Desconectado',
    };
    if (s.status == PeerStatus.connected && !_bgOn) {
      _startBgService(text);
    } else if (_bgOn) {
      _updateBgNotification(text);
    }
  }

  Future<void> _startBgService(String text) async {
    try {
      await FlutterForegroundTask.requestNotificationPermission();
      // Best-effort: pedir excepción de batería para sobrevivir mejor a la
      // pantalla bloqueada (depende del fabricante; se pide una sola vez).
      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
      if (await FlutterForegroundTask.isRunningService) {
        _bgOn = true;
        await _updateBgNotification(text);
        return;
      }
      await FlutterForegroundTask.startService(
        serviceId: 1747,
        serviceTypes: const [ForegroundServiceTypes.dataSync],
        notificationTitle: 'sbox',
        notificationText: text,
      );
      _bgOn = true;
    } catch (_) {
      // A prueba de fallos: sin servicio queda la reconexión-al-volver.
    }
  }

  Future<void> _updateBgNotification(String text) async {
    try {
      await FlutterForegroundTask.updateService(notificationText: text);
    } catch (_) {}
  }

  Future<void> _stopBgService() async {
    if (!_bgOn) return;
    _bgOn = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }

  Future<void> _logout() async {
    await _stopBgService(); // botón rojo: cortar también el servicio de 2º plano
    await _stateSub?.cancel();
    await _msgSub?.cancel();
    await _fileSub?.cancel();
    await _hostSub?.cancel();
    await _advertiser?.stop();
    await _browser?.stop();
    await _host?.dispose();
    await _client?.dispose();
    if (_trustListener != null) {
      TrustStore.instance.tokens.removeListener(_trustListener!);
      _trustListener = null;
    }
    _host = null;
    _client = null;
    _advertiser = null;
    _browser = null;
    _found.clear();
    _ipCtrl.clear();
    _codeCtrl.clear();
    setState(() {
      _state = PeerState.idle;
      _shared = null;
      _recvName = null;
      _recvPath = null;
    });
    if (isDesktop) {
      _startHost();
    } else {
      _startBrowsing();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stateSub?.cancel();
    _msgSub?.cancel();
    _fileSub?.cancel();
    _hostSub?.cancel();
    _shareSub?.cancel();
    _connSub?.cancel();
    _clipboardWatch?.cancel();
    for (final t in _imageDeletions) {
      t.cancel();
    }
    _advertiser?.stop();
    _browser?.stop();
    _host?.dispose();
    _client?.dispose();
    if (_trustListener != null) {
      TrustStore.instance.tokens.removeListener(_trustListener!);
    }
    _ipCtrl.dispose();
    _codeCtrl.dispose();
    _sendCtrl.dispose();
    super.dispose();
  }

  bool get _connected => _state.status == PeerStatus.connected;

  Color get _dotColor {
    switch (_state.status) {
      case PeerStatus.connected:
        return cOnline;
      case PeerStatus.connecting:
      case PeerStatus.listening:
        return cAccent;
      case PeerStatus.rejected:
      case PeerStatus.error:
        return cDanger;
      case PeerStatus.idle:
        return cDim;
    }
  }

  String? get _primaryIp {
    for (final ip in _ips) {
      if (!ip.startsWith('192.168.122.')) return ip; // evita el bridge virtual
    }
    return _ips.isEmpty ? null : _ips.first;
  }

  @override
  Widget build(BuildContext context) {
    Widget box = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cCard.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cBorder),
      ),
      child: Stack(
        children: [
          Column(
            children: [
              _header(),
              Expanded(child: _body()),
            ],
          ),
          if (isDesktop)
            Positioned(right: 0, bottom: 0, child: _resizeGrip()),
        ],
      ),
    );
    // En escritorio, soltar archivos sobre el recuadro los envía.
    if (isDesktop) {
      box = DropTarget(onDragDone: _onDesktopDrop, child: box);
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(8), child: box),
      ),
    );
  }

  Widget _header() {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          const Text(
            'SBOX',
            style: TextStyle(
              fontFamily: fontMono,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          _iconBtn(Icons.settings, _openSettings),
          if (_connected)
            _iconBtn(Icons.logout, _logout, color: cDanger),
          if (isDesktop) _iconBtn(Icons.close, () => windowManager.close()),
        ],
      ),
    );
    // En escritorio, arrastrar la cabecera mueve la ventana sin bordes.
    return isDesktop ? DragToMoveArea(child: header) : header;
  }

  Widget _body() {
    if (_connected) return _connectedView();
    if (isDesktop) return _hostWaitingView();
    return _clientConnectView();
  }

  // ---------------------------------------------------------------- HOST (PC)
  Widget _hostWaitingView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        children: [
          const _Label('VINCULAR · MISMA WIFI'),
          const SizedBox(height: 14),
          FittedBox(fit: BoxFit.scaleDown, child: _codeBoxes(_code)),
          const SizedBox(height: 14),
          const Text(
            'Escribe este código en tu teléfono\n(ambos en la misma WiFi)',
            textAlign: TextAlign.center,
            style: TextStyle(color: cDim, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 18),
          const Divider(color: cBorder, height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: cDim),
              ),
              const SizedBox(width: 10),
              const Flexible(
                child: Text(
                  'Esperando al teléfono…',
                  style: TextStyle(color: cDim, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_primaryIp != null)
            Text(
              'Si no aparece sola, en el teléfono escribe:\n$_primaryIp',
              textAlign: TextAlign.center,
              style: const TextStyle(color: cDim, fontSize: 12, height: 1.4),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------- CLIENTE (Android)
  Widget _clientConnectView() {
    final found = _found.isNotEmpty ? _found.first : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Label('CONECTAR A TU PC'),
          const SizedBox(height: 14),
          if (found == null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                SizedBox(
                  width: 14,
                  height: 14,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: cDim),
                ),
                SizedBox(width: 10),
                Text('Buscando tu PC en la WiFi…',
                    style: TextStyle(color: cDim, fontSize: 13)),
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cAccent.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.computer, color: cAccent, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${found.label} · ${found.ip}',
                      style: const TextStyle(color: cAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          _codeField(),
          const SizedBox(height: 12),
          _pillButton(
            label: _state.status == PeerStatus.connecting
                ? 'Conectando…'
                : 'Conectar',
            icon: Icons.link,
            onTap: _state.status == PeerStatus.connecting ? null : _connect,
          ),
          if (_state.status == PeerStatus.rejected ||
              _state.status == PeerStatus.error) ...[
            const SizedBox(height: 10),
            Text(
              _state.message ?? 'No se pudo conectar',
              textAlign: TextAlign.center,
              style: const TextStyle(color: cDanger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          const Divider(color: cBorder, height: 1),
          const SizedBox(height: 12),
          const Text('¿No aparece sola? Escribe la IP que muestra la PC:',
              style: TextStyle(color: cDim, fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _ipCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontFamily: fontMono, fontSize: 14),
            decoration: _inputDecoration('192.168.x.x'),
          ),
        ],
      ),
    );
  }

  Widget _codeField() {
    return TextField(
      controller: _codeCtrl,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: fontMono,
        fontSize: 22,
        letterSpacing: 8,
        fontWeight: FontWeight.w700,
      ),
      decoration: _inputDecoration('· · · · · ·').copyWith(counterText: ''),
    );
  }

  // ---------------------------------------------------------------- CONECTADO
  Widget _connectedView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: cOnline, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Conectado · ${_state.peerName ?? ''}',
                  style: const TextStyle(color: cOnline, fontSize: 13),
                ),
              ),
            ],
          ),
          if (_recvName != null) ...[
            const SizedBox(height: 12),
            _receivedFileCard(),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cBorder),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _shared?.isNotEmpty == true ? _shared! : 'Portapapeles vacío',
                  style: TextStyle(
                    color: _shared?.isNotEmpty == true ? Colors.white : cDim,
                    fontFamily: fontMono,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _iconBtn(
                _sending ? Icons.hourglass_top : Icons.attach_file,
                _pickAndSendFile,
                color: cAccent,
              ),
              if (!isDesktop)
                _iconBtn(Icons.photo_camera, _capture, color: cAccent),
              Expanded(
                child: TextField(
                  controller: _sendCtrl,
                  style: const TextStyle(fontSize: 14),
                  decoration: _inputDecoration('Escribe o pega…'),
                  onSubmitted: (t) {
                    _send(t);
                    _sendCtrl.clear();
                  },
                ),
              ),
              const SizedBox(width: 8),
              _iconBtn(Icons.send, () {
                _send(_sendCtrl.text);
                _sendCtrl.clear();
              }, color: cAccent),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _pillButton(
                  label: 'Portapapeles',
                  icon: Icons.content_paste,
                  onTap: _sendClipboard,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _pillButton(
                  label: 'Copiar',
                  icon: Icons.copy,
                  onTap: _shared == null
                      ? null
                      : () => Clipboard.setData(ClipboardData(text: _shared!)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ widgets
  Widget _codeBoxes(String code) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final d in code.split(''))
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 36,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cAccent.withValues(alpha: 0.4)),
            ),
            child: Text(
              d,
              style: const TextStyle(
                fontFamily: fontMono,
                color: cAccent,
                fontWeight: FontWeight.w700,
                fontSize: 20,
              ),
            ),
          ),
      ],
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, {Color color = cDim}) {
    return InkResponse(
      onTap: onTap,
      radius: 20,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  // Tarjeta del último archivo recibido, con botones para compartirlo (Android)
  // y abrirlo.
  Widget _receivedFileCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cOnline.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cOnline.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file, color: cOnline, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _recvName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Recibido · ${_fmtSize(_recvSize)}',
                  style: const TextStyle(color: cDim, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          if (!isDesktop)
            _iconBtn(Icons.share, _shareReceived, color: cOnline),
          _iconBtn(Icons.open_in_new, _openReceived, color: cOnline),
        ],
      ),
    );
  }

  // Agarre para redimensionar la ventana sin bordes (escritorio).
  Widget _resizeGrip() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => windowManager.startResizing(ResizeEdge.bottomRight),
        child: const Padding(
          padding: EdgeInsets.fromLTRB(10, 10, 6, 6),
          child: Icon(Icons.south_east, size: 14, color: cDim),
        ),
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cAccent.withValues(alpha: enabled ? 0.16 : 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cAccent.withValues(alpha: enabled ? 0.45 : 0.18),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: enabled ? cAccent : cDim),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: fontMono,
                      color: enabled ? cAccent : cDim,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: cDim),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.25),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: cBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cAccent.withValues(alpha: 0.6)),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: fontMono,
        color: cDim,
        fontSize: 11,
        letterSpacing: 2,
      ),
    );
  }
}
