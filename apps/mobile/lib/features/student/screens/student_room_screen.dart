import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/subject.dart';
import '../../../models/attendance_session.dart';
import '../../../models/attendance_record.dart';
import '../../../services/auth_service.dart';
import '../../../services/attendance_service.dart';
import '../../../services/ble_service.dart';
import '../../../services/student_profile_service.dart';
import '../../../screens/ble_test_screen.dart';

class StudentRoomScreen extends StatefulWidget {
  final Subject subject;

  const StudentRoomScreen({super.key, required this.subject});

  @override
  State<StudentRoomScreen> createState() => _StudentRoomScreenState();
}

class _StudentRoomScreenState extends State<StudentRoomScreen> {
  final _authService = AuthService();
  final _attendanceService = AttendanceService();
  final _bleService = BleService();

  AttendanceSession? _activeSession;
  AttendanceRecord? _markedRecord;
  StudentProfile? _studentProfile;
  bool _isSubmitting = false;
  bool _isConnectingGateway = false;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _initSessionSubscription();
    _bleService.addListener(_onBleUpdate);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_activeSession?.isActive == true && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _bleService.removeListener(_onBleUpdate);
    super.dispose();
  }

  void _onBleUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _loadProfile() async {
    final profile = await StudentProfileService.getProfile();
    if (mounted) setState(() => _studentProfile = profile);
  }

  void _initSessionSubscription() {
    _attendanceService.subscribeToSubjectSession(
      subjectId: widget.subject.id,
      onSessionChange: (session) async {
        if (!mounted) return;
        AttendanceRecord? existing;
        if (session != null) {
          final studentId = _authService.currentProfile?.id ?? 'c74da711-97f9-4387-a5cd-a7428bbc6491';
          existing = await _attendanceService.checkExistingAttendance(session.id, studentId);
        }
        if (mounted) {
          setState(() {
            _activeSession = session;
            if (existing != null) {
              _markedRecord = existing;
            } else if (_markedRecord != null && _markedRecord!.sessionId != session?.id) {
              _markedRecord = null;
            }
          });
        }
      },
    );
  }

  Future<void> _handleConnectGateway() async {
    setState(() => _isConnectingGateway = true);
    try {
      await _bleService.initialize();
      final success = await _bleService.autoConnectGateway();
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.bluetooth_connected, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Connected to Gateway: ${_bleService.connectedDeviceName}'),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 3),
          ),
        );
      } else if (!success && mounted) {
        // Show dialog offering simulated gateway option if no hardware is in range
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Gateway Not Found Nearby'),
            content: const Text(
              'No physical ESP32 gateway was detected via BLE advertisement. '
              'Ensure the ESP32 is powered on and within range, or use Simulated Mode for testing.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _bleService.connectSimulatedGateway('BMA-Gateway-01 (Simulated)');
                },
                child: const Text('Connect Simulated Gateway'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('BLE Connect error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnectingGateway = false);
    }
  }

  Future<void> _handleMarkAttendance() async {
    if (_activeSession == null || !_activeSession!.isActive || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    final user = _authService.currentProfile;
    final studentName = user?.name ?? (_studentProfile?.name ?? 'Student');
    final rollNumber = user?.rollNumber ?? (_studentProfile?.studentId ?? 'N/A');
    final macAddress = _studentProfile?.macAddress ?? '';
    final studentId = user?.id ?? 'c74da711-97f9-4387-a5cd-a7428bbc6491';

    try {
      // 1. BLE Gateway transmission with adequate timeout for connect + write + ACK
      bool bleSuccess = false;
      try {
        bleSuccess = await _bleService.markAttendance(
          sessionId: _activeSession!.id,
          sessionNonce: _activeSession!.sessionNonce,
          studentName: studentName,
          studentId: rollNumber,
          deviceMac: macAddress,
        ).timeout(const Duration(seconds: 12), onTimeout: () => false);
      } catch (e) {
        debugPrint('[StudentRoomScreen] BLE transmission note: $e');
        bleSuccess = false;
      }

      // 2. Supabase backend record submission
      AttendanceRecord record;
      if (bleSuccess) {
        record = await _attendanceService.submitVerifiedAttendance(
          sessionId: _activeSession!.id,
          studentId: studentId,
          studentName: studentName,
          rollNumber: rollNumber,
          macAddress: macAddress,
          verificationMethod: 'BLE_GATEWAY',
          gatewayVerified: true,
        );
      } else {
        record = await _attendanceService.submitDevelopmentAttendance(
          sessionId: _activeSession!.id,
          studentId: studentId,
          studentName: studentName,
          rollNumber: rollNumber,
        );
      }

      if (mounted) {
        setState(() => _markedRecord = record);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  bleSuccess ? Icons.verified : Icons.cloud_done,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bleSuccess
                        ? '✓ Verified & Displayed on ESP32 Gateway Screen!'
                        : '⚠ Saved to Cloud only: ESP32 Gateway was not reached.',
                  ),
                ),
              ],
            ),
            backgroundColor: bleSuccess ? Colors.green.shade700 : Colors.orange.shade800,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Submission failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final subject = widget.subject;
    final hasActiveSession = _activeSession != null && _activeSession!.isActive;
    final isAlreadyMarked = _markedRecord != null || _bleService.isAttendanceMarked;
    final isConnectedToGateway = _bleService.isConnected;

    return Scaffold(
      appBar: AppBar(
        title: Text(subject.code.isNotEmpty ? subject.code : subject.name),
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
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final session = await _attendanceService.fetchActiveSessionForSubject(subject.id);
          if (mounted) setState(() => _activeSession = session);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── Room Details Banner ────────────────────────────────
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subject.name,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Class: ${subject.className ?? "Standard"} • Faculty: ${subject.teacherName ?? "Course Faculty"}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (subject.roomCode != null && subject.roomCode!.isNotEmpty)
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: subject.roomCode!));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Room Code "${subject.roomCode}" copied to clipboard!'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    subject.roomCode!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.copy, size: 14, color: Colors.white70),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          subject.scheduleTime ?? '10:00 AM - 11:00 AM',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Icon(Icons.meeting_room_outlined, size: 16, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          subject.classroomName ?? 'Classroom 405',
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Step 1: Gateway Connection ─────────────────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isConnectedToGateway
                      ? (isDark ? const Color(0xFF22C55E) : const Color(0xFF4CAF50))
                      : theme.colorScheme.outlineVariant,
                  width: isConnectedToGateway ? 1.5 : 1.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isConnectedToGateway
                                ? (isDark ? const Color(0xFF144D29) : const Color(0xFFC8E6C9))
                                : theme.colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isConnectedToGateway ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                            color: isConnectedToGateway
                                ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF14532D))
                                : theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Step 1: Classroom Gateway',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                isConnectedToGateway
                                    ? 'Connected: ${_bleService.connectedDeviceName}'
                                    : 'Connect to ESP32 Gateway in classroom',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isConnectedToGateway
                                      ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF14532D))
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: isConnectedToGateway ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isConnectedToGateway
                                ? (isDark ? const Color(0xFF144D29) : const Color(0xFFC8E6C9))
                                : (isDark ? const Color(0xFF334155) : Colors.grey.shade200),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isConnectedToGateway
                                  ? (isDark ? const Color(0xFF22C55E) : const Color(0xFF81C784))
                                  : (isDark ? const Color(0xFF475569) : Colors.grey.shade300),
                            ),
                          ),
                          child: Text(
                            isConnectedToGateway ? 'ONLINE' : 'OFFLINE',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isConnectedToGateway
                                  ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF14532D))
                                  : (isDark ? const Color(0xFF94A3B8) : Colors.grey.shade700),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: isConnectedToGateway
                              ? OutlinedButton.icon(
                                  onPressed: () => _bleService.disconnect(),
                                  icon: const Icon(Icons.close, size: 18),
                                  label: const Text('Disconnect Gateway'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                )
                              : FilledButton.icon(
                                  onPressed: _isConnectingGateway ? null : _handleConnectGateway,
                                  icon: _isConnectingGateway
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Icon(Icons.bluetooth, size: 18),
                                  label: Text(_isConnectingGateway ? 'Scanning...' : 'Connect to Gateway'),
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: 'Hardware Diagnostics',
                          icon: const Icon(Icons.tune),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const BleTestScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ─── Step 2: Attendance Session & Submission ────────────
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: hasActiveSession
                      ? (isDark ? const Color(0xFF22C55E) : const Color(0xFF4CAF50))
                      : theme.colorScheme.outlineVariant,
                  width: hasActiveSession ? 1.5 : 1.0,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: hasActiveSession
                                ? (isDark ? const Color(0xFF144D29) : const Color(0xFFC8E6C9))
                                : theme.colorScheme.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            hasActiveSession ? Icons.sensors : Icons.sensors_off,
                            color: hasActiveSession
                                ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF14532D))
                                : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Step 2: Lecture Attendance',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                hasActiveSession
                                    ? 'Teacher has started recording attendance'
                                    : 'Waiting for teacher to start attendance...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: hasActiveSession
                                      ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF14532D))
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: hasActiveSession ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (isAlreadyMarked) ...[
                      // Confirmed Attendance Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0D3319) : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF22C55E) : const Color(0xFFA5D6A7),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.check_circle,
                              color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                              size: 48,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ATTENDANCE VERIFIED & RECORDED',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isDark ? Colors.white : const Color(0xFF14532D),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Student: ${_authService.currentProfile?.name ?? (_studentProfile?.name ?? "Student")}',
                              style: TextStyle(
                                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Roll: ${_authService.currentProfile?.rollNumber ?? (_studentProfile?.studentId ?? "N/A")} • Method: ${_markedRecord?.verificationMethod ?? "BLE_GATEWAY"}',
                              style: TextStyle(
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (!hasActiveSession) ...[
                      // Session Not Started banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.hourglass_empty, color: theme.colorScheme.onSurfaceVariant, size: 36),
                            const SizedBox(height: 8),
                            Text(
                              'Attendance Session Not Started',
                              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Your teacher will start recording attendance shortly. This page updates automatically in real-time.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Active session countdown
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0D3319) : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF22C55E) : const Color(0xFFA5D6A7),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Time Remaining:',
                                  style: TextStyle(
                                    color: isDark ? Colors.white : const Color(0xFF14532D),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              _activeSession!.timeRemainingFormatted,
                              style: TextStyle(
                                color: isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
                                fontWeight: FontWeight.w900,
                                fontFamily: 'monospace',
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Mark Attendance Action Button
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: (!isConnectedToGateway || _isSubmitting)
                              ? null
                              : _handleMarkAttendance,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.how_to_reg, size: 22),
                          label: Text(
                            !isConnectedToGateway
                                ? 'CONNECT TO GATEWAY FIRST'
                                : (_isSubmitting ? 'RECORDING ATTENDANCE...' : 'MARK MY ATTENDANCE'),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              letterSpacing: 0.6,
                              color: !isConnectedToGateway
                                  ? (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569))
                                  : Colors.white,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF15803D),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            disabledForegroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
