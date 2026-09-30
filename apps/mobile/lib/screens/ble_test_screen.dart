// Phase 4 — BLE Interoperability Test Screen.
//
// Shows device info, scan results, relay controls, and an event log.

import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../models/ble_event.dart';

class BleTestScreen extends StatefulWidget {
  const BleTestScreen({super.key});

  @override
  State<BleTestScreen> createState() => _BleTestScreenState();
}

class _BleTestScreenState extends State<BleTestScreen> {
  final BleService _bleService = BleService();
  final TextEditingController _messageController =
      TextEditingController(text: 'HELLO-FROM-PHONE');
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
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
        title: const Text('BLE Relay Test'),
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _bleService.clearEvents,
            tooltip: 'Clear log',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
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
        ),
      ),
    );
  }

  // ─── Device Info Card ──────────────────────────────────────────

  Widget _buildDeviceInfoCard(ColorScheme colorScheme) {
    return Card(
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'BLE INTEROPERABILITY TEST',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Phase 4 — Cross-Platform Relay',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const Divider(height: 16),
            _infoRow('Device ID', _bleService.deviceId, colorScheme),
            _infoRow('Platform', _bleService.platform, colorScheme),
            _infoRow('BLE Status', _bleService.bleStatus, colorScheme),
            _infoRow('Relay Mode',
                _bleService.relayMode ? 'ON' : 'OFF', colorScheme),
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
            if (_bleService.isScanning)
              const LinearProgressIndicator(),
            if (_bleService.discoveredDevices.isEmpty &&
                !_bleService.isScanning)
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
        child: Row(
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
                    'Ready to send packets',
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
      ),
    );
  }

  // ─── Relay Section ─────────────────────────────────────────────

  Widget _buildRelaySection(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
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
              'Test Message',
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
            const Divider(height: 12),
            if (_bleService.events.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No events yet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ...(_bleService.events.take(30).map((event) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  event.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: _eventColor(event.type, colorScheme),
                  ),
                ),
              );
            })),
          ],
        ),
      ),
    );
  }

  Color _eventColor(BleEventType type, ColorScheme colorScheme) {
    switch (type) {
      case BleEventType.tx:
        return Colors.blue;
      case BleEventType.rx:
        return Colors.green;
      case BleEventType.forward:
        return Colors.orange;
      case BleEventType.duplicate:
        return Colors.amber;
      case BleEventType.ack:
        return Colors.teal;
      case BleEventType.error:
        return Colors.red;
      case BleEventType.connect:
        return Colors.green;
      case BleEventType.disconnect:
        return Colors.red;
      case BleEventType.scan:
        return Colors.purple;
      case BleEventType.info:
        return colorScheme.onSurface.withValues(alpha: 0.6);
    }
  }
}
