/// Simple input validators.
class Validators {
  static String? email(String? v) {
    final s = (v ?? '').trim();
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
    if (!ok) return 'Enter a valid email address';
    return null;
  }

  static String? phone(String? v) {
    final s = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (s.length < 10) return 'Enter a valid 10-digit number';
    return null;
  }

  static String? otp(String? v, {int len = 6}) {
    if ((v ?? '').length != len) return 'Enter the $len-digit code';
    return null;
  }

  static String? notEmpty(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  /// Normalises to E.164 with India country code.
  static String toE164(String raw) {
    final s = raw.replaceAll(RegExp(r'\D'), '');
    return s.startsWith('91') ? '+$s' : '+91$s';
  }
}
