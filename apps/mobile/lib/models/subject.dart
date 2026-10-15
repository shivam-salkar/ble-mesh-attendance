class Subject {
  final String id;
  final String name;
  final String code;
  final String classId;
  final String? className;
  final String teacherId;
  final String? teacherName;
  final String? roomCode;
  final String? scheduleTime;
  final String? classroomId;
  final String? classroomName;
  final String? gatewayId;

  const Subject({
    required this.id,
    required this.name,
    required this.code,
    required this.classId,
    this.className,
    required this.teacherId,
    this.teacherName,
    this.roomCode,
    this.scheduleTime,
    this.classroomId,
    this.classroomName,
    this.gatewayId,
  });

  factory Subject.fromJson(Map<String, dynamic> json) {
    String? cName;
    if (json['class_name'] is String) {
      cName = json['class_name'] as String;
    } else if (json['classes'] is Map) {
      cName = json['classes']['name'] as String?;
    }

    String? tName;
    if (json['teacher_name'] is String) {
      tName = json['teacher_name'] as String;
    } else if (json['profiles'] is Map) {
      tName = json['profiles']['name'] as String?;
    }

    String? crName;
    String? gwId;
    if (json['classrooms'] is Map) {
      crName = json['classrooms']['name'] as String?;
      gwId = json['classrooms']['gateway_id'] as String?;
    } else {
      crName = json['classroom_name'] as String?;
      gwId = json['gateway_id'] as String?;
    }

    return Subject(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Subject',
      code: json['code'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      className: cName,
      teacherId: json['teacher_id'] as String? ?? '',
      teacherName: tName,
      roomCode: json['room_code'] as String?,
      scheduleTime: json['schedule_time'] as String?,
      classroomId: json['classroom_id'] as String?,
      classroomName: crName,
      gatewayId: gwId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'code': code,
      'class_id': classId,
      'class_name': className,
      'teacher_id': teacherId,
      'teacher_name': teacherName,
      'room_code': roomCode,
      'schedule_time': scheduleTime,
      'classroom_id': classroomId,
      'classroom_name': classroomName,
      'gateway_id': gatewayId,
    };
  }

  Subject copyWith({
    String? id,
    String? name,
    String? code,
    String? classId,
    String? className,
    String? teacherId,
    String? teacherName,
    String? roomCode,
    String? scheduleTime,
    String? classroomId,
    String? classroomName,
    String? gatewayId,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      classId: classId ?? this.classId,
      className: className ?? this.className,
      teacherId: teacherId ?? this.teacherId,
      teacherName: teacherName ?? this.teacherName,
      roomCode: roomCode ?? this.roomCode,
      scheduleTime: scheduleTime ?? this.scheduleTime,
      classroomId: classroomId ?? this.classroomId,
      classroomName: classroomName ?? this.classroomName,
      gatewayId: gatewayId ?? this.gatewayId,
    );
  }
}
