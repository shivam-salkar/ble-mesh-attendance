// Phase 4 — Relay test packet and ACK models.
//
// PHASE-4 INTEROPERABILITY TEST PROTOCOL
// This is a development test protocol and is NOT production-secure.

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// The Phase 4 test relay packet that travels over BLE GATT.
class RelayPacket {
  static const int protocolVersion = 1;
  static const String typeTestRelay = 'TEST_RELAY';

  final int version;
  final String type;
  final String packetId;
  final String originId;
  final String sourcePlatform;
  final String payload;
  int ttl;
  int hopCount;

  RelayPacket({
    this.version = protocolVersion,
    this.type = typeTestRelay,
    String? packetId,
    required this.originId,
    required this.sourcePlatform,
    required this.payload,
    this.ttl = 3,
    this.hopCount = 0,
  }) : packetId = packetId ?? _generatePacketId();

  /// Generate an 8-char hex packet ID.
  static String _generatePacketId() {
    final full = _uuid.v4().replaceAll('-', '');
    return full.substring(0, 8).toUpperCase();
  }

  /// Create from JSON map (received over BLE).
  factory RelayPacket.fromJson(Map<String, dynamic> json) {
    return RelayPacket(
      version: json['v'] as int? ?? 1,
      type: json['t'] as String? ?? typeTestRelay,
      packetId: json['pid'] as String? ?? '',
      originId: json['oid'] as String? ?? '',
      sourcePlatform: json['sp'] as String? ?? '',
      payload: json['p'] as String? ?? '',
      ttl: json['ttl'] as int? ?? 0,
      hopCount: json['hc'] as int? ?? 0,
    );
  }

  /// Convert to JSON map for BLE transmission.
  Map<String, dynamic> toJson() {
    return {
      'v': version,
      't': type,
      'pid': packetId,
      'oid': originId,
      'sp': sourcePlatform,
      'p': payload,
      'ttl': ttl,
      'hc': hopCount,
    };
  }

  /// Serialize to compact JSON string for GATT write.
  String toJsonString() {
    return '{"v":$version,"t":"$type","pid":"$packetId","oid":"$originId","sp":"$sourcePlatform","p":"$payload","ttl":$ttl,"hc":$hopCount}';
  }

  /// Create a forwarded copy (increment hop, decrement TTL).
  RelayPacket forwarded() {
    return RelayPacket(
      version: version,
      type: type,
      packetId: packetId,
      originId: originId,
      sourcePlatform: sourcePlatform,
      payload: payload,
      ttl: ttl - 1,
      hopCount: hopCount + 1,
    );
  }

  bool get isValid =>
      version == protocolVersion &&
      type == typeTestRelay &&
      packetId.isNotEmpty &&
      originId.isNotEmpty &&
      ttl > 0;

  @override
  String toString() => 'RelayPacket(pid=$packetId, origin=$originId, '
      'platform=$sourcePlatform, payload=$payload, ttl=$ttl, hc=$hopCount)';
}

/// ACK packet received from the ESP32 gateway or a relay peer.
class AckPacket {
  final int version;
  final String type;
  final String packetId;
  final String gatewayId;
  final String status;

  const AckPacket({
    required this.version,
    required this.type,
    required this.packetId,
    required this.gatewayId,
    required this.status,
  });

  factory AckPacket.fromJson(Map<String, dynamic> json) {
    return AckPacket(
      version: json['v'] as int? ?? 1,
      type: json['t'] as String? ?? 'ACK',
      packetId: json['pid'] as String? ?? '',
      gatewayId: json['gid'] as String? ?? '',
      status: json['s'] as String? ?? '',
    );
  }

  bool get isReceived => status == 'RECEIVED';
  bool get isDuplicate => status == 'DUPLICATE';

  @override
  String toString() => 'ACK($packetId → $status from $gatewayId)';
}
