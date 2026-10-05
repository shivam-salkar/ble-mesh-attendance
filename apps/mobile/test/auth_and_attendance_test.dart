import 'package:flutter_test/flutter_test.dart';
import 'package:ble_mesh_attendance/models/profile.dart';
import 'package:ble_mesh_attendance/models/attendance_session.dart';
import 'package:ble_mesh_attendance/services/auth_service.dart';
import 'package:ble_mesh_attendance/services/attendance_service.dart';

void main() {
  group('AuthService Tests', () {
    final authService = AuthService();

    test('Teacher demo login returns teacher profile', () async {
      final profile = await authService.signIn(
        email: 'teacher@college.edu',
        password: 'any_password',
      );

      expect(profile.role, UserRole.teacher);
      expect(profile.isTeacher, isTrue);
      expect(profile.isStudent, isFalse);
      expect(authService.currentProfile?.email, 'teacher@college.edu');
    });

    test('Student demo login returns student profile', () async {
      final profile = await authService.signIn(
        email: 'student@college.edu',
        password: 'any_password',
      );

      expect(profile.role, UserRole.student);
      expect(profile.isStudent, isTrue);
      expect(profile.isTeacher, isFalse);
      expect(authService.currentProfile?.name, 'Aryan Darekar');
    });

    test('Sign out clears the active profile', () async {
      await authService.signOut();
      expect(authService.currentProfile, isNull);
    });
  });

  group('AttendanceSession Model Tests', () {
    test('AttendanceSession calculation methods work correctly', () {
      final now = DateTime.now();
      final activeSession = AttendanceSession(
        id: 'sess-001',
        classId: 'class-1',
        subjectId: 'subj-1',
        teacherId: 'prof-1',
        status: SessionStatus.active,
        startedAt: now.subtract(const Duration(minutes: 2)),
        expiresAt: now.add(const Duration(minutes: 8)),
        sessionNonce: 'nonce-abcd',
        subjectName: 'Database Management Systems',
        subjectCode: 'CS301',
        classroomName: 'Room 405',
      );

      expect(activeSession.isActive, isTrue);
      expect(activeSession.timeRemaining.inSeconds, greaterThan(0));
      expect(activeSession.timeRemaining.inMinutes, lessThanOrEqualTo(8));

      final closedSession = AttendanceSession(
        id: 'sess-002',
        classId: 'class-1',
        subjectId: 'subj-1',
        teacherId: 'prof-1',
        status: SessionStatus.closed,
        startedAt: now.subtract(const Duration(minutes: 20)),
        expiresAt: now.subtract(const Duration(minutes: 5)),
        endedAt: now.subtract(const Duration(minutes: 5)),
        sessionNonce: 'nonce-abcd',
      );

      expect(closedSession.isActive, isFalse);
      expect(closedSession.timeRemaining, equals(Duration.zero));
    });
  });

  group('AttendanceService In-Memory/Dev Flow Tests', () {
    final attendanceService = AttendanceService();

    test('Start session creates active session and notifies listeners', () async {
      final session = await attendanceService.startSession(
        subjectId: 'subj-cn',
        subjectName: 'Computer Networks',
        subjectCode: 'CS302',
        classId: 'class-cmpn-c',
        className: 'TE CMPN-C',
        teacherId: 'teacher-1',
        teacherName: 'Prof. Sharma',
        classroomId: 'room-405',
        classroomName: 'Lab 405',
        durationMinutes: 10,
      );

      expect(session.id, isNotEmpty);
      expect(session.subjectName, 'Computer Networks');
      expect(session.isActive, isTrue);
      expect(attendanceService.activeSession?.id, session.id);
    });

    test('Student marks development attendance into session records', () async {
      final active = attendanceService.activeSession;
      expect(active, isNotNull);

      // Student submits
      final record = await attendanceService.submitDevelopmentAttendance(
        sessionId: active!.id,
        studentId: 'student-dev-1',
        studentName: 'Rahul Sharma',
        rollNumber: '101',
      );

      expect(record.sessionId, active.id);
      expect(record.studentId, 'student-dev-1');
      expect(record.status, 'PRESENT');
      expect(attendanceService.sessionRecords.length, 1);
      expect(attendanceService.sessionRecords.first.studentName, 'Rahul Sharma');

      // Duplicate submission does not duplicate record
      final secondRecord = await attendanceService.submitDevelopmentAttendance(
        sessionId: active.id,
        studentId: 'student-dev-1',
        studentName: 'Rahul Sharma',
        rollNumber: '101',
      );
      expect(secondRecord.studentId, 'student-dev-1');
      expect(attendanceService.sessionRecords.length, 1);
    });

    test('Teacher closes session', () async {
      final active = attendanceService.activeSession;
      expect(active, isNotNull);

      await attendanceService.closeSession(active!.id);
      expect(attendanceService.activeSession?.status, SessionStatus.closed);
      expect(attendanceService.activeSession?.isActive, isFalse);
    });
  });
}
