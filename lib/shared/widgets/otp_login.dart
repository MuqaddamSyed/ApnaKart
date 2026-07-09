import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/providers.dart';
import '../utils/validators.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';

/// Reusable email-OTP login used by customer/supplier/delivery flavors.
/// [role] is written to users.role for a new account. On success calls
/// [onSuccess] with the auth user id and whether the profile was new.
class OtpLogin extends ConsumerStatefulWidget {
  final String role;
  final void Function(String userId, bool isNew) onSuccess;

  /// When false, the phone field is hidden and the user/profile row is NOT
  /// created here — the caller collects phone (and more) afterwards and calls
  /// [AuthService.ensureUserRow] itself. Used by the customer email-only flow.
  final bool collectPhone;

  const OtpLogin({
    super.key,
    required this.role,
    required this.onSuccess,
    this.collectPhone = true,
  });

  @override
  ConsumerState<OtpLogin> createState() => _OtpLoginState();
}

class _OtpLoginState extends ConsumerState<OtpLogin> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _error;

  Future<void> _send() async {
    final emailErr = Validators.email(_emailCtrl.text);
    if (emailErr != null) return setState(() => _error = emailErr);
    // Store-review demo account: skip sending a real OTP, go straight to the
    // code screen (the reviewer enters the fixed bypass code there).
    if (ref.read(authServiceProvider).isReviewer(_emailCtrl.text)) {
      return setState(() { _otpSent = true; _error = null; });
    }
    if (widget.collectPhone) {
      final phoneErr = Validators.phone(_phoneCtrl.text);
      if (phoneErr != null) return setState(() => _error = phoneErr);
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authServiceProvider).sendOTP(_emailCtrl.text.trim());
      setState(() => _otpSent = true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    setState(() { _loading = true; _error = null; });
    try {
      final auth = ref.read(authServiceProvider);
      final email = _emailCtrl.text.trim();
      // Store-review bypass: fixed demo account, no real OTP needed. The demo
      // account already has a complete profile, so skip the phone/row setup.
      final reviewerId = await auth.tryReviewerBypass(email, _otpCtrl.text.trim());
      if (reviewerId != null) {
        final existing = await auth.getCurrentUser();
        final isNew = existing == null || existing.role == null;
        ref.read(currentUserIdProvider.notifier).state = reviewerId;
        widget.onSuccess(reviewerId, isNew);
        return;
      }
      final id = await auth.verifyOTP(email, _otpCtrl.text.trim());
      final existing = await auth.getCurrentUser();
      final isNew = existing == null || existing.role == null;
      if (widget.collectPhone) {
        final phone = Validators.toE164(_phoneCtrl.text);
        await auth.ensureUserRow(email: email, phone: phone, role: widget.role);
        await ref.read(notificationServiceProvider).initFCM(appRole: widget.role);
      }
      ref.read(currentUserIdProvider.notifier).state = id;
      widget.onSuccess(id, isNew);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.delivery_dining, size: 64, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(AppConstants.appName,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          if (!_otpSent) ...[
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Email address',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              onSubmitted: (_) {
                if (!_loading) _send();
              },
            ),
            if (widget.collectPhone) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Phone number for delivery',
                  prefixText: '+91 ',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                onSubmitted: (_) {
                  if (!_loading) _send();
                },
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _send,
              child: _loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send OTP'),
            ),
          ] else ...[
            Text(
              'We sent a login code to ${_emailCtrl.text.trim()}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Enter 6-digit OTP'),
              onSubmitted: (_) {
                if (!_loading) _verify();
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loading ? null : _verify,
              child: _loading
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Verify & Continue'),
            ),
            TextButton(
              onPressed: () => setState(() => _otpSent = false),
              child: const Text('Change email'),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
