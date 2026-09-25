import 'package:flutter_test/flutter_test.dart';

import 'package:ble_mesh_attendance/main.dart';

void main() {
  testWidgets('Smoke test for initialization screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const BleMeshAttendanceApp());

    expect(find.text('BLE Mesh Attendance'), findsWidgets);
    expect(find.text('Repository Initialized'), findsOneWidget);
  });
}
