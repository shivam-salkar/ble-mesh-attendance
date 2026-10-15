import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final Map<String, int> _enrolledCounts = {};
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
    final teacherId = _authService.currentProfile?.id ?? 'cec26a0c-1c06-4755-8625-9b3dbe266746';
    final subjects = await _attendanceService.fetchTeacherSubjects(teacherId);
    final classrooms = await _attendanceService.fetchClassrooms();
    await _attendanceService.fetchActiveSessionForTeacher(teacherId);

    if (mounted) {
      setState(() {
        _subjects = subjects;
        _classrooms = classrooms;
        _isLoading = false;
      });

      for (final s in subjects) {
        _attendanceService.fetchRoomEnrolledCount(s.id).then((count) {
          if (mounted) {
            setState(() {
              _enrolledCounts[s.id] = count;
            });
          }
        });
      }
    }
  }

  void _showRoomCreatedDialog(Subject subject) {
    final roomCode = subject.roomCode ?? subject.code;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 28),
            const SizedBox(width: 8),
            const Text('Room Created!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${subject.name} (${subject.code})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              'Class: ${subject.className ?? "CMPN-A"} • ${subject.scheduleTime ?? "10:00 AM - 11:00 AM"}',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            const SizedBox(height: 18),
            const Text(
              'Share this Room Code with your students:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    roomCode,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3.0,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  IconButton.filled(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: roomCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Room code $roomCode copied to clipboard!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 20),
                    tooltip: 'Copy Code',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Students will enter this code on their dashboard to join this subject and connect to the classroom gateway.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _showAddSubjectDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    final classCtrl = TextEditingController(text: 'CMPN-A');
    final roomCtrl = TextEditingController(text: _classrooms.isNotEmpty ? _classrooms.first.name : 'Room 101');
    final timeCtrl = TextEditingController(text: '10:00 AM - 11:00 AM');
    final gatewayCtrl = TextEditingController();
    String generatedCode = AttendanceService.generateRoomCode();
    final roomCodeCtrl = TextEditingController(text: generatedCode);

    final timePresets = [
      '09:00 AM - 10:00 AM',
      '10:00 AM - 11:00 AM',
      '11:15 AM - 12:15 PM',
      '01:00 PM - 02:00 PM',
      '02:00 PM - 03:00 PM',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Create Classroom Room / Subject'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Subject Name (e.g. Operating Systems)',
                    prefixIcon: Icon(Icons.menu_book),
                  ),
                  onChanged: (val) {
                    if (codeCtrl.text.isEmpty && val.isNotEmpty) {
                      final words = val.trim().split(RegExp(r'\s+'));
                      final initials = words.map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
                      if (initials.isNotEmpty) {
                        codeCtrl.text = initials.length > 4 ? initials.substring(0, 4) : initials;
                        setDialogState(() {
                          generatedCode = AttendanceService.generateRoomCode(codeCtrl.text);
                          roomCodeCtrl.text = generatedCode;
                        });
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Subject Code (e.g. CS302)',
                    prefixIcon: Icon(Icons.code),
                  ),
                  onChanged: (val) {
                    setDialogState(() {
                      generatedCode = AttendanceService.generateRoomCode(val.trim());
                      roomCodeCtrl.text = generatedCode;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: classCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Target Class / Division (e.g. CMPN-A)',
                    prefixIcon: Icon(Icons.groups),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: roomCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Classroom Name (e.g. Room 405)',
                    prefixIcon: Icon(Icons.meeting_room),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Scheduled Lecture Time',
                    prefixIcon: Icon(Icons.schedule),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: timePresets.map((preset) {
                    final isSel = timeCtrl.text == preset;
                    return ChoiceChip(
                      label: Text(preset, style: const TextStyle(fontSize: 11)),
                      selected: isSel,
                      onSelected: (_) {
                        setDialogState(() => timeCtrl.text = preset);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: roomCodeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Room Code (Students will enter this)',
                          prefixIcon: Icon(Icons.key),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Regenerate Code',
                      icon: const Icon(Icons.refresh),
                      onPressed: () {
                        setDialogState(() {
                          generatedCode = AttendanceService.generateRoomCode(codeCtrl.text.trim());
                          roomCodeCtrl.text = generatedCode;
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: gatewayCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Gateway Code (Optional, e.g. ESP32_405)',
                    prefixIcon: Icon(Icons.router),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
                Navigator.of(ctx).pop();
                setState(() => _isLoading = true);
                try {
                  final teacherId = _authService.currentProfile?.id ?? 'cec26a0c-1c06-4755-8625-9b3dbe266746';
                  final created = await _attendanceService.createSubjectWithClassAndRoom(
                    subjectName: nameCtrl.text.trim(),
                    subjectCode: codeCtrl.text.trim(),
                    className: classCtrl.text.trim().isEmpty ? 'CMPN-A' : classCtrl.text.trim(),
                    teacherId: teacherId,
                    roomName: roomCtrl.text.trim().isEmpty ? 'Room 101' : roomCtrl.text.trim(),
                    scheduleTime: timeCtrl.text.trim().isEmpty ? '10:00 AM - 11:00 AM' : timeCtrl.text.trim(),
                    gatewayCode: gatewayCtrl.text.trim().isEmpty ? null : gatewayCtrl.text.trim(),
                    roomCode: roomCodeCtrl.text.trim().isNotEmpty ? roomCodeCtrl.text.trim().toUpperCase() : generatedCode,
                  );
                  await _loadData();
                  if (mounted) {
                    _showRoomCreatedDialog(created);
                    if (created.id.startsWith('subj-')) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text('Room created in Offline Mode. Attendance can be taken via ESP32 Gateway!'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 4),
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    final errStr = e.toString();
                    String msg = 'Failed to add subject: $e';
                    if (errStr.contains('SocketException') ||
                        errStr.contains('Failed host lookup') ||
                        errStr.contains('errno = 7')) {
                      msg = 'No internet connection: Please ensure your device has internet access.';
                    }
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text(msg), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text('Create Room'),
            ),
          ],
        ),
      ),
    );
  }

  void _showStartAttendanceDialog(Subject subject) {
    String selectedRoomId = subject.classroomId ?? (_classrooms.isNotEmpty ? _classrooms.first.id : 'default-room');
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
                  Text('Class: ${subject.className ?? "CMPN-A"}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (subject.roomCode != null) ...[
                    const SizedBox(height: 4),
                    Text('Room Code: ${subject.roomCode}',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                  ],
                  if (subject.scheduleTime != null) ...[
                    const SizedBox(height: 4),
                    Text('Time: ${subject.scheduleTime}',
                        style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ],
                  const SizedBox(height: 16),
                  const Text('Select Classroom / Gateway:'),
                  _classrooms.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Default Room (ESP32_GATEWAY_DEFAULT)'),
                        )
                      : DropdownButton<String>(
                          isExpanded: true,
                          value: _classrooms.any((r) => r.id == selectedRoomId)
                              ? selectedRoomId
                              : _classrooms.first.id,
                          items: _classrooms.map((room) {
                            return DropdownMenuItem(
                              value: room.id,
                              child: Text('${room.name} (${room.gatewayId ?? "ESP32"})'),
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
                  Classroom room;
                  if (_classrooms.isNotEmpty) {
                    room = _classrooms.firstWhere(
                      (r) => r.id == selectedRoomId,
                      orElse: () => _classrooms.first,
                    );
                  } else {
                    room = const Classroom(
                      id: '11111111-1111-1111-1111-111111111101',
                      name: 'Room 101',
                      building: 'Main Block',
                      gatewayId: 'ESP32_GATEWAY_101',
                    );
                  }
                  await _attendanceService.startSession(
                    subjectId: subject.id,
                    subjectName: subject.name,
                    subjectCode: subject.code,
                    classId: subject.classId,
                    className: subject.className ?? 'CMPN-A',
                    teacherId: _authService.currentProfile?.id ?? 'cec26a0c-1c06-4755-8625-9b3dbe266746',
                    teacherName: _authService.currentProfile?.name ?? 'Teacher',
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
            tooltip: 'Add Subject & Classroom',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _showAddSubjectDialog,
          ),
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
                                  profile?.name ?? 'Teacher',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  profile?.email ?? 'teacher@institution.edu',
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Today's Assigned Subjects",
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        TextButton.icon(
                          onPressed: _showAddSubjectDialog,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Subject'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_subjects.isEmpty)
                      Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
                          child: Column(
                            children: [
                              Icon(Icons.library_books_outlined, size: 48, color: theme.colorScheme.primary),
                              const SizedBox(height: 14),
                              Text(
                                'No Subjects Configured',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Create a subject and assign it to a classroom to start taking live BLE attendance sessions.',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: _showAddSubjectDialog,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Subject & Classroom'),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._subjects.map((subject) => _buildSubjectCard(context, subject)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSubjectCard(BuildContext context, Subject subject) {
    final theme = Theme.of(context);
    final roomCode = subject.roomCode ?? subject.code;
    final enrolledCount = _enrolledCounts[subject.id] ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    subject.className ?? 'Classroom',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              subject.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 10),

            // ROOM CODE BADGE WITH 1-CLICK COPY
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: roomCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Room code $roomCode copied to clipboard!'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.key, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'STUDENT ROOM CODE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          Text(
                            roomCode,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      color: theme.colorScheme.primary,
                      tooltip: 'Copy Room Code',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: roomCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Room code $roomCode copied to clipboard!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Class details: Schedule Time, Classroom/Gateway, Enrolled count
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  subject.scheduleTime ?? '10:00 AM - 11:00 AM',
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${subject.classroomName ?? "Room 101"} (${subject.gatewayId ?? "ESP32_GATEWAY"})',
                    style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.people_outline, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  '$enrolledCount students joined',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enrolledCount > 0 ? Colors.green.shade800 : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _showStartAttendanceDialog(subject),
                icon: const Icon(Icons.play_circle_fill, size: 20),
                label: const Text('RECORD ATTENDANCE'),
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
            '${session.subjectName ?? "Active Lecture"}${session.subjectCode != null ? " (${session.subjectCode})" : ""}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text('Class: ${session.className ?? "Standard"} | ${session.classroomName ?? "Classroom"}'),
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
