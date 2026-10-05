// Attendance Record Model
//
// Represents an attendee record both in Supabase and captured during a classroom session.

class AttendanceRecord {
  final String? id;
  final String? sessionId;
  final String studentName;
  final String studentId;
  final String? rollNumber;
  final String macAddress;
  final String deviceId;
  final DateTime timestamp;
  final DateTime? verifiedAt;
  final int hopCount;
  final String status;
  final bool isConfirmed;
  final bool isSelf;
  final bool faceVerified;
  final bool gatewayVerified;
  final String? verificationMethod;

  const AttendanceRecord({
    this.id,
    this.sessionId,
    required this.studentName,
    required this.studentId,
    this.rollNumber,
    this.macAddress = '',
    this.deviceId = '',
    required this.timestamp,
    this.verifiedAt,
    this.hopCount = 0,
    this.status = 'PRESENT',
    this.isConfirmed = true,
    this.isSelf = false,
    this.faceVerified = false,
    this.gatewayVerified = false,
    this.verificationMethod,
  });

  bool get isPresent => status == 'PRESENT';

  AttendanceRecord copyWith({
    String? id,
    String? sessionId,
    String? studentName,
    String? studentId,
    String? rollNumber,
    String? macAddress,
    String? deviceId,
    DateTime? timestamp,
    DateTime? verifiedAt,
    int? hopCount,
    String? status,
    bool? isConfirmed,
    bool? isSelf,
    bool? faceVerified,
    bool? gatewayVerified,
    String? verificationMethod,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      studentName: studentName ?? this.studentName,
      studentId: studentId ?? this.studentId,
      rollNumber: rollNumber ?? this.rollNumber,
      macAddress: macAddress ?? this.macAddress,
      deviceId: deviceId ?? this.deviceId,
      timestamp: timestamp ?? this.timestamp,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      hopCount: hopCount ?? this.hopCount,
      status: status ?? this.status,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      isSelf: isSelf ?? this.isSelf,
      faceVerified: faceVerified ?? this.faceVerified,
      gatewayVerified: gatewayVerified ?? this.gatewayVerified,
      verificationMethod: verificationMethod ?? this.verificationMethod,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      'studentName': studentName,
      'studentId': studentId,
      if (rollNumber != null) 'roll_number': rollNumber,
      'macAddress': macAddress,
      'deviceId': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'status': status,
      'hopCount': hopCount,
      'isConfirmed': isConfirmed,
      'isSelf': isSelf,
      'face_verified': faceVerified,
      'gateway_verified': gatewayVerified,
      if (verificationMethod != null) 'verification_method': verificationMethod,
    };
  }

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    // Check if coming from Supabase join (with profiles)
    String name = 'Student';
    String? roll;
    if (json['profiles'] is Map) {
      name = json['profiles']['name'] as String? ?? name;
      roll = json['profiles']['roll_number'] as String?;
    } else {
      name = json['studentName'] as String? ?? (json['name'] as String? ?? 'Student');
      roll = json['roll_number'] as String? ?? (json['rollNumber'] as String?);
    }

    final id = json['id'] as String?;
    final sessionId = json['session_id'] as String?;
    final studentId = json['student_id'] as String? ?? (json['studentId'] as String? ?? '');
    final status = json['status'] as String? ?? 'PRESENT';

    return AttendanceRecord(
      id: id,
      sessionId: sessionId,
      studentName: name,
      studentId: studentId,
      rollNumber: roll,
      macAddress: json['macAddress'] as String? ?? (json['mac'] as String? ?? ''),
      deviceId: json['deviceId'] as String? ?? (json['gateway_id'] as String? ?? ''),
      timestamp: DateTime.tryParse(
            json['submitted_at'] as String? ?? (json['timestamp'] as String? ?? ''),
          ) ??
          DateTime.now(),
      verifiedAt: json['verified_at'] != null
          ? DateTime.tryParse(json['verified_at'] as String)
          : null,
      hopCount: json['hopCount'] as int? ?? 0,
      status: status,
      isConfirmed: json['isConfirmed'] as bool? ?? (status == 'PRESENT'),
      isSelf: json['isSelf'] as bool? ?? false,
      faceVerified: json['face_verified'] as bool? ?? false,
      gatewayVerified: json['gateway_verified'] as bool? ?? false,
      verificationMethod: json['verification_method'] as String?,
    );
  }
}
