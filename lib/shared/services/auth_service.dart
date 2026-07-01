import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import 'supabase_client.dart';

/// Email-OTP auth + user-profile bootstrap.
class AuthService {
  /// Sends an OTP to the email address using Supabase Email Auth.
  Future<void> sendOTP(String email) async {
    await supabase.auth.signInWithOtp(email: email);
  }

  /// Verifies the OTP. Returns the auth user id on success.
  Future<String> verifyOTP(String email, String otp) async {
    final res = await supabase.auth.verifyOTP(
      email: email,
      token: otp,
      type: OtpType.email,
    );
    final user = res.user;
    if (user == null) throw Exception('OTP verification failed');
    return user.id;
  }

  /// Creates the row in `users` for a brand-new account (idempotent).
  Future<void> ensureUserRow({
    required String email,
    required String phone,
    String? name,
    required String role,
  }) async {
    await supabase.rpc('register_user_profile', params: {
      'p_email': email,
      'p_phone': phone,
      'p_name': name,
      'p_role': role,
    });
  }

  Future<AppUser?> getCurrentUser() async {
    final id = supabase.auth.currentUser?.id;
    if (id == null) return null;
    final data = await supabase.from('users').select().eq('id', id).maybeSingle();
    return data == null ? null : AppUser.fromMap(data);
  }

  Future<void> signOut() => supabase.auth.signOut();

  bool get isSignedIn => supabase.auth.currentSession != null;
}
