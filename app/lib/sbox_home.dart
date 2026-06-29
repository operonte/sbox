import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sbox_core/sbox_core.dart';
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

class _SboxHomeState extends State<SboxHome> {
  // Enlace activo (host o cliente).
  SboxHost? _host;
  SboxClient? _client;
  PeerLink? get _link => _host ?? _client;

  PeerState _state = PeerState.idle;
  String? _shared; // último texto compartido (lo que viaja entre cajas)

  // Host (PC)
  String _code = '';
  int _port = kSboxPort;
  List<String> _ips = const [];
  SboxAdvertiser? _advertiser;

  // Cliente (Android)
  SboxBrowser? _browser;
  final List<DiscoveredHost> _found = [];
  final _ipCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  // Envío
  final _sendCtrl = TextEditingController();

  StreamSubscription<PeerState>? _stateSub;
  StreamSubscription<SboxMessage>? _msgSub;
  StreamSubscription<DiscoveredHost>? _hostSub;

  @override
  void initState() {
    super.initState();
    if (isDesktop) {
      _startHost();
    } else {
      _startBrowsing();
    }
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
    _stateSub = link.state.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _msgSub = link.messages.listen((m) async {
      if (m.type == SboxMsgType.text && m.content != null) {
        if (mounted) setState(() => _shared = m.content);
        // Portapapeles compartido: copiar automáticamente lo recibido.
        await Clipboard.setData(ClipboardData(text: m.content!));
      }
    });
  }

  Future<void> _startHost() async {
    _code = (100000 + Random().nextInt(900000)).toString();
    final host = SboxHost(code: _code, deviceName: _myName());
    _host = host;
    _listen(host);
    _port = await host.start();
    _ips = await localIPv4();
    _advertiser = SboxAdvertiser();
    try {
      await _advertiser!.start(port: _port, deviceLabel: _myName());
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
    _client?.connect(host.ip, code: _codeCtrl.text.trim(), port: host.port);
  }

  void _send(String text) {
    if (text.isEmpty) return;
    _link?.send(SboxMessage.text(text));
    if (mounted) setState(() => _shared = text);
  }

  Future<void> _sendClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty) _send(text);
  }

  Future<void> _logout() async {
    await _stateSub?.cancel();
    await _msgSub?.cancel();
    await _hostSub?.cancel();
    await _advertiser?.stop();
    await _browser?.stop();
    await _host?.dispose();
    await _client?.dispose();
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
    });
    if (isDesktop) {
      _startHost();
    } else {
      _startBrowsing();
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _msgSub?.cancel();
    _hostSub?.cancel();
    _advertiser?.stop();
    _browser?.stop();
    _host?.dispose();
    _client?.dispose();
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Container(
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
          ),
        ),
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
