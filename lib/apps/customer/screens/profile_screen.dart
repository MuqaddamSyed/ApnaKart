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

  /// Permanent account deletion (store requirement). Two-step so it can't be
  /// triggered by accident: explain first, then require typing DELETE.
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final warned = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account, saved addresses and profile. '
          'This cannot be undone.\n\nYour past order history stays with the '
          'shops for their records but is no longer linked to you.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (warned != true || !context.mounted) return;

    final confirmCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Confirm deletion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Type DELETE to confirm.'),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'DELETE'),
                onChanged: (_) => setLocal(() {}),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger),
              onPressed: confirmCtrl.text.trim().toUpperCase() == 'DELETE'
                  ? () => Navigator.pop(ctx, true)
                  : null,
              child: const Text('Delete forever'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await supabase.rpc('delete_my_account');
      await ref.read(authServiceProvider).signOut();
      if (context.mounted) {
        Navigator.pop(context); // close spinner
        context.go(Routes.login);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your account has been deleted.')));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close spinner
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete account: $e')));
      }
    }
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: AppColors.danger),
            title: const Text('Delete account',
                style: TextStyle(color: AppColors.danger)),
            subtitle: const Text('Permanently remove your account and data'),
            onTap: () => _deleteAccount(context, ref),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
