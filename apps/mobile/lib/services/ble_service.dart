// Phase 4 — BLE service managing Central and Peripheral roles.
//
// Central role (flutter_blue_plus):
//   - Scan for nearby BLE devices (other phones + ESP32 gateway)
//   - Connect to devices
//   - Write relay packets to GATT characteristics
//   - Listen for ACK notifications
//
// Peripheral role (flutter_ble_peripheral):
//   - Advertise this device as a relay node
//   - Host a GATT server for receiving relay packets from other phones
//
// IMPORTANT: This service operates in the FOREGROUND only, per the PRD.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import '../models/relay_packet.dart';
import '../models/ble_event.dart';
import 'device_id_service.dart';
import 'relay_engine.dart';

/// BLE UUIDs — must match ESP32 gateway and protocol spec.
class BleUuids {
  // Gateway service (Phone → ESP32)
  static final gatewayService =
      Guid('a1b2c3d4-e5f6-7890-abcd-ef1234567890');
  static final gatewayStatus =
      Guid('a1b2c3d4-e5f6-7890-abcd-ef1234567891');
  static final gatewayAttendance =
      Guid('a1b2c3d4-e5f6-7890-abcd-ef1234567892');
  static final gatewayAck =
      Guid('a1b2c3d4-e5f6-7890-abcd-ef1234567896');

  // Relay service (Phone ↔ Phone)
  static final relayService =
      Guid('a1b2c3d4-e5f6-7890-abcd-ef1234567893');
  static final relayRx =
      Guid('a1b2c3d4-e5f6-7890-abcd-ef1234567894');
  static final relayTx =
      Guid('a1b2c3d4-e5f6-7890-abcd-ef1234567895');
}

/// Represents a discovered BLE device.
class DiscoveredDevice {
  final String name;
  final String id;
  final int rssi;
  final bool isGateway;
  final bool isRelay;
  final BluetoothDevice? fbpDevice;

  const DiscoveredDevice({
    required this.name,
    required this.id,
    required this.rssi,
    this.isGateway = false,
    this.isRelay = false,
    this.fbpDevice,
  });
}

/// The main BLE service for Phase 4 testing.
class BleService extends ChangeNotifier {
  // ─── State ─────────────────────────────────────────────────────

  final RelayEngine _relayEngine = RelayEngine();
  final List<BleEvent> _events = [];
  final List<DiscoveredDevice> _discoveredDevices = [];

  String _deviceId = '';
  String _platform = '';
  bool _isScanning = false;
  bool _relayMode = false;
  bool _isAdvertising = false;
  BluetoothDevice? _connectedDevice;
  String _connectedDeviceName = '';
  bool _isConnected = false;
  String _bleStatus = 'Initializing...';

  StreamSubscription? _scanSubscription;
  StreamSubscription? _ackSubscription;
  StreamSubscription? _statusSubscription;

  // Gateway peer tracking — how many clients are connected to the gateway
  int _gatewayPeerCount = 0;

  // ─── Getters ───────────────────────────────────────────────────

  String get deviceId => _deviceId;
  String get platform => _platform;
  bool get isScanning => _isScanning;
  bool get relayMode => _relayMode;
  bool get isAdvertising => _isAdvertising;
  bool get isConnected => _isConnected;
  String get connectedDeviceName => _connectedDeviceName;
  String get bleStatus => _bleStatus;
  int get gatewayPeerCount => _gatewayPeerCount;
  List<BleEvent> get events => List.unmodifiable(_events);
  List<DiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);

  // ─── Initialization ────────────────────────────────────────────

  Future<void> initialize() async {
    _deviceId = await DeviceIdService.getDeviceId();
    _platform = DeviceIdService.platform;
    _bleStatus = 'Ready';
    _addEvent(BleEventType.info, 'Device ID: $_deviceId ($_platform)');
    notifyListeners();
  }

  // ─── Scanning (Central Role) ───────────────────────────────────

  Future<void> startScan() async {
    if (_isScanning) return;

    _discoveredDevices.clear();
    _isScanning = true;
    _bleStatus = 'Scanning...';
    _addEvent(BleEventType.scan, 'Scan started');
    notifyListeners();

    try {
      // Start scanning with our known service UUIDs
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withServices: [BleUuids.gatewayService, BleUuids.relayService],
        androidUsesFineLocation: true,
      );

      _scanSubscription?.cancel();
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        _discoveredDevices.clear();
        for (final result in results) {
          final name = result.device.platformName.isNotEmpty
              ? result.device.platformName
              : result.advertisementData.advName;
          final serviceUuids = result.advertisementData.serviceUuids;

          final isGateway =
              serviceUuids.contains(BleUuids.gatewayService) ||
              name.startsWith('BMA-Gateway');
          final isRelay =
              serviceUuids.contains(BleUuids.relayService) ||
              (name.startsWith('BMA-') && !isGateway);

          if (name.isNotEmpty || isGateway || isRelay) {
            _discoveredDevices.add(DiscoveredDevice(
              name: name.isEmpty ? result.device.remoteId.str : name,
              id: result.device.remoteId.str,
              rssi: result.rssi,
              isGateway: isGateway,
              isRelay: isRelay,
              fbpDevice: result.device,
            ));
          }
        }
        notifyListeners();
      });

      // Also do a general scan without filter to find all BMA devices
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true,
      );

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 10));
    } catch (e) {
      _addEvent(BleEventType.error, 'Scan error: $e');
    } finally {
      _isScanning = false;
      _bleStatus = _isConnected ? 'Connected' : 'Ready';
      _addEvent(BleEventType.scan,
          'Scan complete: ${_discoveredDevices.length} devices found');
      notifyListeners();
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _isScanning = false;
    _bleStatus = _isConnected ? 'Connected' : 'Ready';
    notifyListeners();
  }

  // ─── Connection (Central Role) ─────────────────────────────────

  Future<bool> connectToDevice(DiscoveredDevice device) async {
    if (device.fbpDevice == null) {
      _addEvent(BleEventType.error, 'No BLE device handle for ${device.name}');
      return false;
    }

    _bleStatus = 'Connecting to ${device.name}...';
    _addEvent(BleEventType.connect, 'Connecting to ${device.name}...');
    notifyListeners();

    try {
      await device.fbpDevice!.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      _connectedDevice = device.fbpDevice;
      _connectedDeviceName = device.name;
      _isConnected = true;
      _bleStatus = 'Connected to ${device.name}';
      _addEvent(BleEventType.connect, 'Connected to ${device.name}');

      // Listen for disconnection
      device.fbpDevice!.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _isConnected = false;
          _connectedDevice = null;
          _connectedDeviceName = '';
          _gatewayPeerCount = 0;
          _statusSubscription?.cancel();
          _bleStatus = 'Disconnected';
          _addEvent(BleEventType.disconnect, 'Disconnected from ${device.name}');
          notifyListeners();
        }
      });

      // Discover services
      final services = await device.fbpDevice!.discoverServices();
      _addEvent(BleEventType.info,
          'Discovered ${services.length} services');

      // Subscribe to ACK notifications if this is a gateway
      if (device.isGateway) {
        _subscribeToAck(services);
        _subscribeToGatewayStatus(services);
      }

      notifyListeners();
      return true;
    } catch (e) {
      _bleStatus = 'Connection failed';
      _addEvent(BleEventType.error, 'Connection failed: $e');
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      final name = _connectedDeviceName;
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
      _connectedDeviceName = '';
      _isConnected = false;
      _gatewayPeerCount = 0;
      _bleStatus = 'Disconnected';
      _addEvent(BleEventType.disconnect, 'Disconnected from $name');
      notifyListeners();
    }
  }

  void _subscribeToAck(List<BluetoothService> services) {
    for (final service in services) {
      if (service.uuid == BleUuids.gatewayService) {
        for (final char in service.characteristics) {
          if (char.uuid == BleUuids.gatewayAck) {
            _addEvent(BleEventType.info, 'Subscribing to ACK notifications');
            char.setNotifyValue(true);
            _ackSubscription?.cancel();
            _ackSubscription = char.onValueReceived.listen((value) {
              _handleAckNotification(value);
            });
          }
        }
      }
    }
  }

  void _handleAckNotification(List<int> data) {
    try {
      final jsonStr = utf8.decode(data);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final ack = AckPacket.fromJson(json);
      _addEvent(BleEventType.ack, '$ack');
    } catch (e) {
      _addEvent(BleEventType.error, 'ACK parse error: $e');
    }
  }

  /// Subscribe to the gateway's status characteristic to track peer count.
  void _subscribeToGatewayStatus(List<BluetoothService> services) {
    for (final service in services) {
      if (service.uuid == BleUuids.gatewayService) {
        for (final char in service.characteristics) {
          if (char.uuid == BleUuids.gatewayStatus) {
            _addEvent(BleEventType.info, 'Subscribing to gateway status');
            char.setNotifyValue(true);
            _statusSubscription?.cancel();
            _statusSubscription = char.onValueReceived.listen((value) {
              _handleGatewayStatus(value);
            });
            // Also do an initial read
            char.read().then((value) {
              _handleGatewayStatus(value);
            }).catchError((_) {});
          }
        }
      }
    }
  }

  void _handleGatewayStatus(List<int> data) {
    try {
      final jsonStr = utf8.decode(data);
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      final clients = json['clients'] as int? ?? 0;
      if (clients != _gatewayPeerCount) {
        _gatewayPeerCount = clients;
        _addEvent(BleEventType.info, 'Gateway reports $clients connected client(s)');
        notifyListeners();
      }
    } catch (e) {
      // Might be old-format string "GATEWAY_ACTIVE_v1_P4", ignore
    }
  }

  // ─── Packet Sending ────────────────────────────────────────────

  Future<bool> sendTestPacket(String payload) async {
    if (!_isConnected || _connectedDevice == null) {
      _addEvent(BleEventType.error, 'Not connected');
      return false;
    }

    final packet = RelayPacket(
      originId: _deviceId,
      sourcePlatform: _platform,
      payload: payload,
      ttl: 3,
      hopCount: 0,
    );

    // Mark our own packet as seen so we don't relay our own
    _relayEngine.markSeen(packet.packetId);

    _addEvent(BleEventType.tx,
        'Sending ${packet.packetId} → $_connectedDeviceName');

    try {
      // Find the attendance characteristic
      final services = await _connectedDevice!.discoverServices();
      BluetoothCharacteristic? targetChar;

      for (final service in services) {
        if (service.uuid == BleUuids.gatewayService) {
          for (final char in service.characteristics) {
            if (char.uuid == BleUuids.gatewayAttendance) {
              targetChar = char;
              break;
            }
          }
        }
        // Also check for relay service (phone-to-phone)
        if (service.uuid == BleUuids.relayService) {
          for (final char in service.characteristics) {
            if (char.uuid == BleUuids.relayRx) {
              targetChar = char;
              break;
            }
          }
        }
      }

      if (targetChar == null) {
        _addEvent(BleEventType.error, 'No writable characteristic found');
        return false;
      }

      // Write the JSON packet
      final jsonBytes = utf8.encode(packet.toJsonString());
      await targetChar.write(jsonBytes, withoutResponse: false);

      _addEvent(BleEventType.tx,
          'Sent: ${packet.packetId} (${jsonBytes.length} bytes)');
      notifyListeners();
      return true;
    } catch (e) {
      _addEvent(BleEventType.error, 'Send failed: $e');
      notifyListeners();
      return false;
    }
  }

  // ─── Relay Mode (Peripheral Role) ──────────────────────────────

  Future<void> toggleRelayMode() async {
    if (_relayMode) {
      await _stopRelay();
    } else {
      await _startRelay();
    }
  }

  Future<void> _startRelay() async {
    try {
      _addEvent(BleEventType.info, 'Starting relay mode...');

      // Start advertising as a BLE peripheral with our relay service
      final advertiseData = AdvertiseData(
        localName: 'BMA-${_deviceId.split('-').last}',
        serviceUuid: 'a1b2c3d4-e5f6-7890-abcd-ef1234567893',
      );

      final isSupported = await FlutterBlePeripheral().isSupported;
      if (!isSupported) {
        _addEvent(BleEventType.error,
            'BLE Peripheral mode not supported on this device');
        return;
      }

      await FlutterBlePeripheral().start(advertiseData: advertiseData);

      _relayMode = true;
      _isAdvertising = true;
      _bleStatus = 'Relay mode ON (advertising)';
      _addEvent(BleEventType.info,
          'Relay mode active — advertising as BMA-${_deviceId.split('-').last}');
      notifyListeners();
    } catch (e) {
      _addEvent(BleEventType.error, 'Relay start failed: $e');
      notifyListeners();
    }
  }

  Future<void> _stopRelay() async {
    try {
      await FlutterBlePeripheral().stop();
      _relayMode = false;
      _isAdvertising = false;
      _bleStatus = _isConnected ? 'Connected' : 'Ready';
      _addEvent(BleEventType.info, 'Relay mode stopped');
      notifyListeners();
    } catch (e) {
      _addEvent(BleEventType.error, 'Relay stop failed: $e');
    }
  }

  // ─── Event Log ─────────────────────────────────────────────────

  void _addEvent(BleEventType type, String message) {
    _events.insert(0, BleEvent(type: type, message: message));
    // Keep log bounded
    if (_events.length > 100) {
      _events.removeRange(100, _events.length);
    }
  }

  void clearEvents() {
    _events.clear();
    notifyListeners();
  }

  // ─── Cleanup ───────────────────────────────────────────────────

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _ackSubscription?.cancel();
    _statusSubscription?.cancel();
    _connectedDevice?.disconnect();
    if (_relayMode) {
      FlutterBlePeripheral().stop();
    }
    super.dispose();
  }
}
