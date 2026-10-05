import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // Configurable via --dart-define=SUPABASE_URL=... or overridden at runtime
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://hiqmayrqlqgvxqsaxdkm.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhpcW1heXJxbHFndnhxc2F4ZGttIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyMTM2OTMsImV4cCI6MjEwNjc4OTY5M30.bq3IEkjLRbCStJybuyGv9KMVbtvUY3tglOlIXyWyumw',
  );

  static bool _isInitialized = false;
  static bool get isInitialized => _isInitialized;

  /// Returns the Supabase client instance.
  static SupabaseClient get client => Supabase.instance.client;

  /// Initialize Supabase once at app start.
  static Future<void> initialize({
    String? url,
    String? anonKey,
  }) async {
    final finalUrl = url ?? supabaseUrl;
    final finalAnonKey = anonKey ?? supabaseAnonKey;

    try {
      await Supabase.initialize(
        url: finalUrl,
        // ignore: deprecated_member_use
        anonKey: finalAnonKey,
        debug: true,
      );
      _isInitialized = true;
    } catch (e) {
      // In development or test environments where credentials are mock, handle gracefully
      _isInitialized = false;
    }
  }
}
