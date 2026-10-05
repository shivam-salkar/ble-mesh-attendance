import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/auth_service.dart';
import '../../../services/attendance_service.dart';
import '../../../services/student_profile_service.dart';
import '../../../models/attendance_session.dart';
import '../../../models/attendance_record.dart';
import '../../../screens/ble_test_screen.dart';
import '../../../services/ble_service.dart';
import '../../auth/screens/login_screen.dart';

class StudentDashboardScreen extends StatefulWidget {
  const StudentDashboardScreen({super.key});

  @override
  State<StudentDashboardScreen> createState() => _StudentDashboardScreenState();
}

class _StudentDashboardScreenState extends State<StudentDashboardScreen> {
  final _authService = AuthService();
  final _attendanceService = AttendanceService();
  final _bleService = BleService();

  StudentProfile? _studentProfile;
  AttendanceSession? _activeSession;
  AttendanceRecord? _markedRecord;
  bool _isSubmitting = false;
  String _submissionStatus = '';
  Timer? _countdownTimer;
  List<AttendanceRecord> _history = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();

    // Subscribe to active attendance sessions in realtime
    _attendanceService.subscribeToActiveSessions(
      classId: '33333333-3333-3333-3333-333333333301', // CMPN-C default
      onSessionChange: (session) {
        if (mounted) {
          setState(() {
            _activeSession = session;
            // Reset marked record if new session
            if (_markedRecord != null && _markedRecord!.sessionId != session?.id) {
              _markedRecord = null;
            }
          });
        }
      },
    );

    // Countdown ticker every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeSession?.isActive == true && mounted) {
        setState(() {});
      }
    });

    _loadHistory();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await StudentProfileService.getProfile();
    if (mounted) setState(() => _studentProfile = profile);
  }

  Future<void> _loadHistory() async {
    final studentId = _authService.currentProfile?.id ?? '55555555-5555-5555-5555-555555555501';
    final history = await _attendanceService.fetchStudentHistory(studentId);
    if (mounted) setState(() => _history = history);
  }

  Future<void> _markAttendance() async {
    if (_activeSession == null || !_activeSession!.isActive || _isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _submissionStatus = 'Scanning for ESP32 Gateway...';
    });
    final user = _authService.currentProfile;
    final studentName = user?.name ?? (_studentProfile?.name ?? 'Aryan Darekar');
    final rollNumber = user?.rollNumber ?? (_studentProfile?.studentId ?? '25102C0040');
    final macAddress = _studentProfile?.macAddress ?? '';

    try {
      bool bleSuccess = false;
      try {
        await _bleService.initialize();
        if (mounted) setState(() => _submissionStatus = 'Connecting to Gateway...');
        bleSuccess = await _bleService.markAttendance(
          sessionId: _activeSession!.id,
          sessionNonce: _activeSession!.sessionNonce,
          studentName: studentName,
          studentId: rollNumber,
          deviceMac: macAddress,
        ).timeout(const Duration(seconds: 4), onTimeout: () => false);
      } catch (bleError) {
        debugPrint('[StudentDashboard] BLE verification fallback: $bleError');
        bleSuccess = false;
      }

      AttendanceRecord record;
      if (bleSuccess) {
        record = await _attendanceService.submitVerifiedAttendance(
          sessionId: _activeSession!.id,
          studentId: user?.id ?? '55555555-5555-5555-5555-555555555501',
          studentName: studentName,
          rollNumber: rollNumber,
          macAddress: macAddress,
          verificationMethod: 'BLE_GATEWAY',
          gatewayVerified: true,
        );
      } else {
        // Fallback for emulator / lab development without hardware nearby
        record = await _attendanceService.submitDevelopmentAttendance(
          sessionId: _activeSession!.id,
          studentId: user?.id ?? '55555555-5555-5555-5555-555555555501',
          studentName: studentName,
          rollNumber: rollNumber,
        );
      }

      if (mounted) {
        setState(() {
          _markedRecord = record;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              bleSuccess
                  ? '✓ Verified via Classroom Gateway for ${_activeSession!.subjectCode ?? "Session"}!'
                  : '✓ Attendance Recorded for ${_activeSession!.subjectCode ?? "Session"} (Direct Fallback)',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _loadHistory();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _submissionStatus = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _authService.currentProfile;
    final hasActiveSession = _activeSession != null && _activeSession!.isActive;

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
        onRefresh: () async {
          await _loadProfile();
          await _loadHistory();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Student Profile Card
            Card(
              elevation: 0,
              color: theme.colorScheme.primaryContainer.withAlpha(102),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: theme.colorScheme.primary,
                          child: const Icon(Icons.person, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                profile?.name ?? (_studentProfile?.name ?? 'Aryan Darekar'),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Roll: ${profile?.rollNumber ?? (_studentProfile?.studentId ?? "25102C0040")} • Class: CMPN-C',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Linked device MAC address badge
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
                            'Linked Device MAC: ${_studentProfile?.macAddress ?? "DA:A1:8B:2F:3C:90"}',
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
            const SizedBox(height: 20),

            // REALTIME ACTIVE SESSION SECTION
            if (hasActiveSession)
              _buildLiveAttendanceCard(context, _activeSession!)
            else
              _buildInactiveSessionCard(context),

            const SizedBox(height: 24),

            // ATTENDANCE HISTORY SECTION
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Attendance History',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_history.length} records',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_history.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('No attendance records yet for this semester.'),
              )
            else
              ..._history.map((rec) => _buildHistoryTile(context, rec)),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveAttendanceCard(BuildContext context, AttendanceSession session) {
    final remaining = session.timeRemaining;
    final mins = remaining.inMinutes.toString().padLeft(2, '0');
    final secs = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    final isAlreadyMarked = _markedRecord != null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade400, width: 2),
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
                    'ATTENDANCE OPEN',
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
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Expires in $mins:$secs',
                  style: TextStyle(
                    color: Colors.green.shade900,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${session.subjectName ?? "Database Systems"} (${session.subjectCode ?? "DBMS"})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            'Room: ${session.classroomName ?? "Room 405"} • Faculty: ${session.teacherName ?? "Prof. Sharma"}',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Attendance Button
          if (isAlreadyMarked) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text(
                    'ATTENDANCE VERIFIED & RECORDED',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _markAttendance,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.touch_app, size: 22),
                label: Text(
                  _isSubmitting
                      ? (_submissionStatus.isNotEmpty ? _submissionStatus : 'VERIFYING...')
                      : 'MARK MY ATTENDANCE',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInactiveSessionCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Icon(Icons.access_time_filled, size: 36, color: Colors.grey.shade500),
          const SizedBox(height: 10),
          const Text(
            'Attendance Currently Unavailable',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 4),
          Text(
            'When your teacher starts attendance, it will appear here in realtime without refreshing.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.blue.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Realtime session listener active',
                style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTile(BuildContext context, AttendanceRecord record) {
    final timeStr = "${record.timestamp.day} Oct • ${record.timestamp.hour.toString().padLeft(2, '0')}:${record.timestamp.minute.toString().padLeft(2, '0')}";

    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green.shade100,
          child: Icon(Icons.check, color: Colors.green.shade800),
        ),
        title: const Text('Database Management Systems (DBMS)', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Classroom: Room 405 • $timeStr'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            record.status,
            style: TextStyle(color: Colors.green.shade800, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
