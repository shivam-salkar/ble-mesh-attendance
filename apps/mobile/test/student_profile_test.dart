import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_mesh_attendance/services/student_profile_service.dart';
import 'package:ble_mesh_attendance/models/attendance_record.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StudentProfileService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('generates valid IEEE 802 MAC format and default profile', () async {
      final profile = await StudentProfileService.getProfile();

      expect(profile.macAddress, isNotEmpty);
      expect(
        RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(profile.macAddress),
        isTrue,
        reason: 'MAC address must match standard 6-byte colon format XX:XX:XX:XX:XX:XX',
      );
      expect(profile.studentId, isNotEmpty);
    });

    test('updates and persists student name and roll number', () async {
      await StudentProfileService.saveProfile(name: 'Rahul Sharma', studentId: '2024CS042');
      final profile1 = await StudentProfileService.getProfile();

      expect(profile1.name, equals('Rahul Sharma'));
      expect(profile1.studentId, equals('2024CS042'));

      // Check persistence with a fresh call
      final profile2 = await StudentProfileService.getProfile();
      expect(profile2.name, equals('Rahul Sharma'));
      expect(profile2.studentId, equals('2024CS042'));
      expect(profile2.macAddress, equals(profile1.macAddress));
    });
  });

  group('AttendanceRecord', () {
    test('AttendanceRecord serializes and parses properly', () {
      final record = AttendanceRecord(
        studentName: 'Priya Patel',
        studentId: '2024EC019',
        macAddress: 'CA:FE:BA:BE:01:23',
        deviceId: 'AND-12345678',
        timestamp: DateTime.now(),
        hopCount: 1,
        isConfirmed: true,
        isSelf: false,
      );

      final json = record.toJson();
      expect(json['studentName'], equals('Priya Patel'));
      expect(json['studentId'], equals('2024EC019'));
      expect(json['macAddress'], equals('CA:FE:BA:BE:01:23'));
      expect(json['hopCount'], equals(1));
      expect(json['isConfirmed'], isTrue);

      final parsed = AttendanceRecord.fromJson(json);
      expect(parsed.studentName, equals(record.studentName));
      expect(parsed.studentId, equals(record.studentId));
      expect(parsed.macAddress, equals(record.macAddress));
      expect(parsed.isConfirmed, isTrue);
    });
  });
}
