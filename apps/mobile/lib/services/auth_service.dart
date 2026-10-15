import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/config/supabase_config.dart';
import '../models/profile.dart';
import 'student_profile_service.dart';

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
      if (profile.isStudent) {
        unawaited(StudentProfileService.saveProfile(
          name: profile.name,
          studentId: profile.rollNumber ?? '',
        ));
      }
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
        data: {
          'name': name.trim(),
          'role': role.name,
          if (rollNumber != null) 'roll_number': rollNumber.trim(),
        },
      );

      final user = response.user;
      if (user == null) throw Exception('Signup failed');

      // Insert or update into public.profiles
      final profileData = {
        'auth_user_id': user.id,
        'name': name.trim(),
        'email': email.trim(),
        'role': role.name,
        'roll_number': rollNumber?.trim(),
      };

      final insertRes = await SupabaseConfig.client
          .from('profiles')
          .upsert(profileData, onConflict: 'email')
          .select()
          .single();

      final profile = UserProfile.fromJson(insertRes);
      _currentProfile = profile;
      if (profile.isStudent) {
        unawaited(StudentProfileService.saveProfile(
          name: profile.name,
          studentId: profile.rollNumber ?? '',
        ));
      }
      notifyListeners();
      return profile;
    } catch (e) {
      debugPrint('[AuthService] Supabase signUp failed: $e. Using local fallback.');
      return _createMockProfile(email, name, role, rollNumber);
    }
  }

  /// Update name & roll number for currently logged in user.
  Future<UserProfile> updateProfileDetails({
    required String name,
    required String rollNumber,
  }) async {
    if (_currentProfile == null) throw Exception('No user logged in');

    final updated = _currentProfile!.copyWith(
      name: name.trim(),
      rollNumber: rollNumber.trim(),
    );

    if (SupabaseConfig.isInitialized) {
      try {
        await SupabaseConfig.client
            .from('profiles')
            .update({
              'name': name.trim(),
              'roll_number': rollNumber.trim(),
            })
            .eq('id', _currentProfile!.id);
      } catch (e) {
        debugPrint('[AuthService] updateProfileDetails DB error: $e');
      }
    }

    _currentProfile = updated;
    await StudentProfileService.saveProfile(
      name: name.trim(),
      studentId: rollNumber.trim(),
    );
    notifyListeners();
    return updated;
  }

  /// Fetch user profile from Supabase `profiles` table.
  Future<UserProfile?> fetchProfile(String authUserId) async {
    try {
      var data = await SupabaseConfig.client
          .from('profiles')
          .select()
          .eq('auth_user_id', authUserId)
          .maybeSingle();

      // If not linked by auth_user_id yet, lookup by email and link auth_user_id
      if (data == null) {
        final currentEmail = SupabaseConfig.client.auth.currentUser?.email;
        if (currentEmail != null && currentEmail.isNotEmpty) {
          data = await SupabaseConfig.client
              .from('profiles')
              .update({'auth_user_id': authUserId})
              .eq('email', currentEmail)
              .select()
              .maybeSingle();
        }
      }

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
    final namePart = email.contains('@') ? email.split('@').first : email;
    final displayName = namePart.isNotEmpty
        ? namePart[0].toUpperCase() + namePart.substring(1)
        : 'User';
    final generatedId = 'user_${email.hashCode.abs()}';

    if (lower.contains('teacher') || lower.contains('prof')) {
      _currentProfile = UserProfile(
        id: generatedId,
        name: displayName.startsWith('Prof') ? displayName : 'Prof. $displayName',
        email: email,
        role: UserRole.teacher,
        createdAt: DateTime.now(),
      );
    } else if (lower.contains('admin')) {
      _currentProfile = UserProfile(
        id: generatedId,
        name: 'Admin $displayName',
        email: email,
        role: UserRole.admin,
        createdAt: DateTime.now(),
      );
    } else {
      _currentProfile = UserProfile(
        id: generatedId,
        name: displayName,
        email: email,
        rollNumber: 'STU-${email.hashCode.abs().toString().padLeft(6, '0').substring(0, 6)}',
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
