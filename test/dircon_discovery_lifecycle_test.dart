import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ss2kconfigapp/utils/constants.dart';
import 'package:ss2kconfigapp/utils/dircon_discovery.dart';

class FakeBrowser extends BonsoirAction<BonsoirDiscoveryEvent>
    with ServiceResolver {
  final events = StreamController<BonsoirDiscoveryEvent>.broadcast(sync: true);
  Completer<void>? initializeGate;
  bool failStart = false;
  bool started = false;
  bool stopped = false;
  bool ready = false;
  final resolved = <BonsoirService>[];
  @override
  Stream<BonsoirDiscoveryEvent> get eventStream => events.stream;
  @override
  bool get isReady => ready;
  @override
  bool get isStopped => stopped;
  @override
  Future<void> initialize() async {
    await initializeGate?.future;
    ready = true;
  }

  @override
  Future<void> start() async {
    if (failStart) throw StateError('permission denied');
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    await events.close();
  }

  @override
  void resolveService(BonsoirService service) => resolved.add(service);
  @override
  bool supportsMdnsHostname() => true;
}

class FakeBonjour extends BonsoirPlatformInterface {
  FakeBonjour(this.browser);
  final FakeBrowser browser;
  String? type;
  @override
  BonsoirAction<BonsoirDiscoveryEvent> createDiscoveryAction(
    String type, {
    bool printLogs = false,
  }) {
    this.type = type;
    return browser;
  }

  @override
  BonsoirAction<BonsoirBroadcastEvent> createBroadcastAction(
    BonsoirService service, {
    bool printLogs = false,
  }) => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BonsoirPlatformInterface previous;
  late FakeBrowser browser;
  late FakeBonjour platform;
  late DirConDiscovery discovery;
  final service = BonsoirService.ignoreNorms(
    name: 'SmartTestS3',
    type: DirConEndpoint.serviceType,
    port: 8081,
    hostAddresses: ['192.168.1.50'],
    attributes: {
      'ble-service-uuids': csUUID,
      'mac-address': 'AA-BB-CC-DD-EE-FF',
    },
  );
  setUp(() {
    previous = BonsoirPlatformInterface.instance;
    browser = FakeBrowser();
    platform = FakeBonjour(browser);
    BonsoirPlatformInterface.instance = platform;
    discovery = DirConDiscovery();
  });
  tearDown(() async {
    await discovery.stop();
    discovery.dispose();
    BonsoirPlatformInterface.instance = previous;
  });

  test(
    'browses exact firmware service, resolves, updates and removes devices',
    () async {
      await discovery.start();
      expect(platform.type, '_wahoo-fitness-tnp._tcp');
      final unresolved = service.copyWith(hostAddresses: []);
      browser.events.add(
        BonsoirDiscoveryServiceFoundEvent(service: unresolved),
      );
      expect(browser.resolved, [unresolved]);
      browser.events.add(
        BonsoirDiscoveryServiceResolvedEvent(service: service),
      );
      expect(discovery.endpoints.single.host, '192.168.1.50');
      browser.events.add(
        BonsoirDiscoveryServiceUpdatedEvent(
          service: service.copyWith(hostAddresses: ['192.168.1.77']),
        ),
      );
      expect(discovery.endpoints.single.host, '192.168.1.77');
      browser.events.add(BonsoirDiscoveryServiceLostEvent(service: service));
      expect(discovery.endpoints, isEmpty);
      await discovery.stop();
      expect(browser.stopped, isTrue);
      expect(discovery.isScanning, isFalse);
    },
  );

  test('stop during native initialization never starts a late scan', () async {
    final gate = Completer<void>();
    browser.initializeGate = gate;
    final starting = discovery.start();
    await Future<void>.delayed(Duration.zero);
    final stopping = discovery.stop();
    gate.complete();
    await starting;
    await stopping;
    expect(browser.started, isFalse);
    expect(browser.stopped, isTrue);
    expect(discovery.isScanning, isFalse);
  });

  test('failed native startup stops cleanly', () async {
    browser.failStart = true;
    await discovery.start();
    await Future<void>.delayed(Duration.zero);
    expect(discovery.isScanning, isFalse);
    expect(browser.stopped, isTrue);
  });

  test('timeout stops browsing but retains discovered scan results', () async {
    await discovery.start(timeout: const Duration(milliseconds: 10));
    browser.events.add(BonsoirDiscoveryServiceResolvedEvent(service: service));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(discovery.isScanning, isFalse);
    expect(discovery.endpoints, hasLength(1));
    expect(browser.stopped, isTrue);
  });

  test(
    'recovery matches stable MAC even after DHCP address and name change',
    () async {
      final found = DirConDiscovery.find(
        id: 'aabbccddeeff',
        host: '192.168.1.10',
        name: 'Old Name',
        timeout: const Duration(seconds: 1),
      );
      await Future<void>.delayed(Duration.zero);
      browser.events.add(
        BonsoirDiscoveryServiceResolvedEvent(service: service),
      );
      expect((await found)?.host, '192.168.1.50');
      expect(browser.stopped, isTrue);
    },
  );
}
