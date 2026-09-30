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
