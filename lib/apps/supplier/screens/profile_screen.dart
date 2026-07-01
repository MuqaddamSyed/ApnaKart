import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';
import 'earnings_screen.dart';

/// Supplier profile: shop info, link to earnings, logout.
class SupplierProfileScreen extends ConsumerStatefulWidget {
  const SupplierProfileScreen({super.key});
  @override
  ConsumerState<SupplierProfileScreen> createState() => _State();
}

class _State extends ConsumerState<SupplierProfileScreen> {
  Map<String, dynamic>? _shop;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      _shop = await supabase.from('suppliers').select().eq('id', uid).maybeSingle();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.storefront, color: AppColors.primary),
            title: Text(_shop?['shop_name'] ?? 'Your shop'),
            subtitle: Text(_shop?['address'] ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            subtitle: Text((_shop?['category'] as List?)?.join(', ') ?? '-'),
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart),
            title: const Text('Earnings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EarningsScreen())),
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
