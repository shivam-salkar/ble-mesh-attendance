import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ble_mesh_attendance/main.dart';

void main() {
  testWidgets('Smoke test for App booting to Login Screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'bma_device_id': 'TEST-1234'});
    await tester.pumpWidget(const BleMeshAttendanceApp());
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Classroom Attendance'), findsOneWidget);
    expect(find.text('Institutional Email'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('Login screen has quick demo triggers for Teacher, Student and Hardware Diagnostics', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'bma_device_id': 'TEST-1234'});
    await tester.pumpWidget(const BleMeshAttendanceApp());
    await tester.pumpAndSettle();

    expect(find.text('Teacher'), findsOneWidget);
    expect(find.text('Student'), findsOneWidget);
    expect(find.text('Open Hardware & BLE Diagnostics'), findsOneWidget);
  });
}
