import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/services/supabase_client.dart';

/// Logo splash that routes by auth state.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final session = supabase.auth.currentSession;
    if (session == null) {
      context.go(Routes.login);
      return;
    }
    // Logged in: send to home if their customer profile exists, else finish onboarding.
    final profile = await supabase
        .from('customers')
        .select('id')
        .eq('id', session.user.id)
        .maybeSingle();
    if (!mounted) return;
    context.go(profile == null ? Routes.onboarding : Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delivery_dining, size: 80, color: Colors.white),
            SizedBox(height: 12),
            Text(AppConstants.appName,
                style: TextStyle(
                    color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
