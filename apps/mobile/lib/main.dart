import 'package:flutter/material.dart';
import 'core/config/supabase_config.dart';
import 'services/auth_service.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/teacher/screens/teacher_dashboard_screen.dart';
import 'features/student/screens/student_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const BleMeshAttendanceApp());
}

class BleMeshAttendanceApp extends StatelessWidget {
  const BleMeshAttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Classroom BLE Mesh Attendance',
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
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await _authService.checkSession();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = _authService.currentProfile;
    if (profile == null) {
      return const LoginScreen();
    }

    if (profile.isTeacher) {
      return const TeacherDashboardScreen();
    } else {
      return const StudentDashboardScreen();
    }
  }
}
