import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

/// Tipo de servicio mDNS de sbox.
const String kSboxServiceType = '_sbox._tcp';

/// Anuncia el host sbox en la red local. Lo corre la PC.
class SboxAdvertiser {
  BonsoirBroadcast? _broadcast;

  Future<void> start({required int port, String deviceLabel = 'PC'}) async {
    final broadcast = BonsoirBroadcast(
      service: BonsoirService(
        name: 'sbox $deviceLabel',
        type: kSboxServiceType,
        port: port,
        attributes: {'device': deviceLabel},
      ),
    );
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  Future<void> stop() async {
    await _broadcast?.stop();
    _broadcast = null;
  }
}

/// Un host sbox descubierto en la WiFi.
class DiscoveredHost {
  DiscoveredHost({required this.label, required this.ip, required this.port});
  final String label;
  final String ip;
  final int port;

  String get key => '$ip:$port';
}

/// Busca hosts sbox en la red local. Lo corre el teléfono.
class SboxBrowser {
  BonsoirDiscovery? _discovery;
  final _controller = StreamController<DiscoveredHost>.broadcast();

  Stream<DiscoveredHost> get hosts => _controller.stream;

  Future<void> start() async {
    final discovery = BonsoirDiscovery(type: kSboxServiceType);
    await discovery.initialize();
    discovery.eventStream!.listen((event) {
      switch (event) {
        // Un servicio apareció: hay que resolverlo para obtener IP y puerto.
        case BonsoirDiscoveryServiceFoundEvent():
          discovery.serviceResolver.resolveService(event.service);
        // Resuelto: ya tenemos la dirección.
        case BonsoirDiscoveryServiceResolvedEvent():
          final service = event.service;
          final ip = service.hostAddress;
          if (ip != null && !_controller.isClosed) {
            _controller.add(DiscoveredHost(
              label: service.attributes['device'] ?? 'PC',
              ip: ip,
              port: service.port,
            ));
          }
        default:
          break;
      }
    });
    await discovery.start();
    _discovery = discovery;
  }

  Future<void> stop() async {
    await _discovery?.stop();
    _discovery = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
