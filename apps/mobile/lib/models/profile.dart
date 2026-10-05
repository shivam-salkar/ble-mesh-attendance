enum UserRole {
  student,
  teacher,
  admin;

  static UserRole fromString(String role) {
    switch (role.toLowerCase().trim()) {
      case 'teacher':
        return UserRole.teacher;
      case 'admin':
        return UserRole.admin;
      case 'student':
      default:
        return UserRole.student;
    }
  }

  String get displayName {
    switch (this) {
      case UserRole.teacher:
        return 'Teacher';
      case UserRole.admin:
        return 'Admin';
      case UserRole.student:
        return 'Student';
    }
  }
}

class UserProfile {
  final String id;
  final String? authUserId;
  final String name;
  final String email;
  final String? rollNumber;
  final UserRole role;
  final DateTime createdAt;

  const UserProfile({
    required this.id,
    this.authUserId,
    required this.name,
    required this.email,
    this.rollNumber,
    required this.role,
    required this.createdAt,
  });

  bool get isStudent => role == UserRole.student;
  bool get isTeacher => role == UserRole.teacher;
  bool get isAdmin => role == UserRole.admin;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      authUserId: json['auth_user_id'] as String?,
      name: json['name'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      rollNumber: json['roll_number'] as String?,
      role: UserRole.fromString(json['role'] as String? ?? 'student'),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'auth_user_id': authUserId,
      'name': name,
      'email': email,
      'roll_number': rollNumber,
      'role': role.name,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
