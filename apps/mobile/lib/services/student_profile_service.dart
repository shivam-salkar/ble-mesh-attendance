// Student Profile Service
//
// Manages persistent storage for:
// - Student Full Name (e.g. "Aryan Sharma")
// - Student Roll Number / ID (e.g. "STU-2026-001")
// - Device MAC Address (formatted as XX:XX:XX:XX:XX:XX)
//
// Stored persistently using SharedPreferences.

import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'device_id_service.dart';

class StudentProfile {
  final String name;
  final String studentId;
  final String macAddress;
  final String deviceId;

  const StudentProfile({
    required this.name,
    required this.studentId,
    required this.macAddress,
    required this.deviceId,
  });

  bool get isConfigured => name.trim().isNotEmpty && studentId.trim().isNotEmpty;
}

class StudentProfileService {
  static const _keyName = 'bma_student_name';
  static const _keyStudentId = 'bma_student_id';
  static const _keyMacAddress = 'bma_mac_address';

  static StudentProfile? _cachedProfile;

  /// Load or initialize the student profile.
  static Future<StudentProfile> getProfile() async {
    if (_cachedProfile != null) return _cachedProfile!;

    final prefs = await SharedPreferences.getInstance();
    final deviceId = await DeviceIdService.getDeviceId();

    String name = prefs.getString(_keyName) ?? '';
    String studentId = prefs.getString(_keyStudentId) ?? '';
    String? mac = prefs.getString(_keyMacAddress);

    // If no MAC address exists, generate a persistent pseudo-hardware MAC address
    if (mac == null || mac.isEmpty) {
      mac = _generateMacAddress(deviceId);
      await prefs.setString(_keyMacAddress, mac);
    }

    // Default student ID from device ID if not entered yet
    if (studentId.isEmpty) {
      studentId = 'STU-${deviceId.split('-').last}';
      await prefs.setString(_keyStudentId, studentId);
    }

    _cachedProfile = StudentProfile(
      name: name,
      studentId: studentId,
      macAddress: mac,
      deviceId: deviceId,
    );

    return _cachedProfile!;
  }

  /// Update and persist student profile details.
  static Future<StudentProfile> saveProfile({
    required String name,
    required String studentId,
    String? macAddress,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = await DeviceIdService.getDeviceId();

    String mac = macAddress?.trim() ?? '';
    if (mac.isEmpty) {
      mac = prefs.getString(_keyMacAddress) ?? _generateMacAddress(deviceId);
    }

    await prefs.setString(_keyName, name.trim());
    await prefs.setString(_keyStudentId, studentId.trim());
    await prefs.setString(_keyMacAddress, mac);

    _cachedProfile = StudentProfile(
      name: name.trim(),
      studentId: studentId.trim(),
      macAddress: mac,
      deviceId: deviceId,
    );

    return _cachedProfile!;
  }

  /// Generates a valid IEEE 802 locally-administered MAC address.
  /// Formatted as: XX:XX:XX:XX:XX:XX
  static String _generateMacAddress(String seed) {
    final rng = Random(seed.hashCode ^ DateTime.now().millisecondsSinceEpoch);
    // Byte 0: Locally administered (bit 1=1) and unicast (bit 0=0), e.g. 0xDA, 0xC4, 0xF6
    final byte0 = (rng.nextInt(256) & 0xFC) | 0x02;
    final b = List.generate(5, (_) => rng.nextInt(256));
    return [
      byte0.toRadixString(16).padLeft(2, '0').toUpperCase(),
      b[0].toRadixString(16).padLeft(2, '0').toUpperCase(),
      b[1].toRadixString(16).padLeft(2, '0').toUpperCase(),
      b[2].toRadixString(16).padLeft(2, '0').toUpperCase(),
      b[3].toRadixString(16).padLeft(2, '0').toUpperCase(),
      b[4].toRadixString(16).padLeft(2, '0').toUpperCase(),
    ].join(':');
  }
}
