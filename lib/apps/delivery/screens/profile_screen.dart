import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/routing/app_router.dart';
import '../../../shared/models/delivery_agent.dart';
import '../../../shared/services/providers.dart';
import '../../../shared/services/supabase_client.dart';

/// Delivery agent profile: name, vehicle, lifetime deliveries, logout.
class DeliveryProfileScreen extends ConsumerStatefulWidget {
  const DeliveryProfileScreen({super.key});
  @override
  ConsumerState<DeliveryProfileScreen> createState() => _State();
}

class _State extends ConsumerState<DeliveryProfileScreen> {
  DeliveryAgent? _agent;
  String? _contact;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final user = supabase.auth.currentUser;
    _contact = user?.email ?? user?.phone;
    if (user != null) {
      final row = await supabase.from('delivery_agents').select().eq('id', user.id).maybeSingle();
      if (row != null) _agent = DeliveryAgent.fromMap(row);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(children: [
        const SizedBox(height: 16),
        const CircleAvatar(radius: 36, backgroundColor: AppColors.primary,
            child: Icon(Icons.delivery_dining, color: Colors.white, size: 36)),
        const SizedBox(height: 8),
        Center(child: Text(_contact ?? '', style: const TextStyle(fontWeight: FontWeight.w600))),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.two_wheeler),
          title: const Text('Vehicle type'),
          subtitle: Text(_agent?.vehicleType ?? 'Not set'),
        ),
        ListTile(
          leading: const Icon(Icons.local_shipping),
          title: const Text('Lifetime deliveries'),
          subtitle: Text('${_agent?.totalDeliveries ?? 0}'),
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
      ]),
    );
  }
}
