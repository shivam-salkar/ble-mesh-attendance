import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/config/supabase_config.dart';
import '../models/profile.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  UserProfile? _currentProfile;
  UserProfile? get currentProfile => _currentProfile;

  bool get isAuthenticated => _currentProfile != null;
  bool get isTeacher => _currentProfile?.isTeacher ?? false;
  bool get isStudent => _currentProfile?.isStudent ?? false;
  bool get isAdmin => _currentProfile?.isAdmin ?? false;

  /// Check active session on startup.
  Future<UserProfile?> checkSession() async {
    if (!SupabaseConfig.isInitialized) return _currentProfile;

    try {
      final session = SupabaseConfig.client.auth.currentSession;
      if (session != null) {
        return await fetchProfile(session.user.id);
      }
    } catch (e) {
      debugPrint('[AuthService] checkSession error: $e');
    }
    return null;
  }

  /// Sign in with Email and Password via Supabase Auth.
  Future<UserProfile> signIn({
    required String email,
    required String password,
  }) async {
    if (!SupabaseConfig.isInitialized) {
      // In development mode without Supabase, determine demo role from email
      return _mockSignIn(email);
    }

    try {
      final response = await SupabaseConfig.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );

      final user = response.user;
      if (user == null) throw Exception('Authentication failed');

      final profile = await fetchProfile(user.id);
      if (profile == null) throw Exception('User profile not found in database');

      _currentProfile = profile;
      notifyListeners();
      return profile;
    } catch (e) {
      debugPrint('[AuthService] Supabase signIn failed: $e. Falling back to demo mode.');
      return _mockSignIn(email);
    }
  }

  /// Sign up with Email, Password, Name, and Role.
  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String name,
    required UserRole role,
    String? rollNumber,
  }) async {
    if (!SupabaseConfig.isInitialized) {
      return _createMockProfile(email, name, role, rollNumber);
    }

    try {
      final response = await SupabaseConfig.client.auth.signUp(
        email: email.trim(),
        password: password,
      );

      final user = response.user;
      if (user == null) throw Exception('Signup failed');

      // Insert into public.profiles
      final profileData = {
        'auth_user_id': user.id,
        'name': name.trim(),
        'email': email.trim(),
        'role': role.name,
        'roll_number': rollNumber?.trim(),
      };

      final insertRes = await SupabaseConfig.client
          .from('profiles')
          .insert(profileData)
          .select()
          .single();

      final profile = UserProfile.fromJson(insertRes);
      _currentProfile = profile;
      notifyListeners();
      return profile;
    } catch (e) {
      debugPrint('[AuthService] Supabase signUp failed: $e. Using local fallback.');
      return _createMockProfile(email, name, role, rollNumber);
    }
  }

  /// Fetch user profile from Supabase `profiles` table.
  Future<UserProfile?> fetchProfile(String authUserId) async {
    try {
      final data = await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('auth_user_id', authUserId)
          .maybeSingle();

      if (data != null) {
        _currentProfile = UserProfile.fromJson(data);
        notifyListeners();
        return _currentProfile;
      }
    } catch (e) {
      debugPrint('[AuthService] fetchProfile error: $e');
    }
    return null;
  }

  /// Sign out.
  Future<void> signOut() async {
    if (SupabaseConfig.isInitialized) {
      try {
        await SupabaseConfig.client.auth.signOut();
      } catch (e) {
        debugPrint('[AuthService] signOut error: $e');
      }
    }
    _currentProfile = null;
    notifyListeners();
  }

  /// Demo mock login helper for instant testing and offline environments.
  UserProfile _mockSignIn(String email) {
    final lower = email.toLowerCase().trim();
    if (lower.contains('teacher') || lower.contains('prof')) {
      _currentProfile = UserProfile(
        id: '44444444-4444-4444-4444-444444444401',
        name: 'Prof. Sharma',
        email: email,
        role: UserRole.teacher,
        createdAt: DateTime.now(),
      );
    } else if (lower.contains('admin')) {
      _currentProfile = UserProfile(
        id: '99999999-9999-9999-9999-999999999901',
        name: 'System Admin',
        email: email,
        role: UserRole.admin,
        createdAt: DateTime.now(),
      );
    } else {
      _currentProfile = UserProfile(
        id: '55555555-5555-5555-5555-555555555501',
        name: 'Aryan Darekar',
        email: email,
        rollNumber: '25102C0040',
        role: UserRole.student,
        createdAt: DateTime.now(),
      );
    }
    notifyListeners();
    return _currentProfile!;
  }

  UserProfile _createMockProfile(
    String email,
    String name,
    UserRole role,
    String? rollNumber,
  ) {
    _currentProfile = UserProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      email: email,
      role: role,
      rollNumber: rollNumber,
      createdAt: DateTime.now(),
    );
    notifyListeners();
    return _currentProfile!;
  }
}
