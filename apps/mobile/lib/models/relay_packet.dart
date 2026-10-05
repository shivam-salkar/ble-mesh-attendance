// Phase 4 — Relay test packet and ACK models.
//
// PHASE-4 INTEROPERABILITY & ATTENDANCE PROTOCOL
// Supports both TEST_RELAY packets and ATTENDANCE confirmation packets.

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// The Phase 4 relay packet that travels over BLE GATT.
class RelayPacket {
  static const int protocolVersion = 1;
  static const String typeTestRelay = 'TEST_RELAY';
  static const String typeAttendance = 'ATTENDANCE';

  final int version;
  final String type;
  final String packetId;
  final String originId;
  final String sourcePlatform;
  final String payload;
  final String studentName;
  final String studentId;
  final String deviceMac;
  final String? sessionId;
  final String? sessionNonce;
  int ttl;
  int hopCount;

  RelayPacket({
    this.version = protocolVersion,
    this.type = typeTestRelay,
    String? packetId,
    required this.originId,
    required this.sourcePlatform,
    required this.payload,
    this.studentName = '',
    this.studentId = '',
    this.deviceMac = '',
    this.sessionId,
    this.sessionNonce,
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
      studentName: json['sname'] as String? ?? '',
      studentId: json['sid'] as String? ?? '',
      deviceMac: json['mac'] as String? ?? '',
      sessionId: json['sess'] as String? ?? (json['sessionId'] as String?),
      sessionNonce: json['nonce'] as String? ?? (json['sessionNonce'] as String?),
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
      'sname': studentName,
      'sid': studentId,
      'mac': deviceMac,
      if (sessionId != null && sessionId!.isNotEmpty) 'sess': sessionId,
      if (sessionNonce != null && sessionNonce!.isNotEmpty) 'nonce': sessionNonce,
      'p': payload,
      'ttl': ttl,
      'hc': hopCount,
    };
  }

  /// Serialize to compact JSON string for GATT write.
  String toJsonString() {
    final buffer = StringBuffer('{')
      ..write('"v":$version,')
      ..write('"t":"$type",')
      ..write('"pid":"$packetId",')
      ..write('"oid":"$originId",')
      ..write('"sp":"$sourcePlatform",')
      ..write('"sname":"$studentName",')
      ..write('"sid":"$studentId",')
      ..write('"mac":"$deviceMac",');
    if (sessionId != null && sessionId!.isNotEmpty) {
      buffer.write('"sess":"$sessionId",');
    }
    if (sessionNonce != null && sessionNonce!.isNotEmpty) {
      buffer.write('"nonce":"$sessionNonce",');
    }
    buffer
      ..write('"p":"$payload",')
      ..write('"ttl":$ttl,')
      ..write('"hc":$hopCount}');
    return buffer.toString();
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
      studentName: studentName,
      studentId: studentId,
      deviceMac: deviceMac,
      sessionId: sessionId,
      sessionNonce: sessionNonce,
      ttl: ttl - 1,
      hopCount: hopCount + 1,
    );
  }

  bool get isValid =>
      version == protocolVersion &&
      (type == typeTestRelay || type == typeAttendance) &&
      packetId.isNotEmpty &&
      originId.isNotEmpty &&
      ttl > 0;

  @override
  String toString() => 'RelayPacket(pid=$packetId, origin=$originId, name=$studentName, '
      'mac=$deviceMac, platform=$sourcePlatform, payload=$payload, ttl=$ttl, hc=$hopCount)';
}

/// ACK packet received from the ESP32 gateway or a relay peer.
class AckPacket {
  final int version;
  final String type;
  final String packetId;
  final String gatewayId;
  final String status;
  final int attendeeCount;
  final bool syncedOnline;

  const AckPacket({
    required this.version,
    required this.type,
    required this.packetId,
    required this.gatewayId,
    required this.status,
    this.attendeeCount = 0,
    this.syncedOnline = false,
  });

  factory AckPacket.fromJson(Map<String, dynamic> json) {
    return AckPacket(
      version: json['v'] as int? ?? 1,
      type: json['t'] as String? ?? 'ACK',
      packetId: json['pid'] as String? ?? '',
      gatewayId: json['gid'] as String? ?? '',
      status: json['s'] as String? ?? '',
      attendeeCount: json['count'] as int? ?? 0,
      syncedOnline: json['sync'] == true || json['sync'] == 'true',
    );
  }

  bool get isReceived =>
      status == 'RECEIVED' ||
      status == 'RECORDED' ||
      status == 'VERIFIED_ONLINE' ||
      status == 'OFFLINE_RECORDED';

  bool get isDuplicate => status == 'DUPLICATE' || status == 'ALREADY_RECORDED';

  @override
  String toString() =>
      'ACK($packetId → $status from $gatewayId, count=$attendeeCount, synced=$syncedOnline)';
}
