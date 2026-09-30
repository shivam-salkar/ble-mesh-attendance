import 'package:flutter/material.dart';
import 'screens/ble_test_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BleMeshAttendanceApp());
}

class BleMeshAttendanceApp extends StatelessWidget {
  const BleMeshAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Mesh Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const BleTestScreen(),
    );
  }
}
