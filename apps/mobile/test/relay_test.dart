import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ble_mesh_attendance/models/relay_packet.dart';
import 'package:ble_mesh_attendance/services/relay_engine.dart';
import 'package:ble_mesh_attendance/services/device_id_service.dart';

void main() {
  group('RelayPacket', () {
    test('serializes and deserializes correctly', () {
      final packet = RelayPacket(
        originId: 'IOS-A1B2',
        sourcePlatform: 'ios',
        payload: 'HELLO-FROM-IP1',
        ttl: 3,
      );

      final jsonStr = packet.toJsonString();
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final parsed = RelayPacket.fromJson(decoded);

      expect(parsed.version, equals(1));
      expect(parsed.type, equals('TEST_RELAY'));
      expect(parsed.packetId, equals(packet.packetId));
      expect(parsed.originId, equals('IOS-A1B2'));
      expect(parsed.sourcePlatform, equals('ios'));
      expect(parsed.payload, equals('HELLO-FROM-IP1'));
      expect(parsed.ttl, equals(3));
      expect(parsed.hopCount, equals(0));
    });

    test('forwarding creates valid packet with decremented TTL and incremented hopCount', () {
      final packet = RelayPacket(
        originId: 'IOS-A1B2',
        sourcePlatform: 'ios',
        payload: 'HELLO-FROM-IP1',
        ttl: 3,
      );

      final forwarded = packet.forwarded();
      expect(forwarded.packetId, equals(packet.packetId));
      expect(forwarded.payload, equals(packet.payload));
      expect(forwarded.ttl, equals(2));
      expect(forwarded.hopCount, equals(1));
    });
  });

  group('AckPacket', () {
    test('serializes and parses ACK packet', () {
      final ack = AckPacket(
        version: 1,
        type: 'ACK',
        packetId: 'A1B2C3D4',
        gatewayId: 'BMA-Gateway-01',
        status: 'RECEIVED',
      );

      expect(ack.isReceived, isTrue);
      expect(ack.isDuplicate, isFalse);
      expect(ack.packetId, equals('A1B2C3D4'));
      expect(ack.gatewayId, equals('BMA-Gateway-01'));
    });

    test('parses ACK packet with online sync status', () {
      final json = {
        'v': 1,
        't': 'ACK',
        'pid': 'PKT-9988',
        'gid': 'ESP32_GATEWAY_405',
        's': 'VERIFIED_ONLINE',
        'count': 15,
        'sync': true,
      };

      final ack = AckPacket.fromJson(json);
      expect(ack.isReceived, isTrue);
      expect(ack.syncedOnline, isTrue);
      expect(ack.status, equals('VERIFIED_ONLINE'));
      expect(ack.attendeeCount, equals(15));
    });

    test('RelayPacket serializes and deserializes session tokens and nonces', () {
      final packet = RelayPacket(
        type: RelayPacket.typeAttendance,
        originId: 'DEV-99',
        sourcePlatform: 'android',
        payload: 'Aryan Darekar (25102C0040)',
        studentName: 'Aryan Darekar',
        studentId: '25102C0040',
        deviceMac: 'AA:BB:CC:DD:EE:FF',
        sessionId: 'sess-1234-abcd',
        sessionNonce: 'nonce-8899',
        ttl: 4,
      );

      final jsonStr = packet.toJsonString();
      expect(jsonStr, contains('"sess":"sess-1234-abcd"'));
      expect(jsonStr, contains('"nonce":"nonce-8899"'));

      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final parsed = RelayPacket.fromJson(decoded);

      expect(parsed.sessionId, equals('sess-1234-abcd'));
      expect(parsed.sessionNonce, equals('nonce-8899'));
      expect(parsed.studentName, equals('Aryan Darekar'));
      expect(parsed.deviceMac, equals('AA:BB:CC:DD:EE:FF'));

      final forwarded = parsed.forwarded();
      expect(forwarded.sessionId, equals('sess-1234-abcd'));
      expect(forwarded.sessionNonce, equals('nonce-8899'));
      expect(forwarded.ttl, equals(3));
      expect(forwarded.hopCount, equals(1));
    });
  });

  group('RelayEngine', () {
    late RelayEngine engine;

    setUp(() {
      engine = RelayEngine();
    });

    test('forwards first-seen packet with ttl > 0', () {
      final packet = RelayPacket(
        originId: 'ANDROID-C3D4',
        sourcePlatform: 'android',
        payload: 'TEST-PAYLOAD',
        ttl: 3,
      );

      final result = engine.processIncoming(packet);
      expect(result.action, equals(RelayAction.forward));
      expect(result.packet.ttl, equals(2));
      expect(result.packet.hopCount, equals(1));
    });

    test('suppresses duplicate packetId', () {
      final packet = RelayPacket(
        originId: 'IOS-A1B2',
        sourcePlatform: 'ios',
        payload: 'DUPLICATE-TEST',
        ttl: 3,
      );

      final result1 = engine.processIncoming(packet);
      expect(result1.action, equals(RelayAction.forward));

      // Same packet sent again
      final result2 = engine.processIncoming(packet);
      expect(result2.action, equals(RelayAction.duplicate));
    });

    test('drops packet when TTL expires', () {
      final packet = RelayPacket(
        version: 1,
        type: 'TEST_RELAY',
        packetId: 'DEADBEEF',
        originId: 'IOS-A1B2',
        sourcePlatform: 'ios',
        payload: 'EXPIRED-TEST',
        ttl: 0,
        hopCount: 3,
      );

      final result = engine.processIncoming(packet);
      expect(result.action, equals(RelayAction.ttlExpired));
    });
  });

  group('DeviceIdService', () {
    test('generates valid platform prefix', () {
      final prefix = DeviceIdService.platformPrefix;
      expect(['IOS', 'ANDROID', 'UNKNOWN'], contains(prefix));
    });
  });
}
