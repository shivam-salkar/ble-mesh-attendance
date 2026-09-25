import 'package:flutter/material.dart';

void main() {
  runApp(const BleMeshAttendanceApp());
}

class BleMeshAttendanceApp extends StatelessWidget {
  const BleMeshAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Mesh Attendance',
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
      home: const InitializationScreen(),
    );
  }
}

class InitializationScreen extends StatelessWidget {
  const InitializationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BLE Mesh Attendance')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.bluetooth_searching, size: 64, color: Colors.indigo),
              SizedBox(height: 24),
              Text(
                'BLE Mesh Attendance',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 12),
              Text(
                'Repository Initialized',
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Application-level peer BLE relay client for classroom attendance.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
