import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_mesh_attendance/main.dart';

void main() {
  testWidgets('Smoke test for BLE test screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'bma_device_id': 'TEST-1234'});
    await tester.pumpWidget(const BleMeshAttendanceApp());
    await tester.pump();
    await tester.idle();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('BLE Relay Test'), findsOneWidget);
    expect(find.text('BLE INTEROPERABILITY TEST'), findsOneWidget);
  });
}
