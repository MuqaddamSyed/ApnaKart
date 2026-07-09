import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import 'supabase_client.dart';

/// Email-OTP auth + user-profile bootstrap.
class AuthService {
  // --- App Store / Play review bypass -------------------------------------
  // OTP-only apps get rejected when the reviewer can't receive the code. This
  // lets a reviewer sign in to ONE pre-created demo customer account without a
  // real email: they enter [reviewerEmail] + [_reviewerCode] and the app signs
  // in with the demo account's password instead of an OTP. The demo account is
  // an ordinary customer with sample data — embedding these is intentional and
  // safe. To disable after review, change the demo account's password in
  // Supabase (sign-in then fails and the normal OTP path is unaffected).
  static const reviewerEmail = 'demo-customer@myminto.in';
  static const _reviewerCode = '424242';
  static const _reviewerPassword = 'REDACTED-ROTATED';

  bool isReviewer(String email) =>
      email.trim().toLowerCase() == reviewerEmail;

  /// If [email]/[code] match the reviewer demo credentials, sign in via
  /// password and return the user id; otherwise return null so the normal OTP
  /// path runs untouched.
  Future<String?> tryReviewerBypass(String email, String code) async {
    if (!isReviewer(email) || code.trim() != _reviewerCode) return null;
    final res = await supabase.auth.signInWithPassword(
      email: reviewerEmail,
      password: _reviewerPassword,
    );
    final user = res.user;
    if (user == null) throw Exception('Reviewer sign-in failed');
    return user.id;
  }

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
