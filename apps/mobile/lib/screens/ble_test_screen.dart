// Student Attendance & BLE Mesh Screen
//
// Features:
// 1. Student Profile (Name, Roll ID, Linked MAC Address)
// 2. Classroom Gateway Connection status
// 3. One-tap "Mark My Attendance" with live verification feedback
// 4. Live Lecture Attendees Roster with Name, Roll ID, and MAC Address
// 5. Mesh Relay Helper toggle
// 6. Diagnostics & Protocol Event Log tab for verification

import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../models/ble_event.dart';
import '../models/attendance_record.dart';

class BleTestScreen extends StatefulWidget {
  const BleTestScreen({super.key});

  @override
  State<BleTestScreen> createState() => _BleTestScreenState();
}

class _BleTestScreenState extends State<BleTestScreen>
    with SingleTickerProviderStateMixin {
  final BleService _bleService = BleService();
  final TextEditingController _messageController =
      TextEditingController(text: 'HELLO-FROM-PHONE');
  late TabController _tabController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _init();
  }

  Future<void> _init() async {
    await _bleService.initialize();
    _bleService.addListener(_onBleUpdate);
    setState(() => _initialized = true);
  }

  void _onBleUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bleService.removeListener(_onBleUpdate);
    _bleService.dispose();
    _messageController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!_initialized) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BLE Relay Test',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              _bleService.isConnected
                  ? 'Connected to ${_bleService.connectedDeviceName}'
                  : 'Classroom Mesh Attendance',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onPrimaryContainer.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Student Profile',
            onPressed: () => _showProfileDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _bleService.clearEvents,
            tooltip: 'Clear log',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary,
          unselectedLabelColor:
              colorScheme.onPrimaryContainer.withValues(alpha: 0.6),
          indicatorColor: colorScheme.primary,
          tabs: const [
            Tab(icon: Icon(Icons.how_to_reg), text: 'Student Attendance'),
            Tab(icon: Icon(Icons.developer_mode), text: 'Diagnostics'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildStudentAttendanceTab(colorScheme),
          _buildDiagnosticsTab(colorScheme),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  TAB 1: STUDENT ATTENDANCE INTERFACE
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildStudentAttendanceTab(ColorScheme colorScheme) {
    return RefreshIndicator(
      onRefresh: () async {
        await _bleService.autoConnectGateway();
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStudentProfileCard(colorScheme),
            const SizedBox(height: 12),
            _buildGatewayStatusCard(colorScheme),
            const SizedBox(height: 16),
            _buildMarkAttendanceHero(colorScheme),
            const SizedBox(height: 16),
            _buildMeshHelperCard(colorScheme),
            const SizedBox(height: 16),
            _buildAttendeesRosterCard(colorScheme),
          ],
        ),
      ),
    );
  }

  // ─── Student Profile Card ──────────────────────────────────────────

  Widget _buildStudentProfileCard(ColorScheme colorScheme) {
    final name = _bleService.studentName.isNotEmpty
        ? _bleService.studentName
        : 'Student (Tap to set name)';
    final roll = _bleService.studentId.isNotEmpty
        ? _bleService.studentId
        : 'ID: Not set';
    final mac = _bleService.macAddress;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified, size: 14, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'BLE INTEROPERABILITY TEST',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'S',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    roll,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fingerprint,
                            size: 12, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'MAC: $mac',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Profile',
              onPressed: () => _showProfileDialog(context),
            ),
          ],
        ),
          ],
        ),
      ),
    );
  }

  // ─── Classroom Gateway Connection Card ─────────────────────────────

  Widget _buildGatewayStatusCard(ColorScheme colorScheme) {
    final isConnected = _bleService.isConnected;
    final gatewayName = _bleService.connectedDeviceName;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isConnected
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isConnected
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.amber.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isConnected ? Icons.router : Icons.wifi_find,
            color: isConnected ? Colors.green : Colors.amber.shade800,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isConnected
                      ? 'Connected to $gatewayName'
                      : 'Classroom Gateway in Proximity',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isConnected ? Colors.green.shade900 : Colors.amber.shade900,
                  ),
                ),
                Text(
                  isConnected
                      ? 'Attendance channel open • ${_bleService.gatewayPeerCount} classmate(s) connected'
                      : 'Tap Connect or Mark Attendance to connect automatically',
                  style: TextStyle(
                    fontSize: 11,
                    color: isConnected
                        ? Colors.green.shade800
                        : Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
          if (!isConnected)
            ElevatedButton(
              onPressed: _bleService.autoConnectGateway,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: const Text('Connect', style: TextStyle(fontSize: 12)),
            )
          else
            TextButton(
              onPressed: _bleService.disconnect,
              child: const Text('Disconnect',
                  style: TextStyle(fontSize: 11, color: Colors.red)),
            ),
        ],
      ),
    );
  }

  // ─── Mark My Attendance Hero Button ────────────────────────────────

  Widget _buildMarkAttendanceHero(ColorScheme colorScheme) {
    final isMarked = _bleService.isAttendanceMarked;
    final isSubmitting = _bleService.isSubmittingAttendance;

    if (isMarked) {
      final timeStr = _bleService.attendanceMarkedTime != null
          ? '${_bleService.attendanceMarkedTime!.hour.toString().padLeft(2, '0')}:${_bleService.attendanceMarkedTime!.minute.toString().padLeft(2, '0')}:${_bleService.attendanceMarkedTime!.second.toString().padLeft(2, '0')}'
          : 'Just now';

      return Card(
        color: Colors.green.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.green.shade400, width: 1.5),
        ),
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 54),
              const SizedBox(height: 10),
              const Text(
                'ATTENDANCE CONFIRMED!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Recorded by Gateway at $timeStr',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.green.shade800,
                ),
              ),
              Text(
                'Linked MAC: ${_bleService.macAddress}',
                style: const TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: isSubmitting ? null : _submitAttendance,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Re-submit Attendance'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade800,
                  side: BorderSide(color: Colors.green.shade400),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [colorScheme.primary, colorScheme.tertiary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          children: [
            const Icon(Icons.how_to_reg, color: Colors.white, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Ready to Mark Attendance',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Transmits your student identity and MAC address over BLE Mesh to the classroom gateway.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: isSubmitting ? null : _submitAttendance,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: colorScheme.primary,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.touch_app, size: 22),
                label: Text(
                  isSubmitting ? 'Recording...' : 'MARK MY ATTENDANCE',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitAttendance() async {
    // If student name is empty, prompt first
    if (_bleService.studentName.trim().isEmpty) {
      final configured = await _showProfileDialog(context);
      if (configured != true) return;
    }

    final success = await _bleService.markAttendance();
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Could not reach gateway. Try moving closer or connecting in Diagnostics tab.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // ─── Mesh Helper Switch ───────────────────────────────────────────

  Widget _buildMeshHelperCard(ColorScheme colorScheme) {
    return Card(
      color: _bleService.relayMode
          ? Colors.blue.withValues(alpha: 0.1)
          : colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.hub,
              color: _bleService.relayMode ? Colors.blue : colorScheme.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Help Classmates (BLE Mesh Relay)',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    _bleService.relayMode
                        ? 'Active — Bouncing attendance for students in weak zones'
                        : 'Toggle on to relay packets for students far from gateway',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _bleService.relayMode,
              onChanged: (_) => _bleService.toggleRelayMode(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Live Lecture Attendees Roster Card ────────────────────────────

  Widget _buildAttendeesRosterCard(ColorScheme colorScheme) {
    final attendees = _bleService.attendees;
    final totalReported = _bleService.classroomAttendeeCount;
    final count = attendees.length > totalReported ? attendees.length : totalReported;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.groups, color: colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Lecture Attendees',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count Present',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            if (attendees.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.person_search,
                          size: 36,
                          color: colorScheme.onSurface.withValues(alpha: 0.3)),
                      const SizedBox(height: 6),
                      Text(
                        'No attendees recorded yet.\nPress "Mark My Attendance" above to record your entry.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: attendees.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (context, index) {
                  final att = attendees[index];
                  return _buildAttendeeTile(att, colorScheme);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendeeTile(AttendanceRecord att, ColorScheme colorScheme) {
    final timeStr =
        '${att.timestamp.hour.toString().padLeft(2, '0')}:${att.timestamp.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor:
              att.isSelf ? colorScheme.primary : colorScheme.secondaryContainer,
          foregroundColor:
              att.isSelf ? colorScheme.onPrimary : colorScheme.onSecondaryContainer,
          child: Text(
            att.studentName.isNotEmpty ? att.studentName[0].toUpperCase() : 'S',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      att.studentName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: att.isSelf ? colorScheme.primary : null,
                      ),
                    ),
                  ),
                  if (att.isSelf) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'You',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${att.studentId} • MAC: ${att.macAddress}',
                style: const TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Icon(
                  att.isConfirmed ? Icons.check_circle : Icons.hourglass_top,
                  size: 14,
                  color: att.isConfirmed ? Colors.green : Colors.amber.shade800,
                ),
                const SizedBox(width: 4),
                Text(
                  att.isConfirmed ? 'PRESENT' : 'PENDING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: att.isConfirmed
                        ? Colors.green
                        : Colors.amber.shade800,
                  ),
                ),
              ],
            ),
            Text(
              '$timeStr • ${att.hopCount == 0 ? "Direct" : "Hop ${att.hopCount}"}',
              style: TextStyle(
                fontSize: 9,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  //  TAB 2: DIAGNOSTICS & TEST PANEL (For verification and testing)
  // ═══════════════════════════════════════════════════════════════════

  Widget _buildDiagnosticsTab(ColorScheme colorScheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDeviceInfoCard(colorScheme),
          const SizedBox(height: 12),
          _buildScanSection(colorScheme),
          const SizedBox(height: 12),
          _buildConnectionSection(colorScheme),
          const SizedBox(height: 12),
          _buildRelaySection(colorScheme),
          const SizedBox(height: 12),
          _buildSendSection(colorScheme),
          const SizedBox(height: 12),
          _buildEventLog(colorScheme),
        ],
      ),
    );
  }

  // ─── Device Info Card (Required by tests & telemetry) ───────────────

  Widget _buildDeviceInfoCard(ColorScheme colorScheme) {
    return Card(
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DIAGNOSTICS & SYSTEM TELEMETRY',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Phase 4 — Cross-Platform Relay & Attendance Protocol',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const Divider(height: 16),
            _infoRow('Student Name', _bleService.studentName, colorScheme),
            _infoRow('Student Roll', _bleService.studentId, colorScheme),
            _infoRow('Linked MAC', _bleService.macAddress, colorScheme),
            _infoRow('Device ID', _bleService.deviceId, colorScheme),
            _infoRow('Platform', _bleService.platform, colorScheme),
            _infoRow('BLE Status', _bleService.bleStatus, colorScheme),
            _infoRow(
                'Relay Mode', _bleService.relayMode ? 'ON' : 'OFF', colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Scan Section ──────────────────────────────────────────────

  Widget _buildScanSection(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth_searching,
                    size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Nearby Devices',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _bleService.isScanning
                      ? _bleService.stopScan
                      : _bleService.startScan,
                  icon: Icon(
                    _bleService.isScanning ? Icons.stop : Icons.search,
                    size: 16,
                  ),
                  label: Text(
                    _bleService.isScanning ? 'Stop' : 'Scan',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_bleService.isScanning) const LinearProgressIndicator(),
            if (_bleService.discoveredDevices.isEmpty && !_bleService.isScanning)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No devices found. Tap Scan.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ..._bleService.discoveredDevices.map((device) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  device.isGateway
                      ? Icons.router
                      : device.isRelay
                          ? Icons.phone_android
                          : Icons.bluetooth,
                  color: device.isGateway
                      ? Colors.green
                      : device.isRelay
                          ? Colors.blue
                          : Colors.grey,
                  size: 20,
                ),
                title: Text(
                  device.name,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '${device.isGateway ? "Gateway" : device.isRelay ? "Relay" : "Device"} • ${device.rssi} dBm',
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: TextButton(
                  onPressed: () => _bleService.connectToDevice(device),
                  child: const Text('Connect', style: TextStyle(fontSize: 11)),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ─── Connection Section ────────────────────────────────────────

  Widget _buildConnectionSection(ColorScheme colorScheme) {
    if (!_bleService.isConnected) return const SizedBox.shrink();

    return Card(
      color: Colors.green.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, color: Colors.green, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connected to ${_bleService.connectedDeviceName}',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const Text(
                        'Ready to transmit attendance packets',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _bleService.disconnect,
                  child: const Text('Disconnect',
                      style: TextStyle(fontSize: 11, color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─── Relay Section ─────────────────────────────────────────────

  Widget _buildRelaySection(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.repeat, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Relay Mode',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Switch(
                  value: _bleService.relayMode,
                  onChanged: (_) => _bleService.toggleRelayMode(),
                ),
              ],
            ),
            if (_bleService.relayMode) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    _bleService.isAdvertising
                        ? Icons.cell_tower
                        : Icons.signal_wifi_off,
                    size: 14,
                    color: _bleService.isAdvertising
                        ? Colors.green
                        : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _bleService.isAdvertising
                        ? 'Advertising — visible to nearby scanners'
                        : 'Not advertising',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── Send Section ──────────────────────────────────────────────

  Widget _buildSendSection(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Diagnostic Test Message',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _messageController,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Enter test payload...',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _bleService.isConnected
                  ? () => _bleService.sendTestPacket(
                        _messageController.text.trim(),
                      )
                  : null,
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Send Test Packet'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Event Log ─────────────────────────────────────────────────

  Widget _buildEventLog(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.list_alt, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  'Event Log',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '${_bleService.events.length} events',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            if (_bleService.events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No events yet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ..._bleService.events.take(30).map((event) {
              final color = _eventColor(event.type);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        event.prefix,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        event.message,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _eventColor(BleEventType type) {
    switch (type) {
      case BleEventType.tx:
        return Colors.blue;
      case BleEventType.rx:
        return Colors.green;
      case BleEventType.forward:
        return Colors.purple;
      case BleEventType.duplicate:
        return Colors.orange;
      case BleEventType.ack:
        return Colors.teal;
      case BleEventType.error:
        return Colors.red;
      case BleEventType.connect:
        return Colors.green;
      case BleEventType.disconnect:
        return Colors.red;
      case BleEventType.scan:
        return Colors.amber;
      case BleEventType.info:
        return Colors.grey;
    }
  }

  // ─── Profile Dialog ────────────────────────────────────────────

  Future<bool?> _showProfileDialog(BuildContext context) async {
    final nameCtrl = TextEditingController(text: _bleService.studentName);
    final rollCtrl = TextEditingController(text: _bleService.studentId);
    final macCtrl = TextEditingController(text: _bleService.macAddress);

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.badge, size: 24),
              SizedBox(width: 8),
              Text('Student Profile', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your identity to record attendance in the lecture.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    hintText: 'e.g. Aryan Sharma',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rollCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Student Roll / ID',
                    hintText: 'e.g. STU-2026-001',
                    prefixIcon: Icon(Icons.numbers),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: macCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Device MAC Address',
                    prefixIcon: Icon(Icons.fingerprint),
                    border: OutlineInputBorder(),
                    helperText: 'Unique identifier linked with your attendance',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isNotEmpty) {
                  await _bleService.updateProfile(
                    name: nameCtrl.text.trim(),
                    studentId: rollCtrl.text.trim(),
                    macAddress: macCtrl.text.trim(),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                }
              },
              child: const Text('Save Profile'),
            ),
          ],
        );
      },
    );
  }
}
