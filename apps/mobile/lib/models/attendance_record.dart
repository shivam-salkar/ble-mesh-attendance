// Attendance Record Model
//
// Represents an attendee captured during a classroom lecture session.

class AttendanceRecord {
  final String studentName;
  final String studentId;
  final String macAddress;
  final String deviceId;
  final DateTime timestamp;
  final int hopCount;
  final bool isConfirmed;
  final bool isSelf;

  const AttendanceRecord({
    required this.studentName,
    required this.studentId,
    required this.macAddress,
    required this.deviceId,
    required this.timestamp,
    this.hopCount = 0,
    this.isConfirmed = true,
    this.isSelf = false,
  });

  AttendanceRecord copyWith({
    String? studentName,
    String? studentId,
    String? macAddress,
    String? deviceId,
    DateTime? timestamp,
    int? hopCount,
    bool? isConfirmed,
    bool? isSelf,
  }) {
    return AttendanceRecord(
      studentName: studentName ?? this.studentName,
      studentId: studentId ?? this.studentId,
      macAddress: macAddress ?? this.macAddress,
      deviceId: deviceId ?? this.deviceId,
      timestamp: timestamp ?? this.timestamp,
      hopCount: hopCount ?? this.hopCount,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      isSelf: isSelf ?? this.isSelf,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'studentName': studentName,
      'studentId': studentId,
      'macAddress': macAddress,
      'deviceId': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'hopCount': hopCount,
      'isConfirmed': isConfirmed,
      'isSelf': isSelf,
    };
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      studentName: json['studentName'] as String? ?? 'Student',
      studentId: json['studentId'] as String? ?? '',
      macAddress: json['macAddress'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      hopCount: json['hopCount'] as int? ?? 0,
      isConfirmed: json['isConfirmed'] as bool? ?? true,
      isSelf: json['isSelf'] as bool? ?? false,
    );
  }
}
