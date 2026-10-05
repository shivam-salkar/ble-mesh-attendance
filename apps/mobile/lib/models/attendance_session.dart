enum SessionStatus {
  active,
  closed,
  expired;

  static SessionStatus fromString(String status) {
    switch (status.toUpperCase().trim()) {
      case 'ACTIVE':
        return SessionStatus.active;
      case 'CLOSED':
        return SessionStatus.closed;
      case 'EXPIRED':
      default:
        return SessionStatus.expired;
    }
  }

  String get dbValue => name.toUpperCase();
}

class AttendanceSession {
  final String id;
  final String subjectId;
  final String? subjectName;
  final String? subjectCode;
  final String classId;
  final String? className;
  final String teacherId;
  final String? teacherName;
  final String? classroomId;
  final String? classroomName;
  final String? gatewayId;
  final String sessionType;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime? endedAt;
  final SessionStatus status;
  final String sessionNonce;

  const AttendanceSession({
    required this.id,
    required this.subjectId,
    this.subjectName,
    this.subjectCode,
    required this.classId,
    this.className,
    required this.teacherId,
    this.teacherName,
    this.classroomId,
    this.classroomName,
    this.gatewayId,
    this.sessionType = 'LECTURE',
    required this.startedAt,
    required this.expiresAt,
    this.endedAt,
    this.status = SessionStatus.active,
    required this.sessionNonce,
  });

  bool get isActive {
    if (status != SessionStatus.active) return false;
    return DateTime.now().isBefore(expiresAt);
  }

  Duration get timeRemaining {
    final now = DateTime.now();
    if (now.isAfter(expiresAt)) return Duration.zero;
    return expiresAt.difference(now);
  }

  factory AttendanceSession.fromJson(Map<String, dynamic> json) {
    final expiresAt = json['expires_at'] != null
        ? DateTime.tryParse(json['expires_at'] as String) ?? DateTime.now()
        : DateTime.now();

    var status = SessionStatus.fromString(json['status'] as String? ?? 'ACTIVE');
    if (status == SessionStatus.active && DateTime.now().isAfter(expiresAt)) {
      status = SessionStatus.expired;
    }

    return AttendanceSession(
      id: json['id'] as String,
      subjectId: json['subject_id'] as String? ?? '',
      subjectName: json['subjects'] is Map
          ? (json['subjects']['name'] as String?)
          : (json['subject_name'] as String?),
      subjectCode: json['subjects'] is Map
          ? (json['subjects']['code'] as String?)
          : (json['subject_code'] as String?),
      classId: json['class_id'] as String? ?? '',
      className: json['classes'] is Map
          ? (json['classes']['name'] as String?)
          : (json['class_name'] as String?),
      teacherId: json['teacher_id'] as String? ?? '',
      teacherName: json['profiles'] is Map
          ? (json['profiles']['name'] as String?)
          : (json['teacher_name'] as String?),
      classroomId: json['classroom_id'] as String?,
      classroomName: json['classrooms'] is Map
          ? (json['classrooms']['name'] as String?)
          : (json['classroom_name'] as String?),
      gatewayId: json['gateway_id'] as String?,
      sessionType: json['session_type'] as String? ?? 'LECTURE',
      startedAt: json['started_at'] != null
          ? DateTime.tryParse(json['started_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: expiresAt,
      endedAt: json['ended_at'] != null
          ? DateTime.tryParse(json['ended_at'] as String)
          : null,
      status: status,
      sessionNonce: json['session_nonce'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'subject_id': subjectId,
      'class_id': classId,
      'teacher_id': teacherId,
      'classroom_id': classroomId,
      'gateway_id': gatewayId,
      'session_type': sessionType,
      'started_at': startedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'status': status.dbValue,
      'session_nonce': sessionNonce,
    };
  }
}
