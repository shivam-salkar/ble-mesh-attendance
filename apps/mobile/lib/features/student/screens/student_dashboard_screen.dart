import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/attendance_service.dart';
import '../../../services/student_profile_service.dart';
import '../../../models/subject.dart';
import '../../../models/attendance_record.dart';
import '../../../screens/ble_test_screen.dart';
import '../../auth/screens/login_screen.dart';
import 'student_room_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  final _authService = AuthService();
  final _attendanceService = AttendanceService();
  final _roomCodeController = TextEditingController();

  StudentProfile? _studentProfile;
  List<Subject> _joinedRooms = [];
  List<AttendanceRecord> _history = [];
  bool _isLoading = true;
  bool _isJoining = false;
  String? _joinError;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _roomCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    await _loadProfile();
    await _loadRooms();
    await _loadHistory();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadProfile() async {
    final profile = await StudentProfileService.getProfile();
    final user = _authService.currentProfile;
    // Sync roll number from auth if available
    if (user != null && user.rollNumber != null && user.rollNumber!.isNotEmpty) {
      if (profile.studentId != user.rollNumber || profile.name != user.name) {
        final synced = await StudentProfileService.saveProfile(
          name: user.name,
          studentId: user.rollNumber!,
        );
        if (mounted) setState(() => _studentProfile = synced);
        return;
      }
    }
    if (mounted) setState(() => _studentProfile = profile);
  }

  Future<void> _loadRooms() async {
    final studentId = _authService.currentProfile?.id ?? 'c74da711-97f9-4387-a5cd-a7428bbc6491';
    final rooms = await _attendanceService.fetchStudentJoinedRooms(studentId);
    if (mounted) setState(() => _joinedRooms = rooms);
  }

  Future<void> _loadHistory() async {
    final studentId = _authService.currentProfile?.id ?? 'c74da711-97f9-4387-a5cd-a7428bbc6491';
    final history = await _attendanceService.fetchStudentHistory(studentId);
    if (mounted) setState(() => _history = history);
  }

  Future<void> _handleJoinRoom() async {
    final code = _roomCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _joinError = 'Please enter a 6-character room code');
      return;
    }

    setState(() {
      _isJoining = true;
      _joinError = null;
    });

    final studentId = _authService.currentProfile?.id ?? 'c74da711-97f9-4387-a5cd-a7428bbc6491';

    try {
      final joinedSubject = await _attendanceService.joinRoomByCode(
        studentId: studentId,
        roomCode: code,
      );

      _roomCodeController.clear();
      await _loadRooms();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Successfully joined ${joinedSubject.name}!'),
            backgroundColor: Colors.green,
          ),
        );

        // Automatically navigate into the newly joined room
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => StudentRoomScreen(subject: joinedSubject)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _joinError = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  void _showEditProfileDialog() {
    final user = _authService.currentProfile;
    final nameCtrl = TextEditingController(text: user?.name ?? _studentProfile?.name ?? '');
    final rollCtrl = TextEditingController(text: user?.rollNumber ?? _studentProfile?.studentId ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Student Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rollCtrl,
              decoration: const InputDecoration(
                labelText: 'Roll / Enrollment Number',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              final newRoll = rollCtrl.text.trim();
              if (newName.isEmpty || newRoll.isEmpty) return;

              Navigator.of(ctx).pop();
              try {
                await _authService.updateProfileDetails(name: newName, rollNumber: newRoll);
                await _loadProfile();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile details updated!'), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Save Details'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _authService.currentProfile;
    final displayName = profile?.name ?? (_studentProfile?.name.isNotEmpty == true ? _studentProfile!.name : 'Student');
    final displayRoll = profile?.rollNumber ?? (_studentProfile?.studentId.isNotEmpty == true ? _studentProfile!.studentId : 'N/A');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Portal'),
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
      body: RefreshIndicator(
        onRefresh: _loadAllData,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ─── Student Profile Details Card ─────────────────
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.primaryContainer.withAlpha(90),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: theme.colorScheme.primary,
                                child: Text(
                                  displayName.isNotEmpty ? displayName[0].toUpperCase() : 'S',
                                  style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Roll No: $displayRoll • ${_studentProfile?.deviceId ?? "Device"}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Edit Details',
                                icon: const Icon(Icons.edit_outlined, size: 20),
                                onPressed: _showEditProfileDialog,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: theme.colorScheme.outlineVariant),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.bluetooth, size: 16, color: theme.colorScheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  'Linked Device MAC: ${_studentProfile?.macAddress ?? "Pending Setup"}',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ─── Enter Room Code Card ─────────────────────────
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.meeting_room, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                'Join a Classroom / Subject',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Enter the 6-character room code provided by your teacher to join their subject.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 14),

                          if (_joinError != null) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _joinError!,
                                style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _roomCodeController,
                                  textCapitalization: TextCapitalization.characters,
                                  decoration: InputDecoration(
                                    hintText: 'e.g. NET405',
                                    labelText: 'Room Code',
                                    prefixIcon: const Icon(Icons.tag),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: _isJoining ? null : _handleJoinRoom,
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                child: _isJoining
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('JOIN ROOM', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ─── Joined Rooms (Subjects) ──────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'My Subjects / Rooms (${_joinedRooms.length})',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        tooltip: 'Refresh Rooms',
                        icon: const Icon(Icons.refresh, size: 20),
                        onPressed: _loadRooms,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_joinedRooms.isEmpty) ...[
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                        child: Column(
                          children: [
                            Icon(Icons.class_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              'No Rooms Joined Yet',
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Ask your teacher for their 6-character room code and enter it above to join your subject!',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    ..._joinedRooms.map((subject) => _buildRoomCard(context, subject)),
                  ],

                  const SizedBox(height: 24),

                  // ─── Recent Attendance Records ────────────────────
                  if (_history.isNotEmpty) ...[
                    Text(
                      'Recent Verified Attendance (${_history.length})',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ..._history.map(_buildHistoryTile),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildRoomCard(BuildContext context, Subject subject) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => StudentRoomScreen(subject: subject)),
          ).then((_) => _loadHistory());
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      subject.code.isNotEmpty ? subject.code.substring(0, subject.code.length.clamp(1, 3)) : 'RM',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.name,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Faculty: ${subject.teacherName ?? "Course Faculty"} • Class: ${subject.className ?? "Standard"}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (subject.roomCode != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Code: ${subject.roomCode}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(Icons.access_time, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    subject.scheduleTime ?? '10:00 AM',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Icon(Icons.meeting_room_outlined, size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    subject.classroomName ?? 'Classroom 405',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryTile(AttendanceRecord record) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final timeStr = '${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isDark ? const Color(0xFF144D29) : Colors.green.shade100,
          child: Icon(
            Icons.check,
            color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF14532D),
          ),
        ),
        title: const Text('Lecture Attendance Verified', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Recorded: $timeStr • Via ${record.verificationMethod ?? "BLE_GATEWAY"}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF144D29) : Colors.green.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            record.status,
            style: TextStyle(
              color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF14532D),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
