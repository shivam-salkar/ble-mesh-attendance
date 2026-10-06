import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/attendance_service.dart';
import '../../../models/attendance_session.dart';
import '../../../models/subject.dart';
import '../../../models/classroom.dart';
import '../../../screens/ble_test_screen.dart';
import '../../auth/screens/login_screen.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  final _authService = AuthService();
  final _attendanceService = AttendanceService();

  List<Subject> _subjects = [];
  List<Classroom> _classrooms = [];
  bool _isLoading = true;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _attendanceService.addListener(_onAttendanceUpdate);

    // Countdown ticker every second for active session
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_attendanceService.activeSession?.isActive == true && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _attendanceService.removeListener(_onAttendanceUpdate);
    super.dispose();
  }

  void _onAttendanceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final teacherId = _authService.currentProfile?.id ?? '44444444-4444-4444-4444-444444444401';
    final subjects = await _attendanceService.fetchTeacherSubjects(teacherId);
    final classrooms = await _attendanceService.fetchClassrooms();
    await _attendanceService.fetchActiveSessionForTeacher(teacherId);

    if (mounted) {
      setState(() {
        _subjects = subjects;
        _classrooms = classrooms;
        _isLoading = false;
      });
    }
  }

  void _showStartAttendanceDialog(Subject subject) {
    String selectedRoomId = _classrooms.isNotEmpty ? _classrooms.first.id : '11111111-1111-1111-1111-111111111101';
    int selectedDuration = 5;
    String sessionType = 'LECTURE';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Start Attendance — ${subject.code}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Class: ${subject.className ?? "CMPN-C"}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('Select Classroom:'),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedRoomId,
                    items: _classrooms.map((room) {
                      return DropdownMenuItem(
                        value: room.id,
                        child: Text('${room.name} (${room.building})'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedRoomId = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Session Duration:'),
                  Row(
                    children: [3, 5, 10, 15].map((mins) {
                      final isSelected = selectedDuration == mins;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('$mins min'),
                          selected: isSelected,
                          onSelected: (_) => setDialogState(() => selectedDuration = mins),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final room = _classrooms.firstWhere(
                    (r) => r.id == selectedRoomId,
                    orElse: () => _classrooms.first,
                  );
                  await _attendanceService.startSession(
                    subjectId: subject.id,
                    subjectName: subject.name,
                    subjectCode: subject.code,
                    classId: subject.classId,
                    className: subject.className ?? 'CMPN-C',
                    teacherId: _authService.currentProfile?.id ?? '44444444-4444-4444-4444-444444444401',
                    teacherName: _authService.currentProfile?.name ?? 'Prof. Sharma',
                    classroomId: room.id,
                    classroomName: room.name,
                    gatewayId: room.gatewayId,
                    durationMinutes: selectedDuration,
                    sessionType: sessionType,
                  );
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('START SESSION'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _authService.currentProfile;
    final activeSession = _attendanceService.activeSession;
    final hasActiveSession = activeSession != null && activeSession.isActive;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Faculty Attendance Portal'),
        actions: [
          IconButton(
            tooltip: 'Hardware Diagnostics',
            icon: const Icon(Icons.developer_mode),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BleTestScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await _authService.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Faculty profile banner
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: theme.colorScheme.primary,
                            child: const Icon(Icons.school, color: Colors.white),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  profile?.name ?? 'Prof. Sharma',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  profile?.email ?? 'teacher@college.edu',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: const Text('TEACHER'),
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                            labelStyle: TextStyle(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ACTIVE SESSION CARD (IF ACTIVE)
                  if (hasActiveSession) ...[
                    _buildActiveSessionCard(context, activeSession),
                    const SizedBox(height: 20),
                    _buildRealtimeAttendeeList(context),
                  ] else ...[
                    // "TODAY'S CLASSES" SECTION
                    Text(
                      "Today's Assigned Subjects",
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    ..._subjects.map((subject) => _buildSubjectCard(context, subject)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSubjectCard(BuildContext context, Subject subject) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    subject.code,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
                Text(
                  subject.className ?? 'CMPN-C',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subject.name,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                const Text('Room 405 (ESP32_GATEWAY_405)'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _showStartAttendanceDialog(subject),
                icon: const Icon(Icons.play_circle_fill, size: 20),
                label: const Text('START ATTENDANCE'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSessionCard(BuildContext context, AttendanceSession session) {
    final remaining = session.timeRemaining;
    final mins = remaining.inMinutes.toString().padLeft(2, '0');
    final secs = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    final presentCount = _attendanceService.sessionRecords.length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade400, width: 2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'ATTENDANCE ACTIVE',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$mins:$secs remaining',
                  style: TextStyle(
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${session.subjectName ?? "DBMS"} (${session.subjectCode ?? "DBMS"})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text('Class: ${session.className ?? "CMPN-C"} | ${session.classroomName ?? "Room 405"}'),
          const SizedBox(height: 16),

          // Realtime count
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$presentCount',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const Text('Present (Realtime)', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'ESP32',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text('Gateway 405', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _attendanceService.closeSession(session.id),
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
              label: const Text('CLOSE ATTENDANCE NOW', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeAttendeeList(BuildContext context) {
    final records = _attendanceService.sessionRecords;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Realtime Attendees',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${records.length} recorded',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (records.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text('Waiting for students to submit attendance...'),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            itemBuilder: (ctx, i) {
              final rec = records[i];
              final timeStr = "${rec.timestamp.hour.toString().padLeft(2, '0')}:${rec.timestamp.minute.toString().padLeft(2, '0')}:${rec.timestamp.second.toString().padLeft(2, '0')}";

              return Card(
                elevation: 0,
                color: Colors.grey.shade50,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.green.shade100,
                    child: Text(
                      rec.studentName.isNotEmpty ? rec.studentName[0] : 'S',
                      style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(rec.studentName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Roll: ${rec.rollNumber ?? rec.studentId} • $timeStr'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      rec.status,
                      style: TextStyle(color: Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
