import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';

/// Profile: account, manage addresses, support, logout.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _support() async {
    final uri = Uri.parse('https://wa.me/${AppConstants.supportWhatsApp.replaceAll('+', '')}');
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = supabase.auth.currentUser;
    final contact = user?.email ?? user?.phone ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          const CircleAvatar(radius: 36, backgroundColor: AppColors.primary,
              child: Icon(Icons.person, color: Colors.white, size: 36)),
          const SizedBox(height: 8),
          Center(child: Text(contact, style: const TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Manage addresses'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.addresses),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Help & Support (WhatsApp)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _support,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text('Logout', style: TextStyle(color: AppColors.danger)),
            onTap: () async {
              await ref.read(authServiceProvider).signOut();
              if (context.mounted) context.go(Routes.login);
            },
          ),
        ],
      ),
    );
  }
}
