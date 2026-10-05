class Subject {
  final String id;
  final String name;
  final String code;
  final String classId;
  final String? className;
  final String teacherId;

  const Subject({
    required this.id,
    required this.name,
    required this.code,
    required this.classId,
    this.className,
    required this.teacherId,
  });

  factory Subject.fromJson(Map<String, dynamic> json) {
    return Subject(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Subject',
      code: json['code'] as String? ?? '',
      classId: json['class_id'] as String? ?? '',
      className: json['class_name'] as String? ??
          (json['classes'] is Map ? json['classes']['name'] as String? : null),
      teacherId: json['teacher_id'] as String? ?? '',
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
    };
  }
}
