// Manages the application-level device identifier.
//
// Generates and persists a unique device ID in the format:
//   {PLATFORM}-{4 hex chars}   e.g. IOS-A1B2, ANDROID-C3D4
//
// Privacy: This ID is ephemeral and application-scoped. It does NOT use
// the phone's hardware Bluetooth MAC address. The ID is stored locally
// in SharedPreferences and is only transmitted during Phase 4 testing.
// In production, device IDs will be replaced with cryptographic session tokens.

import 'dart:io';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdService {
  static const _key = 'bma_device_id';
  static String? _cachedId;

  /// Get or generate the device ID.
  static Future<String> getDeviceId() async {
    if (_cachedId != null) return _cachedId!;

    final prefs = await SharedPreferences.getInstance();
    _cachedId = prefs.getString(_key);

    if (_cachedId == null || _cachedId!.isEmpty) {
      _cachedId = _generate();
      await prefs.setString(_key, _cachedId!);
    }

    return _cachedId!;
  }

  /// Get the platform string.
  static String get platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  /// Get the platform prefix for the device ID.
  static String get platformPrefix {
    if (Platform.isIOS) return 'IOS';
    if (Platform.isAndroid) return 'ANDROID';
    return 'UNKNOWN';
  }

  static String _generate() {
    final hex = _randomHex(4);
    return '$platformPrefix-$hex';
  }

  static String _randomHex(int length) {
    final rng = Random.secure();
    final chars = '0123456789ABCDEF';
    return List.generate(length, (_) => chars[rng.nextInt(16)]).join();
  }
}
