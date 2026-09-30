// BLE event log entries displayed in the test UI.

enum BleEventType {
  tx,
  rx,
  forward,
  duplicate,
  ack,
  error,
  connect,
  disconnect,
  scan,
  info,
}

class BleEvent {
  final DateTime timestamp;
  final BleEventType type;
  final String message;
  final String? deviceId;

  BleEvent({
    DateTime? timestamp,
    required this.type,
    required this.message,
    this.deviceId,
  }) : timestamp = timestamp ?? DateTime.now();

  String get prefix {
    switch (type) {
      case BleEventType.tx:
        return 'TX →';
      case BleEventType.rx:
        return 'RX ←';
      case BleEventType.forward:
        return 'FWD →';
      case BleEventType.duplicate:
        return 'DUP ✕';
      case BleEventType.ack:
        return 'ACK ✓';
      case BleEventType.error:
        return 'ERR ✗';
      case BleEventType.connect:
        return 'CON ●';
      case BleEventType.disconnect:
        return 'DIS ○';
      case BleEventType.scan:
        return 'SCN ◎';
      case BleEventType.info:
        return 'INF ℹ';
    }
  }

  String get timeStr {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  String toString() => '$timeStr $prefix $message';
}
