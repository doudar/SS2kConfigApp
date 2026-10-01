import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

import 'constants.dart';

/// A resolved SmartSpin2k DNS-SD service. The advertised MAC is the WiFi MAC,
/// not the BLE address, and the serial number is not unique in SS2k firmware.
class DirConEndpoint {
  const DirConEndpoint({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });

  static const serviceType = '_wahoo-fitness-tnp._tcp';
  final String id;
  final String name;
  final String host;
  final int port;

  static DirConEndpoint? fromService(BonsoirService service) {
    final uuids = (service.attributes['ble-service-uuids'] ?? '')
        .toLowerCase()
        .split(',')
        .map((uuid) => uuid.trim());
    // Other trainers advertise the same Dircon service. Require SS2k's
    // configuration UUID, including when the owner has renamed the device.
    if (!uuids.contains(csUUID.toLowerCase()) ||
        service.port <= 0 ||
        service.port > 65535 ||
        service.hostAddresses.isEmpty)
      return null;
    final addresses = service.hostAddresses
        .where((host) => host.isNotEmpty && host != '0.0.0.0' && host != '::')
        .toList();
    if (addresses.isEmpty) return null;
    final mac = service.attributes['mac-address']
        ?.replaceAll(RegExp('[:-]'), '')
        .toLowerCase();
    return DirConEndpoint(
      id: mac != null && RegExp(r'^[0-9a-f]{12}$').hasMatch(mac)
          ? mac
          : service.name.toLowerCase(),
      name: service.name,
      host: addresses.firstWhere(
        (host) => !host.contains(':'),
        orElse: () => addresses.first,
      ),
      port: service.port,
    );
  }
}

/// A bounded, cancellable native Bonjour/NSD browse shared by scan and recovery.
/// Web keeps using Web Bluetooth, since browsers cannot browse local mDNS.
class DirConDiscovery extends ChangeNotifier {
  final Map<String, DirConEndpoint> _endpoints = {};
  _DirConBrowseSession? _session;
  Timer? _timer;
  int _generation = 0;
  bool _disposed = false;
  bool isScanning = false;

  List<DirConEndpoint> get endpoints => List.unmodifiable(_endpoints.values);

  Future<void> start({Duration timeout = const Duration(seconds: 15)}) async {
    final generation = ++_generation;
    await _stopCurrent();
    if (_disposed || kIsWeb || generation != _generation) return;
    _endpoints.clear();
    isScanning = true;
    notifyListeners();
    _timer = Timer(timeout, () => unawaited(stop()));
    final session = _DirConBrowseSession();
    _session = session;
    session.starting = _startBrowser(generation, session);
    await session.starting;
  }

  Future<void> _startBrowser(
    int generation,
    _DirConBrowseSession session,
  ) async {
    try {
      final browser = BonsoirDiscovery(
        type: DirConEndpoint.serviceType,
        printLogs: false,
      );
      session.browser = browser;
      await browser.initialize();
      if (_disposed || generation != _generation) return;
      session.subscription = browser.eventStream!.listen(
        (event) {
          if (_disposed || generation != _generation) return;
          switch (event) {
            case BonsoirDiscoveryServiceFoundEvent():
              _observe(event.service);
              unawaited(
                event.service
                    .resolve(browser.serviceResolver)
                    .catchError(
                      (Object error) =>
                          debugPrint('[mDNS] Resolve failed: $error'),
                    ),
              );
            case BonsoirDiscoveryServiceResolvedEvent():
              _observe(event.service);
            case BonsoirDiscoveryServiceUpdatedEvent():
              _observe(event.service);
            case BonsoirDiscoveryServiceLostEvent():
              _endpoints.removeWhere(
                (_, endpoint) => endpoint.name == event.service.name,
              );
              notifyListeners();
            default:
              break;
          }
        },
        onError: (Object error) {
          debugPrint('[mDNS] Discovery failed: $error');
          unawaited(stop());
        },
      );
      await browser.start();
    } catch (error) {
      debugPrint('[mDNS] Discovery unavailable: $error');
      // Schedule teardown outside session.starting, which stop() itself awaits.
      if (generation == _generation) {
        unawaited(Future<void>.microtask(stop));
      }
    }
  }

  void _observe(BonsoirService service) {
    final endpoint = DirConEndpoint.fromService(service);
    if (endpoint == null) return;
    _endpoints[endpoint.id] = endpoint;
    notifyListeners();
  }

  Future<void> stop() {
    ++_generation;
    return _stopCurrent();
  }

  Future<void> _stopCurrent() async {
    _timer?.cancel();
    isScanning = false;
    if (!_disposed) notifyListeners();
    final session = _session;
    _session = null;
    await session?.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }

  static Future<DirConEndpoint?> find({
    String? id,
    String? host,
    String? name,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (kIsWeb) return null;
    final discovery = DirConDiscovery();
    final result = Completer<DirConEndpoint?>();
    bool started = false;
    DirConEndpoint? uniqueNameMatch() {
      if (id != null || name == null || name.isEmpty) return null;
      final named = discovery.endpoints
          .where(
            (endpoint) => endpoint.name.toLowerCase() == name.toLowerCase(),
          )
          .toList();
      return named.length == 1 ? named.single : null;
    }

    discovery.addListener(() {
      if (discovery.isScanning) started = true;
      for (final endpoint in discovery.endpoints) {
        if (id != null ? endpoint.id == id : endpoint.host == host) {
          if (!result.isCompleted) result.complete(endpoint);
        }
      }
      if (started && !discovery.isScanning && !result.isCompleted) {
        result.complete(uniqueNameMatch());
      }
    });
    try {
      unawaited(discovery.start(timeout: timeout));
      return await result.future.timeout(
        timeout,
        onTimeout: () {
          // A BLE-only identity has no WiFi MAC yet. Allow DHCP address changes
          // by name only after collecting the entire browse, if unambiguous.
          return uniqueNameMatch();
        },
      );
    } finally {
      await discovery.stop();
      discovery.dispose();
    }
  }
}

class _DirConBrowseSession {
  BonsoirDiscovery? browser;
  StreamSubscription<BonsoirDiscoveryEvent>? subscription;
  Future<void>? starting;

  Future<void> stop() async {
    await starting;
    await subscription?.cancel();
    try {
      if (browser?.isReady ?? false) await browser!.stop();
    } catch (error) {
      debugPrint('[mDNS] Stop failed: $error');
    }
  }
}
