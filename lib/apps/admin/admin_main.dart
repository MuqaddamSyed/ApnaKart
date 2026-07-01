import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/app_constants.dart';
import '../../shared/services/bootstrap.dart';
import 'screens/login_screen.dart';
import 'screens/admin_shell.dart';

/// Admin dashboard entry point (Flutter Web).
Future<void> main() async {
  await bootstrap();
  runApp(const ProviderScope(child: AdminApp()));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '${AppConstants.appName} Admin',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: Supabase.instance.client.auth.currentSession == null
          ? const AdminLoginScreen()
          : const AdminShell(),
    );
  }
}
