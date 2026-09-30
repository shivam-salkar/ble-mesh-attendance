// Phase 4 — Relay engine with duplicate suppression.
//
// Implements the relay algorithm:
//   receive(packet) →
//     if pid seen: ignore
//     if ttl ≤ 0: ignore
//     mark pid as seen
//     hc += 1, ttl -= 1
//     forward

import '../models/relay_packet.dart';

class RelayEngine {
  /// Maximum cached packet IDs.
  static const int maxCacheSize = 128;

  /// Cache expiry duration.
  static const Duration cacheExpiry = Duration(minutes: 5);

  /// Seen packet ID cache: packetId → timestamp.
  final Map<String, DateTime> _seenPackets = {};

  /// Process an incoming relay packet.
  /// Returns a [RelayResult] indicating what happened.
  RelayResult processIncoming(RelayPacket packet) {
    _cleanExpired();

    // Check duplicate
    if (_seenPackets.containsKey(packet.packetId)) {
      return RelayResult(
        action: RelayAction.duplicate,
        packet: packet,
        reason: 'Packet ${packet.packetId} already seen',
      );
    }

    // Check TTL
    if (packet.ttl <= 0) {
      return RelayResult(
        action: RelayAction.ttlExpired,
        packet: packet,
        reason: 'TTL expired for ${packet.packetId}',
      );
    }

    // Validate
    if (!packet.isValid) {
      return RelayResult(
        action: RelayAction.invalid,
        packet: packet,
        reason: 'Invalid packet: ${packet.packetId}',
      );
    }

    // Mark as seen
    _seenPackets[packet.packetId] = DateTime.now();
    _enforceMaxSize();

    // Create forwarded version
    final forwarded = packet.forwarded();

    return RelayResult(
      action: RelayAction.forward,
      packet: forwarded,
      reason: 'Forwarding ${packet.packetId} (hop ${packet.hopCount} → ${forwarded.hopCount})',
    );
  }

  /// Check if a packet ID has been seen.
  bool hasSeen(String packetId) {
    _cleanExpired();
    return _seenPackets.containsKey(packetId);
  }

  /// Mark a packet ID as seen (for locally originated packets).
  void markSeen(String packetId) {
    _seenPackets[packetId] = DateTime.now();
    _enforceMaxSize();
  }

  /// Remove expired entries.
  void _cleanExpired() {
    final cutoff = DateTime.now().subtract(cacheExpiry);
    _seenPackets.removeWhere((_, timestamp) => timestamp.isBefore(cutoff));
  }

  /// Enforce maximum cache size by removing oldest entries.
  void _enforceMaxSize() {
    while (_seenPackets.length > maxCacheSize) {
      // Find oldest
      String? oldestKey;
      DateTime? oldestTime;
      for (final entry in _seenPackets.entries) {
        if (oldestTime == null || entry.value.isBefore(oldestTime)) {
          oldestKey = entry.key;
          oldestTime = entry.value;
        }
      }
      if (oldestKey != null) {
        _seenPackets.remove(oldestKey);
      }
    }
  }

  /// Clear all cached entries.
  void clear() => _seenPackets.clear();

  /// Number of currently cached entries.
  int get cacheSize => _seenPackets.length;
}

enum RelayAction {
  forward,
  duplicate,
  ttlExpired,
  invalid,
}

class RelayResult {
  final RelayAction action;
  final RelayPacket packet;
  final String reason;

  const RelayResult({
    required this.action,
    required this.packet,
    required this.reason,
  });

  bool get shouldForward => action == RelayAction.forward;
}
