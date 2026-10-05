// Phase 4 — BLE service managing Central and Peripheral roles & Attendance.
//
// Central role (flutter_blue_plus):
//   - Scan for nearby BLE devices (other phones + ESP32 gateway)
//   - Connect to devices
//   - Submit attendance packets with Student Name & MAC Address
//   - Write relay packets to GATT characteristics
//   - Listen for ACK notifications
//
// Peripheral role (flutter_ble_peripheral):
//   - Advertise this device as a mesh relay node
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
import '../models/attendance_record.dart';
import 'device_id_service.dart';
import 'student_profile_service.dart';
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

/// The main BLE service for Attendance and Mesh Relay.
class BleService extends ChangeNotifier {
  // ─── State ─────────────────────────────────────────────────────

  final RelayEngine _relayEngine = RelayEngine();
  final List<BleEvent> _events = [];
  final List<DiscoveredDevice> _discoveredDevices = [];
  final List<AttendanceRecord> _attendees = [];

  StudentProfile? _profile;
  String _deviceId = '';
  String _platform = '';
  bool _isScanning = false;
  bool _relayMode = false;
  bool _isAdvertising = false;
  BluetoothDevice? _connectedDevice;
  String _connectedDeviceName = '';
  bool _isConnected = false;
  String _bleStatus = 'Initializing...';

  // Attendance state
  bool _isAttendanceMarked = false;
  bool _isSubmittingAttendance = false;
  String? _lastMarkedPacketId;
  DateTime? _attendanceMarkedTime;
  int _classroomAttendeeCount = 0;

  StreamSubscription? _scanSubscription;
  StreamSubscription? _ackSubscription;
  StreamSubscription? _statusSubscription;

  // Gateway peer tracking — how many clients are connected to the gateway
  int _gatewayPeerCount = 0;

  // ─── Getters ───────────────────────────────────────────────────

  StudentProfile? get profile => _profile;
  String get studentName => _profile?.name ?? 'Student';
  String get studentId => _profile?.studentId ?? '';
  String get macAddress => _profile?.macAddress ?? '';
  String get deviceId => _deviceId;
  String get platform => _platform;
  bool get isScanning => _isScanning;
  bool get relayMode => _relayMode;
  bool get isAdvertising => _isAdvertising;
  bool get isConnected => _isConnected;
  String get connectedDeviceName => _connectedDeviceName;
  String get bleStatus => _bleStatus;
  int get gatewayPeerCount => _gatewayPeerCount;
  int get classroomAttendeeCount => _classroomAttendeeCount;
  bool get isAttendanceMarked => _isAttendanceMarked;
  bool get isSubmittingAttendance => _isSubmittingAttendance;
  DateTime? get attendanceMarkedTime => _attendanceMarkedTime;
  List<BleEvent> get events => List.unmodifiable(_events);
  List<DiscoveredDevice> get discoveredDevices =>
      List.unmodifiable(_discoveredDevices);
  List<AttendanceRecord> get attendees => List.unmodifiable(_attendees);

  // ─── Initialization ────────────────────────────────────────────

  Future<void> initialize() async {
    _profile = await StudentProfileService.getProfile();
    _deviceId = _profile!.deviceId;
    _platform = DeviceIdService.platform;
    _bleStatus = 'Ready';
    _addEvent(BleEventType.info,
        'Profile loaded: ${_profile!.name.isEmpty ? "Unnamed Student" : _profile!.name} [MAC: ${_profile!.macAddress}]');
    notifyListeners();
  }

  Future<void> updateProfile({
    required String name,
    required String studentId,
    String? macAddress,
  }) async {
    _profile = await StudentProfileService.saveProfile(
      name: name,
      studentId: studentId,
      macAddress: macAddress,
    );
    _addEvent(BleEventType.info,
        'Updated Profile: ${_profile!.name} (${_profile!.studentId}) [MAC: ${_profile!.macAddress}]');
    notifyListeners();
  }

  // ─── Scanning (Central Role) ───────────────────────────────────

  Future<void> startScan() async {
    if (_isScanning) return;

    _discoveredDevices.clear();
    _isScanning = true;
    _bleStatus = 'Scanning...';
    _addEvent(BleEventType.scan, 'Scanning for classroom gateway and mesh peers...');
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
          'Discovered ${services.length} services on ${device.name}');

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

  /// Automatically connects to the closest classroom gateway if available.
  Future<bool> autoConnectGateway() async {
    if (_isConnected && _connectedDeviceName.contains('Gateway')) return true;

    // Search discovered devices for gateway
    final gateway = _discoveredDevices.where((d) => d.isGateway).firstOrNull;
    if (gateway != null) {
      return await connectToDevice(gateway);
    }

    // Otherwise, run a brief scan
    await startScan();
    final foundGateway = _discoveredDevices.where((d) => d.isGateway).firstOrNull;
    if (foundGateway != null) {
      return await connectToDevice(foundGateway);
    }

    // If no direct gateway found, check for a mesh relay peer
    final relay = _discoveredDevices.where((d) => d.isRelay).firstOrNull;
    if (relay != null) {
      _addEvent(BleEventType.info, 'No direct gateway. Connecting via relay: ${relay.name}');
      return await connectToDevice(relay);
    }

    return false;
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

      if (ack.attendeeCount > 0) {
        _classroomAttendeeCount = ack.attendeeCount;
      }

      // If this ACK confirms our attendance submission
      if (ack.packetId == _lastMarkedPacketId || ack.isReceived) {
        _isAttendanceMarked = true;
        _isSubmittingAttendance = false;
        _attendanceMarkedTime = DateTime.now();

        // Update self attendee record
        final idx = _attendees.indexWhere((a) => a.isSelf);
        if (idx != -1) {
          _attendees[idx] = _attendees[idx].copyWith(
            isConfirmed: true,
            timestamp: _attendanceMarkedTime,
          );
        } else {
          _attendees.insert(
            0,
            AttendanceRecord(
              studentName: _profile?.name.isNotEmpty == true ? _profile!.name : 'Student',
              studentId: _profile?.studentId ?? '',
              macAddress: _profile?.macAddress ?? '',
              deviceId: _deviceId,
              timestamp: _attendanceMarkedTime!,
              isConfirmed: true,
              isSelf: true,
            ),
          );
        }

        _addEvent(BleEventType.info,
            '✓ Attendance Verified by Gateway! ($_classroomAttendeeCount attendee(s) in lecture)');
        notifyListeners();
      }
    } catch (e) {
      _addEvent(BleEventType.error, 'ACK parse error: $e');
    }
  }

  /// Subscribe to the gateway's status characteristic to track peer count & attendees.
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
      final attendees = json['attendees'] as int? ?? 0;

      bool changed = false;
      if (clients != _gatewayPeerCount) {
        _gatewayPeerCount = clients;
        changed = true;
      }
      if (attendees > 0 && attendees != _classroomAttendeeCount) {
        _classroomAttendeeCount = attendees;
        changed = true;
      }

      if (changed) {
        _addEvent(BleEventType.info,
            'Gateway status: $clients client(s), $attendees attendee(s)');
        notifyListeners();
      }
    } catch (_) {}
  }

  // ─── Student Attendance Submission ─────────────────────────────

  /// Submits student attendance to the connected Gateway or mesh peer.
  Future<bool> markAttendance() async {
    // If not connected, try auto-connecting
    if (!_isConnected || _connectedDevice == null) {
      _addEvent(BleEventType.info, 'Not connected. Searching for classroom gateway...');
      final connected = await autoConnectGateway();
      if (!connected) {
        _addEvent(BleEventType.error,
            'Cannot connect to Classroom Gateway. Ensure you are in range and scan.');
        return false;
      }
    }

    final name = _profile?.name.trim().isNotEmpty == true
        ? _profile!.name.trim()
        : 'Student (${_deviceId.split('-').last})';
    final sid = _profile?.studentId.trim().isNotEmpty == true
        ? _profile!.studentId.trim()
        : 'STU-${_deviceId.split('-').last}';
    final mac = _profile?.macAddress ?? '';

    _isSubmittingAttendance = true;
    notifyListeners();

    final packet = RelayPacket(
      type: RelayPacket.typeAttendance,
      originId: _deviceId,
      sourcePlatform: _platform,
      studentName: name,
      studentId: sid,
      deviceMac: mac,
      payload: '$name ($sid)',
      ttl: 3,
      hopCount: 0,
    );

    _lastMarkedPacketId = packet.packetId;
    _relayEngine.markSeen(packet.packetId);

    // Register self in local attendees list as pending confirmation
    _attendees.removeWhere((a) => a.isSelf);
    _attendees.insert(
      0,
      AttendanceRecord(
        studentName: name,
        studentId: sid,
        macAddress: mac,
        deviceId: _deviceId,
        timestamp: DateTime.now(),
        isConfirmed: false,
        isSelf: true,
      ),
    );

    _addEvent(BleEventType.tx,
        'Submitting Attendance for "$name" [MAC: $mac] → $_connectedDeviceName');

    try {
      final success = await _writePacket(packet);
      if (success) {
        _addEvent(BleEventType.info,
            'Packet sent! Waiting for Gateway acknowledgment...');
      } else {
        _isSubmittingAttendance = false;
        notifyListeners();
      }
      return success;
    } catch (e) {
      _isSubmittingAttendance = false;
      _addEvent(BleEventType.error, 'Attendance submit failed: $e');
      notifyListeners();
      return false;
    }
  }

  // ─── Test Packet Dispatching ───────────────────────────────────

  Future<bool> sendTestPacket(String payload) async {
    if (!_isConnected || _connectedDevice == null) {
      _addEvent(BleEventType.error, 'Not connected');
      return false;
    }

    final packet = RelayPacket(
      type: RelayPacket.typeTestRelay,
      originId: _deviceId,
      sourcePlatform: _platform,
      studentName: _profile?.name ?? '',
      studentId: _profile?.studentId ?? '',
      deviceMac: _profile?.macAddress ?? '',
      payload: payload,
      ttl: 3,
      hopCount: 0,
    );

    _relayEngine.markSeen(packet.packetId);
    _addEvent(BleEventType.tx, 'Sending ${packet.packetId} → $_connectedDeviceName');

    return await _writePacket(packet);
  }

  Future<bool> _writePacket(RelayPacket packet) async {
    if (_connectedDevice == null) return false;

    try {
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

      final jsonBytes = utf8.encode(packet.toJsonString());
      await targetChar.write(jsonBytes, withoutResponse: false);

      _addEvent(BleEventType.tx,
          'Sent: ${packet.packetId} (${jsonBytes.length} bytes)');
      notifyListeners();
      return true;
    } catch (e) {
      _addEvent(BleEventType.error, 'Write failed: $e');
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
