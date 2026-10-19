import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  final Set<String> _studentJoinedRoomIds = {};

  RealtimeChannel? _sessionSubscription;
  RealtimeChannel? _recordsSubscription;

  static final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  /// Check whether a string adheres to standard RFC 4122 UUID format.
  static bool isValidUuid(String? id) {
    if (id == null) return false;
    return _uuidRegex.hasMatch(id.trim());
  }

  static String _teacherStorageKey(String? teacherId, {String? email}) {
    final cleanEmail = email?.trim().toLowerCase();
    if (cleanEmail != null && cleanEmail.isNotEmpty) {
      return 'teacher_rooms_${cleanEmail.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
    }
    final cleanId = teacherId?.trim().toLowerCase() ?? 'default_teacher';
    return 'teacher_rooms_${cleanId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')}';
  }

  /// Load locally persisted subjects created by a teacher account.
  Future<List<Subject>> loadPersistedTeacherSubjects(String? teacherId, {String? email}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _teacherStorageKey(teacherId, email: email);
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        return list.map((e) => Subject.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('[AttendanceService] loadPersistedTeacherSubjects error: $e');
    }
    return [];
  }

  /// Save persistent list of subjects created by a teacher account.
  Future<void> savePersistedTeacherSubjects(
    String? teacherId,
    List<Subject> subjects, {
    String? email,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _teacherStorageKey(teacherId, email: email);
      final jsonList = subjects.map((s) => s.toJson()).toList();
      await prefs.setString(key, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[AttendanceService] savePersistedTeacherSubjects error: $e');
    }
  }

  /// Persist a single newly created subject to local storage for the teacher account.
  Future<void> persistSingleTeacherSubject(
    String? teacherId,
    Subject subject, {
    String? email,
  }) async {
    try {
      final existing = await loadPersistedTeacherSubjects(teacherId, email: email);
      final updated = <Subject>[subject];
      for (final s in existing) {
        if (s.id != subject.id && s.roomCode != subject.roomCode) {
          updated.add(s);
        }
      }
      await savePersistedTeacherSubjects(teacherId, updated, email: email);
    } catch (e) {
      debugPrint('[AttendanceService] persistSingleTeacherSubject error: $e');
    }
  }

  /// Resolves any teacher identifier (timestamp, mock string, or auth user ID)
  /// into a guaranteed valid profile UUID that exists in `public.profiles`.
  Future<String> resolveTeacherUuid(
    String? teacherId, {
    String? email,
    String? name,
  }) async {
    const knownTeacherUuid = 'cec26a0c-1c06-4755-8625-9b3dbe266746';

    if (!SupabaseConfig.isInitialized) {
      if (isValidUuid(teacherId)) return teacherId!.trim();
      return knownTeacherUuid;
    }

    try {
      // 1. If input is already a valid UUID, verify it exists in profiles
      if (isValidUuid(teacherId)) {
        final existing = await SupabaseConfig.client
            .from('profiles')
            .select('id')
            .eq('id', teacherId!.trim())
            .maybeSingle();
        if (existing != null && existing['id'] != null) {
          return existing['id'] as String;
        }
      }

      // 2. Check if currently authenticated Supabase user has a profile
      final currentAuthUser = SupabaseConfig.client.auth.currentUser;
      if (currentAuthUser != null) {
        final byAuth = await SupabaseConfig.client
            .from('profiles')
            .select('id')
            .eq('auth_user_id', currentAuthUser.id)
            .maybeSingle();
        if (byAuth != null && byAuth['id'] != null) {
          return byAuth['id'] as String;
        }

        final authEmail = currentAuthUser.email?.trim().toLowerCase();
        if (authEmail != null && authEmail.isNotEmpty) {
          final byEmail = await SupabaseConfig.client
              .from('profiles')
              .select('id')
              .eq('email', authEmail)
              .maybeSingle();
          if (byEmail != null && byEmail['id'] != null) {
            final id = byEmail['id'] as String;
            try {
              await SupabaseConfig.client
                  .from('profiles')
                  .update({'auth_user_id': currentAuthUser.id})
                  .eq('id', id);
            } catch (_) {}
            return id;
          }
        }
      }

      // 3. Search profile by provided email
      final searchEmail = (email ?? currentAuthUser?.email)?.trim().toLowerCase();
      if (searchEmail != null && searchEmail.isNotEmpty) {
        final byEmail = await SupabaseConfig.client
            .from('profiles')
            .select('id')
            .eq('email', searchEmail)
            .maybeSingle();
        if (byEmail != null && byEmail['id'] != null) {
          return byEmail['id'] as String;
        }
      }

      // 4. Auto-create this teacher's dedicated profile with their own email & ID
      final targetEmail = searchEmail ?? 'teacher@college.edu';
      final targetName = name ?? currentAuthUser?.userMetadata?['name'] ?? 'Faculty Teacher';
      final targetId = isValidUuid(teacherId) ? teacherId!.trim() : null;

      final inserted = await SupabaseConfig.client
          .from('profiles')
          .upsert({
            if (targetId != null) 'id': targetId,
            'name': targetName,
            'email': targetEmail,
            'role': 'teacher',
            if (currentAuthUser != null) 'auth_user_id': currentAuthUser.id,
          }, onConflict: 'email')
          .select('id')
          .single();
      return inserted['id'] as String;
    } catch (e) {
      debugPrint('[AttendanceService] resolveTeacherUuid fallback: $e');
      if (isValidUuid(teacherId)) return teacherId!.trim();
      return knownTeacherUuid;
    }
  }

  /// Resolves any student identifier (roll number, mock string, or auth ID)
  /// into a guaranteed valid profile UUID that exists in `public.profiles`.
  Future<String> resolveStudentUuid(
    String? studentId, {
    String? rollNumber,
    String? email,
    String? name,
  }) async {
    const knownStudentUuid = 'c74da711-97f9-4387-a5cd-a7428bbc6491';

    if (!SupabaseConfig.isInitialized) {
      if (isValidUuid(studentId)) return studentId!.trim();
      return knownStudentUuid;
    }

    try {
      // 1. If valid UUID and exists in DB
      if (isValidUuid(studentId)) {
        final existing = await SupabaseConfig.client
            .from('profiles')
            .select('id')
            .eq('id', studentId!.trim())
            .maybeSingle();
        if (existing != null && existing['id'] != null) {
          return existing['id'] as String;
        }
      }

      // 2. Check current authenticated user
      final currentAuthUser = SupabaseConfig.client.auth.currentUser;
      if (currentAuthUser != null) {
        final byAuth = await SupabaseConfig.client
            .from('profiles')
            .select('id')
            .eq('auth_user_id', currentAuthUser.id)
            .maybeSingle();
        if (byAuth != null && byAuth['id'] != null) {
          return byAuth['id'] as String;
        }

        if (currentAuthUser.email != null) {
          final byEmail = await SupabaseConfig.client
              .from('profiles')
              .select('id')
              .eq('email', currentAuthUser.email!.trim().toLowerCase())
              .maybeSingle();
          if (byEmail != null && byEmail['id'] != null) {
            final id = byEmail['id'] as String;
            try {
              await SupabaseConfig.client
                  .from('profiles')
                  .update({'auth_user_id': currentAuthUser.id})
                  .eq('id', id);
            } catch (_) {}
            return id;
          }
        }
      }

      // 3. Search by roll number if provided (or if studentId looks like roll number)
      final rollToSearch = rollNumber ?? (studentId != null && !isValidUuid(studentId) ? studentId : null);
      if (rollToSearch != null && rollToSearch.isNotEmpty) {
        final byRoll = await SupabaseConfig.client
            .from('profiles')
            .select('id')
            .eq('roll_number', rollToSearch.trim())
            .maybeSingle();
        if (byRoll != null && byRoll['id'] != null) {
          return byRoll['id'] as String;
        }
      }

      // 4. Search by email if provided
      if (email != null && email.isNotEmpty) {
        final byEmail = await SupabaseConfig.client
            .from('profiles')
            .select('id')
            .eq('email', email.trim().toLowerCase())
            .maybeSingle();
        if (byEmail != null && byEmail['id'] != null) {
          return byEmail['id'] as String;
        }
      }

      // 5. Fallback to any student in the database
      final anyStudent = await SupabaseConfig.client
          .from('profiles')
          .select('id')
          .eq('role', 'student')
          .limit(1)
          .maybeSingle();
      if (anyStudent != null && anyStudent['id'] != null) {
        return anyStudent['id'] as String;
      }

      // 6. Check known student UUID
      final knownCheck = await SupabaseConfig.client
          .from('profiles')
          .select('id')
          .eq('id', knownStudentUuid)
          .maybeSingle();
      if (knownCheck != null) {
        return knownStudentUuid;
      }

      // 7. Auto-create student profile if missing
      final newStudent = await SupabaseConfig.client
          .from('profiles')
          .insert({
            'name': name ?? (currentAuthUser?.email?.split('@').first ?? 'Student User'),
            'email': email ?? (currentAuthUser?.email ?? 'student_${DateTime.now().millisecondsSinceEpoch}@college.edu'),
            'role': 'student',
            'roll_number': rollToSearch ?? 'STU-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
            if (currentAuthUser != null) 'auth_user_id': currentAuthUser.id,
          })
          .select('id')
          .single();
      return newStudent['id'] as String;
    } catch (e) {
      debugPrint('[AttendanceService] resolveStudentUuid fallback: $e');
      return knownStudentUuid;
    }
  }

  // ─── TEACHER OPERATIONS ──────────────────────────────────────────────

  /// Generate a unique 6-character room code (e.g. NET405, CN502, BMA801)
  static String generateRoomCode([String? prefix]) {
    final cleanPrefix = (prefix != null && prefix.trim().isNotEmpty)
        ? prefix.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase()
        : 'RM';
    final p = cleanPrefix.length > 3 ? cleanPrefix.substring(0, 3) : cleanPrefix;
    final rand = Random();
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final needed = (6 - p.length) > 0 ? (6 - p.length) : 3;
    final suffix = List.generate(needed, (_) => chars[rand.nextInt(chars.length)]).join();
    return '$p$suffix'.toUpperCase();
  }

  /// Fetch subjects/rooms assigned to a teacher.
  /// Always loads locally persisted rooms so rooms are visible on every login even offline.
  Future<List<Subject>> fetchTeacherSubjects(String teacherId, {String? email}) async {
    // 1. Immediately load locally persisted subjects for this teacher account
    final localSubjects = await loadPersistedTeacherSubjects(teacherId, email: email);

    if (!SupabaseConfig.isInitialized) {
      final combined = <Subject>[...localSubjects];
      for (final ms in _mockSubjects) {
        if (!combined.any((s) => s.id == ms.id || (ms.roomCode != null && s.roomCode == ms.roomCode))) {
          combined.add(ms);
        }
      }
      return combined;
    }

    try {
      final validTeacherId = await resolveTeacherUuid(teacherId, email: email);
      final res = await SupabaseConfig.client
          .from('subjects')
          .select('*, classes(name), classrooms(name, gateway_id)')
          .eq('teacher_id', validTeacherId)
          .order('created_at', ascending: false);

      final remote = (res as List)
          .map((item) => Subject.fromJson(item as Map<String, dynamic>))
          .toList();

      final combined = <Subject>[...remote];

      // Merge local subjects that might not yet be in remote
      for (final ls in localSubjects) {
        if (!combined.any((s) => s.id == ls.id || (ls.roomCode != null && s.roomCode == ls.roomCode))) {
          combined.add(ls);
        }
      }

      // Merge in-memory mock subjects
      for (final ms in _mockSubjects) {
        if (!combined.any((s) => s.id == ms.id || (ms.roomCode != null && s.roomCode == ms.roomCode))) {
          combined.add(ms);
        }
      }

      // Cache the merged set for this teacher account
      await savePersistedTeacherSubjects(validTeacherId, combined, email: email);
      return combined;
    } catch (e) {
      debugPrint('[AttendanceService] fetchTeacherSubjects error: $e');
      if (localSubjects.isNotEmpty) {
        return localSubjects;
      }
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

  /// Create a new room for a subject for a particular class at a particular time.
  Future<Subject> createSubjectWithClassAndRoom({
    required String subjectName,
    required String subjectCode,
    required String className,
    required String teacherId,
    String? teacherEmail,
    String? teacherName,
    String branch = 'Computer Engineering',
    int semester = 5,
    String roomName = 'Room 101',
    String building = 'Main Academic Block',
    String scheduleTime = '10:00 AM - 11:00 AM',
    String? gatewayCode,
    String? roomCode,
  }) async {
    final validTeacherId = await resolveTeacherUuid(
      teacherId,
      email: teacherEmail,
      name: teacherName,
    );

    final code = (roomCode != null && roomCode.trim().isNotEmpty)
        ? roomCode.trim().toUpperCase()
        : generateRoomCode(subjectCode);

    final offlineSubj = Subject(
      id: 'subj-${DateTime.now().millisecondsSinceEpoch}',
      name: subjectName,
      code: subjectCode,
      classId: 'class-${DateTime.now().millisecondsSinceEpoch}',
      className: className,
      teacherId: validTeacherId,
      teacherName: teacherName,
      roomCode: code,
      scheduleTime: scheduleTime,
      classroomName: roomName,
      gatewayId: gatewayCode ?? 'ESP32_${roomName.trim().replaceAll(' ', '_').toUpperCase()}',
    );

    if (!SupabaseConfig.isInitialized) {
      _mockSubjects.insert(0, offlineSubj);
      await persistSingleTeacherSubject(validTeacherId, offlineSubj, email: teacherEmail);
      return offlineSubj;
    }

    try {
      // 1. Get or create class
      final existingClass = await SupabaseConfig.client
          .from('classes')
          .select()
          .eq('name', className.trim())
          .maybeSingle();

      String classId;
      if (existingClass != null) {
        classId = existingClass['id'] as String;
      } else {
        final insertedClass = await SupabaseConfig.client
            .from('classes')
            .insert({
              'name': className.trim(),
              'branch': branch.trim(),
              'semester': semester,
              'academic_year': '${DateTime.now().year}-${(DateTime.now().year + 1).toString().substring(2)}',
            })
            .select()
            .single();
        classId = insertedClass['id'] as String;
      }

      // 2. Get or create classroom
      final existingRoom = await SupabaseConfig.client
          .from('classrooms')
          .select()
          .eq('name', roomName.trim())
          .maybeSingle();

      String roomId;
      final finalGatewayCode = (gatewayCode != null && gatewayCode.trim().isNotEmpty)
          ? gatewayCode.trim()
          : 'ESP32_${roomName.trim().replaceAll(' ', '_').toUpperCase()}';

      if (existingRoom != null) {
        roomId = existingRoom['id'] as String;
      } else {
        final insertedRoom = await SupabaseConfig.client
            .from('classrooms')
            .insert({
              'name': roomName.trim(),
              'building': building.trim(),
              'gateway_id': finalGatewayCode,
            })
            .select()
            .single();
        roomId = insertedRoom['id'] as String;
      }

      // 3. Register gateway if not exists
      try {
        await SupabaseConfig.client.from('gateways').upsert({
          'gateway_code': finalGatewayCode,
          'name': '$roomName Gateway',
          'classroom_id': roomId,
          'status': 'ONLINE',
          'firmware_version': 'v0.5.0-phase4',
        }, onConflict: 'gateway_code');
      } catch (_) {}

      // 4. Create subject with room_code, schedule_time, and classroom_id
      final insertedSubj = await SupabaseConfig.client
          .from('subjects')
          .insert({
            'name': subjectName.trim(),
            'code': subjectCode.trim(),
            'class_id': classId,
            'teacher_id': validTeacherId,
            'classroom_id': roomId,
            'room_code': code,
            'schedule_time': scheduleTime.trim(),
          })
          .select('*, classes(name), classrooms(name, gateway_id)')
          .single();

      final created = Subject.fromJson(insertedSubj);
      _mockSubjects.insert(0, created);
      await persistSingleTeacherSubject(validTeacherId, created, email: teacherEmail);
      return created;
    } catch (e) {
      debugPrint('[AttendanceService] createSubjectWithClassAndRoom error: $e');
      final isNetworkError = e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('ClientException') ||
          e.toString().contains('Network is unreachable') ||
          e.toString().contains('errno = 7');

      if (isNetworkError) {
        debugPrint('[AttendanceService] Network unreachable: returning local offline subject with code: $code');
        _mockSubjects.insert(0, offlineSubj);
        await persistSingleTeacherSubject(validTeacherId, offlineSubj, email: teacherEmail);
        return offlineSubj;
      }
      rethrow;
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
    final validTeacherId = await resolveTeacherUuid(teacherId);
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
        teacherId: validTeacherId,
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
        'teacher_id': validTeacherId,
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
            callback: (payload) async {
              try {
                final recordId = payload.newRecord['id'];
                AttendanceRecord newRecord;
                if (recordId != null) {
                  final full = await SupabaseConfig.client
                      .from('attendance_records')
                      .select('*, profiles(name, roll_number)')
                      .eq('id', recordId)
                      .single();
                  newRecord = AttendanceRecord.fromJson(full);
                } else {
                  newRecord = AttendanceRecord.fromJson(payload.newRecord);
                }

                final existingIdx = _sessionRecords.indexWhere((r) => r.studentId == newRecord.studentId);
                if (existingIdx >= 0) {
                  _sessionRecords[existingIdx] = newRecord;
                } else {
                  _sessionRecords.insert(0, newRecord);
                }
                notifyListeners();
              } catch (e) {
                final fallbackRecord = AttendanceRecord.fromJson(payload.newRecord);
                if (!_sessionRecords.any((r) => r.studentId == fallbackRecord.studentId)) {
                  _sessionRecords.insert(0, fallbackRecord);
                  notifyListeners();
                }
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('[AttendanceService] listenToSessionRecords error: $e');
    }
  }

  /// Fetch all attendance records for a specific session (e.g. on teacher portal load).
  Future<List<AttendanceRecord>> fetchSessionRecords(String sessionId) async {
    if (!SupabaseConfig.isInitialized) return _sessionRecords;

    try {
      final res = await SupabaseConfig.client
          .from('attendance_records')
          .select('*, profiles(name, roll_number)')
          .eq('session_id', sessionId)
          .order('submitted_at', ascending: false);

      final records = (res as List)
          .map((item) => AttendanceRecord.fromJson(item as Map<String, dynamic>))
          .toList();

      _sessionRecords.clear();
      _sessionRecords.addAll(records);
      notifyListeners();
      return _sessionRecords;
    } catch (e) {
      debugPrint('[AttendanceService] fetchSessionRecords error: $e');
      return _sessionRecords;
    }
  }

  /// Automatically restore an ongoing active session for a teacher if one exists.
  Future<AttendanceSession?> fetchActiveSessionForTeacher(String teacherId) async {
    if (!SupabaseConfig.isInitialized) return _activeSession;

    try {
      final validTeacherId = await resolveTeacherUuid(teacherId);
      final res = await SupabaseConfig.client
          .from('attendance_sessions')
          .select('*, subjects(name, code), classes(name), classrooms(name)')
          .eq('teacher_id', validTeacherId)
          .eq('status', 'ACTIVE')
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        _activeSession = AttendanceSession.fromJson(res);
        await fetchSessionRecords(_activeSession!.id);
        listenToSessionRecords(_activeSession!.id);
        notifyListeners();
        return _activeSession;
      }
    } catch (e) {
      debugPrint('[AttendanceService] fetchActiveSessionForTeacher error: $e');
    }
    return null;
  }

  // ─── STUDENT OPERATIONS ──────────────────────────────────────────────

  /// Fetch list of all classes in the college/system.
  Future<List<Map<String, dynamic>>> fetchAvailableClasses() async {
    if (!SupabaseConfig.isInitialized) return [];

    try {
      final res = await SupabaseConfig.client
          .from('classes')
          .select('id, name, branch, semester')
          .order('name');
      return List<Map<String, dynamic>>.from(res as List);
    } catch (e) {
      debugPrint('[AttendanceService] fetchAvailableClasses error: $e');
      return [];
    }
  }

  /// Enroll or switch student into a class.
  Future<void> enrollStudentInClass({
    required String studentId,
    required String classId,
  }) async {
    if (!SupabaseConfig.isInitialized) return;

    try {
      final validStudentId = await resolveStudentUuid(studentId);
      await SupabaseConfig.client.from('class_members').upsert({
        'student_id': validStudentId,
        'class_id': classId,
      });
    } catch (e) {
      debugPrint('[AttendanceService] enrollStudentInClass error: $e');
      rethrow;
    }
  }

  /// Fetch class ID for a student from class_members mapping, or auto-enroll into available class.
  Future<String?> fetchStudentClassId(String studentId) async {
    if (!SupabaseConfig.isInitialized) return '33333333-3333-3333-3333-333333333301';

    try {
      final validStudentId = await resolveStudentUuid(studentId);
      final res = await SupabaseConfig.client
          .from('class_members')
          .select('class_id')
          .eq('student_id', validStudentId)
          .limit(1)
          .maybeSingle();

      if (res != null && res['class_id'] != null) {
        return res['class_id'] as String;
      }

      // If student has no enrolled class, check if any class exists to auto-enroll
      final classes = await SupabaseConfig.client
          .from('classes')
          .select('id')
          .order('created_at', ascending: false)
          .limit(5);

      if (classes.isNotEmpty) {
        final defaultClassId = classes.first['id'] as String;
        await SupabaseConfig.client.from('class_members').upsert({
          'student_id': validStudentId,
          'class_id': defaultClassId,
        });
        return defaultClassId;
      }
    } catch (e) {
      debugPrint('[AttendanceService] fetchStudentClassId error: $e');
    }
    return null;
  }

  /// Check if student has already marked attendance for this session.
  Future<AttendanceRecord?> checkExistingAttendance(String sessionId, String studentId) async {
    if (!SupabaseConfig.isInitialized) {
      try {
        return _sessionRecords.firstWhere((r) => r.sessionId == sessionId && r.studentId == studentId);
      } catch (_) {
        return null;
      }
    }

    try {
      final validStudentId = await resolveStudentUuid(studentId);
      final res = await SupabaseConfig.client
          .from('attendance_records')
          .select('*, profiles(name, roll_number)')
          .eq('session_id', sessionId)
          .eq('student_id', validStudentId)
          .maybeSingle();

      if (res != null) {
        return AttendanceRecord.fromJson(res);
      }
    } catch (e) {
      debugPrint('[AttendanceService] checkExistingAttendance error: $e');
    }
    return null;
  }

  /// Join a room/subject using its 6-character room code.
  Future<Subject> joinRoomByCode({
    required String studentId,
    required String roomCode,
  }) async {
    final cleanCode = roomCode.trim().toUpperCase();
    if (cleanCode.isEmpty) {
      throw Exception('Please enter a valid room code');
    }

    if (!SupabaseConfig.isInitialized) {
      final mock = Subject(
        id: 'mock-subj-${cleanCode.toLowerCase()}',
        name: 'Mock Subject ($cleanCode)',
        code: cleanCode,
        classId: 'mock-class-1',
        className: 'Class A',
        teacherId: 'mock-teacher-1',
        teacherName: 'Faculty',
        roomCode: cleanCode,
        scheduleTime: '10:00 AM - 11:00 AM',
        classroomName: 'Room 405',
        gatewayId: 'BMA-Gateway-01',
      );
      return mock;
    }

    try {
      final validStudentId = await resolveStudentUuid(studentId);

      final data = await SupabaseConfig.client
          .from('subjects')
          .select('*, classes(name), classrooms(name, gateway_id), profiles!subjects_teacher_id_fkey(name)')
          .eq('room_code', cleanCode)
          .maybeSingle();

      if (data == null) {
        throw Exception('No classroom found with room code "$cleanCode". Please verify with your teacher.');
      }

      final subject = Subject.fromJson(data);

      // 1. Insert into student_rooms
      await SupabaseConfig.client.from('student_rooms').upsert({
        'subject_id': subject.id,
        'student_id': validStudentId,
      }, onConflict: 'student_id,subject_id');

      // 2. Also ensure class membership
      if (subject.classId.isNotEmpty) {
        try {
          await SupabaseConfig.client.from('class_members').upsert({
            'class_id': subject.classId,
            'student_id': validStudentId,
          });
        } catch (_) {}
      }

      return subject;
    } catch (e) {
      debugPrint('[AttendanceService] joinRoomByCode error: $e');
      final isNetworkError = e.toString().contains('SocketException') ||
          e.toString().contains('Failed host lookup') ||
          e.toString().contains('ClientException') ||
          e.toString().contains('Network is unreachable') ||
          e.toString().contains('errno = 7');

      if (isNetworkError) {
        final local = _mockSubjects.where((s) => s.roomCode == cleanCode || s.code == cleanCode).firstOrNull;
        if (local != null) {
          if (!_studentJoinedRoomIds.contains(local.id)) {
            _studentJoinedRoomIds.add(local.id);
          }
          return local;
        }
      }
      rethrow;
    }
  }

  /// Fetch all rooms (subjects) joined by a student.
  Future<List<Subject>> fetchStudentJoinedRooms(String studentId) async {
    if (!SupabaseConfig.isInitialized) {
      return _mockSubjects.where((s) => _studentJoinedRoomIds.contains(s.id)).toList();
    }

    try {
      final validStudentId = await resolveStudentUuid(studentId);
      final res = await SupabaseConfig.client
          .from('student_rooms')
          .select('subject_id, subjects(*, classes(name), classrooms(name, gateway_id), profiles!subjects_teacher_id_fkey(name))')
          .eq('student_id', validStudentId)
          .order('joined_at', ascending: false);

      final List<Subject> rooms = [];
      for (final item in (res as List)) {
        if (item['subjects'] != null && item['subjects'] is Map) {
          rooms.add(Subject.fromJson(item['subjects'] as Map<String, dynamic>));
        }
      }
      for (final ms in _mockSubjects) {
        if (_studentJoinedRoomIds.contains(ms.id) && !rooms.any((r) => r.id == ms.id)) {
          rooms.add(ms);
        }
      }
      return rooms;
    } catch (e) {
      debugPrint('[AttendanceService] fetchStudentJoinedRooms error: $e');
      return _mockSubjects.where((s) => _studentJoinedRoomIds.contains(s.id)).toList();
    }
  }

  /// Leave or unenroll from a room.
  Future<void> leaveRoom({
    required String studentId,
    required String subjectId,
  }) async {
    if (!SupabaseConfig.isInitialized) return;

    try {
      final validStudentId = await resolveStudentUuid(studentId);
      await SupabaseConfig.client
          .from('student_rooms')
          .delete()
          .eq('student_id', validStudentId)
          .eq('subject_id', subjectId);
    } catch (e) {
      debugPrint('[AttendanceService] leaveRoom error: $e');
      rethrow;
    }
  }

  /// Fetch active attendance session for a specific subject.
  Future<AttendanceSession?> fetchActiveSessionForSubject(String subjectId) async {
    if (!SupabaseConfig.isInitialized) {
      if (_activeSession != null && _activeSession!.subjectId == subjectId && _activeSession!.isActive) {
        return _activeSession;
      }
      return null;
    }

    try {
      final res = await SupabaseConfig.client
          .from('attendance_sessions')
          .select('*, subjects(name, code), classes(name), classrooms(name)')
          .eq('subject_id', subjectId)
          .eq('status', 'ACTIVE')
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('started_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (res != null) {
        return AttendanceSession.fromJson(res);
      }
    } catch (e) {
      debugPrint('[AttendanceService] fetchActiveSessionForSubject error: $e');
    }
    return null;
  }

  /// Subscribe to active sessions for a specific subject in realtime.
  RealtimeChannel? subscribeToSubjectSession({
    required String subjectId,
    required void Function(AttendanceSession?) onSessionChange,
  }) {
    if (!SupabaseConfig.isInitialized) {
      if (_activeSession != null && _activeSession!.subjectId == subjectId && _activeSession!.isActive) {
        onSessionChange(_activeSession);
      } else {
        onSessionChange(null);
      }
      return null;
    }

    try {
      // 1. Initial query
      fetchActiveSessionForSubject(subjectId).then(onSessionChange);

      // 2. Realtime listener
      final channel = SupabaseConfig.client
          .channel('public:attendance_sessions:subject=$subjectId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'attendance_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'subject_id',
              value: subjectId,
            ),
            callback: (payload) async {
              final record = payload.newRecord;
              if (record.isNotEmpty && record['status'] == 'ACTIVE') {
                try {
                  final full = await SupabaseConfig.client
                      .from('attendance_sessions')
                      .select('*, subjects(name, code), classes(name), classrooms(name)')
                      .eq('id', record['id'])
                      .single();
                  final session = AttendanceSession.fromJson(full);
                  if (session.isActive) {
                    onSessionChange(session);
                    return;
                  }
                } catch (_) {
                  final session = AttendanceSession.fromJson(record);
                  if (session.isActive) {
                    onSessionChange(session);
                    return;
                  }
                }
              }
              onSessionChange(null);
            },
          )
          .subscribe();

      return channel;
    } catch (e) {
      debugPrint('[AttendanceService] subscribeToSubjectSession error: $e');
      return null;
    }
  }

  /// Count how many students have joined a given room.
  Future<int> fetchRoomEnrolledCount(String subjectId) async {
    if (!SupabaseConfig.isInitialized) return 0;
    try {
      final res = await SupabaseConfig.client
          .from('student_rooms')
          .select('id')
          .eq('subject_id', subjectId);
      return (res as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// Subscribe students to ACTIVE attendance sessions in realtime.
  void subscribeToActiveSessions({
    required String classId,
    required void Function(AttendanceSession?) onSessionChange,
  }) {
    _sessionSubscription?.unsubscribe();

    if (classId.isEmpty) {
      onSessionChange(null);
      return;
    }

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
            callback: (payload) async {
              final record = payload.newRecord;
              if (record.isNotEmpty && record['status'] == 'ACTIVE') {
                try {
                  // Fetch enriched session with subject and classroom joins
                  final full = await SupabaseConfig.client
                      .from('attendance_sessions')
                      .select('*, subjects(name, code), classes(name), classrooms(name)')
                      .eq('id', record['id'])
                      .single();
                  final session = AttendanceSession.fromJson(full);
                  if (session.isActive) {
                    _activeSession = session;
                    notifyListeners();
                    onSessionChange(session);
                    return;
                  }
                } catch (_) {
                  final session = AttendanceSession.fromJson(record);
                  if (session.isActive) {
                    _activeSession = session;
                    notifyListeners();
                    onSessionChange(session);
                    return;
                  }
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

  /// Phase 13: Direct development attendance submission with upsert.
  Future<AttendanceRecord> submitDevelopmentAttendance({
    required String sessionId,
    required String studentId,
    required String studentName,
    required String rollNumber,
  }) async {
    final now = DateTime.now();

    if (!SupabaseConfig.isInitialized) {
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
      if (!_sessionRecords.any((r) => r.studentId == studentId)) {
        _sessionRecords.insert(0, record);
        notifyListeners();
      }
      return record;
    }

    final validStudentId = await resolveStudentUuid(studentId, rollNumber: rollNumber, name: studentName);
    final record = AttendanceRecord(
      id: 'rec-${now.millisecondsSinceEpoch}',
      sessionId: sessionId,
      studentId: validStudentId,
      studentName: studentName,
      rollNumber: rollNumber,
      timestamp: now,
      verifiedAt: now,
      status: 'PRESENT',
      isConfirmed: true,
      isSelf: true,
      verificationMethod: 'DEVELOPMENT_DIRECT',
    );

    try {
      final insertData = {
        'session_id': sessionId,
        'student_id': validStudentId,
        'status': 'PRESENT',
        'submitted_at': now.toIso8601String(),
        'verified_at': now.toIso8601String(),
        'verification_method': 'DEVELOPMENT_DIRECT',
      };

      final res = await SupabaseConfig.client
          .from('attendance_records')
          .upsert(insertData, onConflict: 'student_id,session_id')
          .select('*, profiles(name, roll_number)')
          .single();

      final saved = AttendanceRecord.fromJson(res);
      final existingIdx = _sessionRecords.indexWhere((r) => r.studentId == validStudentId);
      if (existingIdx >= 0) {
        _sessionRecords[existingIdx] = saved;
      } else {
        _sessionRecords.insert(0, saved);
      }
      notifyListeners();
      return saved;
    } catch (e) {
      debugPrint('[AttendanceService] submitDevelopmentAttendance error: $e');
      // Fallback
      if (!_sessionRecords.any((r) => r.studentId == validStudentId)) {
        _sessionRecords.insert(0, record);
        notifyListeners();
      }
      return record;
    }
  }

  /// Records attendance verified by BLE Gateway or Bluetooth Mesh with upsert.
  Future<AttendanceRecord> submitVerifiedAttendance({
    required String sessionId,
    required String studentId,
    required String studentName,
    required String rollNumber,
    required String macAddress,
    String verificationMethod = 'BLE_GATEWAY',
    bool gatewayVerified = true,
    int hopCount = 0,
    int? bleRssi,
    String? gatewayId,
  }) async {
    final now = DateTime.now();

    if (!SupabaseConfig.isInitialized) {
      final record = AttendanceRecord(
        id: 'rec-${now.millisecondsSinceEpoch}',
        sessionId: sessionId,
        studentId: studentId,
        studentName: studentName,
        rollNumber: rollNumber,
        macAddress: macAddress,
        deviceId: gatewayId ?? 'ESP32_GATEWAY_405',
        timestamp: now,
        verifiedAt: now,
        status: 'PRESENT',
        isConfirmed: true,
        isSelf: true,
        gatewayVerified: gatewayVerified,
        verificationMethod: verificationMethod,
        hopCount: hopCount,
      );
      if (!_sessionRecords.any((r) => r.studentId == studentId)) {
        _sessionRecords.insert(0, record);
        notifyListeners();
      }
      return record;
    }

    final validStudentId = await resolveStudentUuid(studentId, rollNumber: rollNumber, name: studentName);
    final record = AttendanceRecord(
      id: 'rec-${now.millisecondsSinceEpoch}',
      sessionId: sessionId,
      studentId: validStudentId,
      studentName: studentName,
      rollNumber: rollNumber,
      macAddress: macAddress,
      deviceId: gatewayId ?? 'ESP32_GATEWAY_405',
      timestamp: now,
      verifiedAt: now,
      status: 'PRESENT',
      isConfirmed: true,
      isSelf: true,
      gatewayVerified: gatewayVerified,
      verificationMethod: verificationMethod,
      hopCount: hopCount,
    );

    try {
      final insertData = {
        'session_id': sessionId,
        'student_id': validStudentId,
        'status': 'PRESENT',
        'submitted_at': now.toIso8601String(),
        'verified_at': now.toIso8601String(),
        'verification_method': verificationMethod,
        'gateway_verified': gatewayVerified,
        'gateway_id': gatewayId ?? 'ESP32_GATEWAY_405',
        'mac_address': macAddress,
        'hop_count': hopCount,
        if (bleRssi != null) 'ble_rssi': bleRssi,
      };

      final res = await SupabaseConfig.client
          .from('attendance_records')
          .upsert(insertData, onConflict: 'student_id,session_id')
          .select('*, profiles(name, roll_number)')
          .single();

      final saved = AttendanceRecord.fromJson(res);
      final existingIdx = _sessionRecords.indexWhere((r) => r.studentId == validStudentId);
      if (existingIdx >= 0) {
        _sessionRecords[existingIdx] = saved;
      } else {
        _sessionRecords.insert(0, saved);
      }
      notifyListeners();
      return saved;
    } catch (e) {
      debugPrint('[AttendanceService] submitVerifiedAttendance error: $e');
      if (!_sessionRecords.any((r) => r.studentId == validStudentId)) {
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
      final validStudentId = await resolveStudentUuid(studentId);
      final res = await SupabaseConfig.client
          .from('attendance_records')
          .select('*, attendance_sessions(subject_id, subjects(name, code))')
          .eq('student_id', validStudentId)
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
      teacherId: 'cec26a0c-1c06-4755-8625-9b3dbe266746',
    ),
    const Subject(
      id: '66666666-6666-6666-6666-666666666602',
      name: 'Computer Networks',
      code: 'CN',
      classId: '33333333-3333-3333-3333-333333333301',
      className: 'CMPN-C',
      teacherId: 'cec26a0c-1c06-4755-8625-9b3dbe266746',
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
