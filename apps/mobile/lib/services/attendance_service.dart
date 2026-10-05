import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/supabase_config.dart';
import '../models/attendance_session.dart';
import '../models/attendance_record.dart';
import '../models/classroom.dart';
import '../models/subject.dart';

class AttendanceService extends ChangeNotifier {
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal();

  AttendanceSession? _activeSession;
  AttendanceSession? get activeSession => _activeSession;

  final List<AttendanceRecord> _sessionRecords = [];
  List<AttendanceRecord> get sessionRecords => List.unmodifiable(_sessionRecords);

  RealtimeChannel? _sessionSubscription;
  RealtimeChannel? _recordsSubscription;

  // ─── TEACHER OPERATIONS ──────────────────────────────────────────────

  /// Fetch subjects assigned to a teacher.
  Future<List<Subject>> fetchTeacherSubjects(String teacherId) async {
    if (!SupabaseConfig.isInitialized) {
      return _mockSubjects;
    }

    try {
      final res = await SupabaseConfig.client
          .from('subjects')
          .select('*, classes(name)')
          .eq('teacher_id', teacherId);

      return (res as List)
          .map((item) => Subject.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[AttendanceService] fetchTeacherSubjects error: $e');
      return _mockSubjects;
    }
  }

  /// Fetch list of available classrooms.
  Future<List<Classroom>> fetchClassrooms() async {
    if (!SupabaseConfig.isInitialized) {
      return _mockClassrooms;
    }

    try {
      final res = await SupabaseConfig.client
          .from('classrooms')
          .select()
          .order('name');

      return (res as List)
          .map((item) => Classroom.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[AttendanceService] fetchClassrooms error: $e');
      return _mockClassrooms;
    }
  }

  /// Start a new attendance session.
  Future<AttendanceSession> startSession({
    required String subjectId,
    required String subjectName,
    required String subjectCode,
    required String classId,
    required String className,
    required String teacherId,
    required String teacherName,
    required String classroomId,
    required String classroomName,
    String? gatewayId,
    int durationMinutes = 5,
    String sessionType = 'LECTURE',
  }) async {
    final now = DateTime.now();
    final expiresAt = now.add(Duration(minutes: durationMinutes));

    if (!SupabaseConfig.isInitialized) {
      _activeSession = AttendanceSession(
        id: 'sess-${now.millisecondsSinceEpoch}',
        subjectId: subjectId,
        subjectName: subjectName,
        subjectCode: subjectCode,
        classId: classId,
        className: className,
        teacherId: teacherId,
        teacherName: teacherName,
        classroomId: classroomId,
        classroomName: classroomName,
        gatewayId: gatewayId ?? 'ESP32_GATEWAY_405',
        sessionType: sessionType,
        startedAt: now,
        expiresAt: expiresAt,
        status: SessionStatus.active,
        sessionNonce: 'nonce-${now.millisecondsSinceEpoch}',
      );
      _sessionRecords.clear();
      notifyListeners();
      return _activeSession!;
    }

    try {
      final insertData = {
        'subject_id': subjectId,
        'class_id': classId,
        'teacher_id': teacherId,
        'classroom_id': classroomId,
        'gateway_id': gatewayId ?? 'ESP32_GATEWAY_405',
        'session_type': sessionType,
        'started_at': now.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'status': 'ACTIVE',
      };

      final res = await SupabaseConfig.client
          .from('attendance_sessions')
          .insert(insertData)
          .select('*, subjects(name, code), classes(name), classrooms(name)')
          .single();

      _activeSession = AttendanceSession.fromJson(res);
      _sessionRecords.clear();
      notifyListeners();

      // Listen for incoming realtime records for this session
      listenToSessionRecords(_activeSession!.id);

      return _activeSession!;
    } catch (e) {
      debugPrint('[AttendanceService] startSession error: $e');
      rethrow;
    }
  }

  /// Close an active attendance session manually.
  Future<void> closeSession(String sessionId) async {
    if (_activeSession != null && _activeSession!.id == sessionId) {
      _activeSession = AttendanceSession(
        id: _activeSession!.id,
        subjectId: _activeSession!.subjectId,
        subjectName: _activeSession!.subjectName,
        subjectCode: _activeSession!.subjectCode,
        classId: _activeSession!.classId,
        className: _activeSession!.className,
        teacherId: _activeSession!.teacherId,
        teacherName: _activeSession!.teacherName,
        classroomId: _activeSession!.classroomId,
        classroomName: _activeSession!.classroomName,
        gatewayId: _activeSession!.gatewayId,
        sessionType: _activeSession!.sessionType,
        startedAt: _activeSession!.startedAt,
        expiresAt: _activeSession!.expiresAt,
        endedAt: DateTime.now(),
        status: SessionStatus.closed,
        sessionNonce: _activeSession!.sessionNonce,
      );
      notifyListeners();
    }

    if (SupabaseConfig.isInitialized) {
      try {
        await SupabaseConfig.client
            .from('attendance_sessions')
            .update({
              'status': 'CLOSED',
              'ended_at': DateTime.now().toIso8601String(),
            })
            .eq('id', sessionId);
      } catch (e) {
        debugPrint('[AttendanceService] closeSession error: $e');
      }
    }

    _recordsSubscription?.unsubscribe();
    _recordsSubscription = null;
  }

  /// Realtime subscription for teacher to see live student submissions.
  void listenToSessionRecords(String sessionId) {
    _recordsSubscription?.unsubscribe();
    if (!SupabaseConfig.isInitialized) return;

    try {
      _recordsSubscription = SupabaseConfig.client
          .channel('public:attendance_records:session=$sessionId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'attendance_records',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'session_id',
              value: sessionId,
            ),
            callback: (payload) {
              final newRecord = AttendanceRecord.fromJson(payload.newRecord);
              if (!_sessionRecords.any((r) => r.studentId == newRecord.studentId)) {
                _sessionRecords.insert(0, newRecord);
                notifyListeners();
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[AttendanceService] listenToSessionRecords error: $e');
    }
  }

  // ─── STUDENT OPERATIONS ──────────────────────────────────────────────

  /// Subscribe students to ACTIVE attendance sessions in realtime.
  void subscribeToActiveSessions({
    required String classId,
    required void Function(AttendanceSession?) onSessionChange,
  }) {
    _sessionSubscription?.unsubscribe();

    if (!SupabaseConfig.isInitialized) {
      // In mock/development mode, notify with the current in-memory active session
      onSessionChange(_activeSession);
      return;
    }

    try {
      // 1. Initial query for currently active session
      SupabaseConfig.client
          .from('attendance_sessions')
          .select('*, subjects(name, code), classes(name), classrooms(name)')
          .eq('class_id', classId)
          .eq('status', 'ACTIVE')
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle()
          .then((res) {
        if (res != null) {
          final session = AttendanceSession.fromJson(res);
          _activeSession = session;
          notifyListeners();
          onSessionChange(session);
        } else {
          onSessionChange(null);
        }
      });

      // 2. Realtime listener for attendance_sessions changes
      _sessionSubscription = SupabaseConfig.client
          .channel('public:attendance_sessions:class=$classId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'attendance_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'class_id',
              value: classId,
            ),
            callback: (payload) {
              final record = payload.newRecord;
              if (record.isNotEmpty && record['status'] == 'ACTIVE') {
                final session = AttendanceSession.fromJson(record);
                if (session.isActive) {
                  _activeSession = session;
                  notifyListeners();
                  onSessionChange(session);
                  return;
                }
              }
              _activeSession = null;
              notifyListeners();
              onSessionChange(null);
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[AttendanceService] subscribeToActiveSessions error: $e');
      onSessionChange(_activeSession);
    }
  }

  /// Phase 13: Temporary direct development attendance submission.
  Future<AttendanceRecord> submitDevelopmentAttendance({
    required String sessionId,
    required String studentId,
    required String studentName,
    required String rollNumber,
  }) async {
    final now = DateTime.now();
    final record = AttendanceRecord(
      id: 'rec-${now.millisecondsSinceEpoch}',
      sessionId: sessionId,
      studentId: studentId,
      studentName: studentName,
      rollNumber: rollNumber,
      timestamp: now,
      verifiedAt: now,
      status: 'PRESENT',
      isConfirmed: true,
      isSelf: true,
      verificationMethod: 'DEVELOPMENT_DIRECT',
    );

    if (!SupabaseConfig.isInitialized) {
      if (!_sessionRecords.any((r) => r.studentId == studentId)) {
        _sessionRecords.insert(0, record);
        notifyListeners();
      }
      return record;
    }

    try {
      final insertData = {
        'session_id': sessionId,
        'student_id': studentId,
        'status': 'PRESENT',
        'submitted_at': now.toIso8601String(),
        'verified_at': now.toIso8601String(),
        'verification_method': 'DEVELOPMENT_DIRECT',
      };

      final res = await SupabaseConfig.client
          .from('attendance_records')
          .insert(insertData)
          .select('*, profiles(name, roll_number)')
          .single();

      final saved = AttendanceRecord.fromJson(res);
      if (!_sessionRecords.any((r) => r.studentId == studentId)) {
        _sessionRecords.insert(0, saved);
        notifyListeners();
      }
      return saved;
    } catch (e) {
      debugPrint('[AttendanceService] submitDevelopmentAttendance error: $e');
      // Fallback
      if (!_sessionRecords.any((r) => r.studentId == studentId)) {
        _sessionRecords.insert(0, record);
        notifyListeners();
      }
      return record;
    }
  }

  /// Fetch past attendance history for a student.
  Future<List<AttendanceRecord>> fetchStudentHistory(String studentId) async {
    if (!SupabaseConfig.isInitialized) {
      return _sessionRecords;
    }

    try {
      final res = await SupabaseConfig.client
          .from('attendance_records')
          .select('*, attendance_sessions(subject_id, subjects(name, code))')
          .eq('student_id', studentId)
          .order('submitted_at', ascending: false);

      return (res as List)
          .map((item) => AttendanceRecord.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[AttendanceService] fetchStudentHistory error: $e');
      return _sessionRecords;
    }
  }

  @override
  void dispose() {
    _sessionSubscription?.unsubscribe();
    _recordsSubscription?.unsubscribe();
    super.dispose();
  }

  // ─── MOCK DATA PLACEHOLDERS ──────────────────────────────────────────

  static final List<Subject> _mockSubjects = [
    const Subject(
      id: '66666666-6666-6666-6666-666666666601',
      name: 'Database Management Systems',
      code: 'DBMS',
      classId: '33333333-3333-3333-3333-333333333301',
      className: 'CMPN-C',
      teacherId: '44444444-4444-4444-4444-444444444401',
    ),
    const Subject(
      id: '66666666-6666-6666-6666-666666666602',
      name: 'Computer Networks',
      code: 'CN',
      classId: '33333333-3333-3333-3333-333333333301',
      className: 'CMPN-C',
      teacherId: '44444444-4444-4444-4444-444444444401',
    ),
  ];

  static final List<Classroom> _mockClassrooms = [
    const Classroom(
      id: '11111111-1111-1111-1111-111111111101',
      name: 'Room 405',
      building: 'Main Academic Block',
      gatewayId: 'ESP32_GATEWAY_405',
    ),
    const Classroom(
      id: '11111111-1111-1111-1111-111111111102',
      name: 'Lab 201',
      building: 'Computer Wing',
      gatewayId: 'ESP32_GATEWAY_201',
    ),
  ];
}
