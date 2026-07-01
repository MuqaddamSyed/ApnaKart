import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/services/supabase_client.dart';
import '../../../shared/widgets/otp_login.dart';

/// Customer login: email-only OTP. New users continue to onboarding
/// (phone + address); returning users go straight home.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  Future<void> _route(BuildContext context, String id) async {
    final profile = await supabase
        .from('customers')
        .select('id')
        .eq('id', id)
        .maybeSingle();
    if (!context.mounted) return;
    context.go(profile == null ? Routes.onboarding : Routes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: OtpLogin(
          role: 'customer',
          collectPhone: false,
          onSuccess: (id, isNew) => _route(context, id),
        ),
      ),
    );
  }
}
